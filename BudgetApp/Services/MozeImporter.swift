import Foundation
import SwiftData

/// Imports a MOZE CSV export. MOZE's column names differ by app language, so headers are
/// matched against Chinese and English aliases.
@MainActor
struct MozeImporter {
    struct Summary {
        var entries = 0
        var transfers = 0
        var newAccounts = 0
        var newCategories = 0
        var newBudgets = 0
        var skipped = 0
    }

    enum ImportError: LocalizedError {
        case missingColumns(found: [String])
        var errorDescription: String? {
            switch self {
            case .missingColumns(let found):
                "看不懂這個 CSV，找不到「金額」或「日期」欄位。檔案的欄位是：\(found.joined(separator: "、"))"
            }
        }
    }

    private static let aliases: [String: [String]] = [
        "account": ["帳戶", "Account"],
        "type": ["記錄類型", "類型", "Type", "Record Type"],
        "main": ["主類別", "Main Category", "Category"],
        "sub": ["子類別", "Subcategory", "Sub Category"],
        "amount": ["金額", "Price", "Amount"],
        "name": ["名稱", "Name"],
        "store": ["商家", "Store", "Merchant"],
        "date": ["日期", "Date"],
        "time": ["時間", "Time"],
        "project": ["專案", "Project"],
        "description": ["描述", "備註", "Description", "Note"],
    ]

    let context: ModelContext
    private var accounts: [String: Account] = [:]
    private var categories: [String: EntryCategory] = [:]
    private var budgets: [String: Budget] = [:]
    private var createdBudgets: [Budget] = []
    private var summary = Summary()

    init(context: ModelContext) {
        self.context = context
    }

    mutating func run(csv text: String) throws -> Summary {
        let rows = CSV.parse(text)
        guard let header = rows.first else { return summary }
        var column: [String: Int] = [:]
        for (key, names) in Self.aliases {
            if let i = header.firstIndex(where: { h in names.contains { $0.caseInsensitiveCompare(h.trimmingCharacters(in: .whitespaces)) == .orderedSame } }) {
                column[key] = i
            }
        }
        guard column["amount"] != nil, column["date"] != nil else {
            throw ImportError.missingColumns(found: header)
        }

        for a in try context.fetch(FetchDescriptor<Account>()) { accounts[a.name] = a }
        for c in try context.fetch(FetchDescriptor<EntryCategory>()) { categories["\(c.kindRaw)|\(c.name)"] = c }
        for b in try context.fetch(FetchDescriptor<Budget>()) { budgets[b.name] = b }

        // MOZE stores a transfer as two rows (out + in); pair them up by time and amount.
        var pendingTransfers: [(key: String, isOut: Bool, account: Account, date: Date, name: String)] = []

        for row in rows.dropFirst() {
            func field(_ key: String) -> String {
                guard let i = column[key], i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let rawAmount = field("amount").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            guard let amount = Double(rawAmount), amount != 0,
                  let date = Self.parseDate(field("date"), time: field("time")) else {
                summary.skipped += 1
                continue
            }
            let type = field("type")
            let account = account(named: field("account"))
            let name = [field("name"), field("store")].first { !$0.isEmpty } ?? ""
            let note = field("description")

            if Self.isTransfer(type) {
                let isOut = type.contains("出") || type.localizedCaseInsensitiveContains("out") || amount < 0
                let key = "\(field("date"))|\(field("time"))|\(abs(amount))"
                if let i = pendingTransfers.firstIndex(where: { $0.key == key && $0.isOut != isOut }) {
                    let other = pendingTransfers.remove(at: i)
                    let entry = Entry(kind: .transfer, amount: abs(amount), date: date, name: name.isEmpty ? other.name : name,
                                      account: isOut ? account : other.account,
                                      toAccount: isOut ? other.account : account)
                    entry.note = note
                    context.insert(entry)
                    summary.transfers += 1
                } else {
                    pendingTransfers.append((key, isOut, account, date, name))
                }
                continue
            }

            let kind: EntryKind
            if type.contains("收入") || type.localizedCaseInsensitiveContains("income") {
                kind = .income
            } else if type.contains("支出") || type.localizedCaseInsensitiveContains("expense") {
                kind = .expense
            } else {
                kind = amount < 0 ? .expense : .income // balance adjustments, receivables, refunds
            }
            let categoryName = [field("sub"), field("main"), type].first { !$0.isEmpty } ?? "其他"
            let entry = Entry(kind: kind, amount: abs(amount), date: date, name: name,
                              category: category(named: categoryName, kind: kind),
                              account: account, budget: budget(named: field("project")))
            entry.note = note
            context.insert(entry)
            summary.entries += 1
        }

        // Transfers whose other half isn't in the file (e.g. to an account outside MOZE).
        for p in pendingTransfers {
            let kind: EntryKind = p.isOut ? .expense : .income
            let amount = Double(p.key.split(separator: "|").last ?? "") ?? 0
            context.insert(Entry(kind: kind, amount: amount, date: p.date, name: p.name,
                                 category: category(named: "轉帳", kind: kind), account: p.account))
            summary.entries += 1
        }

        // Budgets created from MOZE projects span their entries; archive ones unused for 60 days.
        try context.save()
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: .now)!
        for budget in createdBudgets {
            let dates = (budget.entries ?? []).map(\.date)
            budget.customStart = dates.min() ?? .now
            budget.customEnd = dates.max() ?? .now
            budget.isArchived = budget.customEnd < cutoff
        }

        try context.save()
        return summary
    }

    private static func isTransfer(_ type: String) -> Bool {
        type.contains("轉") || type.localizedCaseInsensitiveContains("transfer")
    }

    private mutating func account(named raw: String) -> Account {
        let name = raw.isEmpty ? "錢包" : raw
        if let a = accounts[name] { return a }
        let lower = name.lowercased()
        let type: AccountType =
            name.contains("卡") || lower.contains("card") ? .creditCard :
            name.contains("現金") || name.contains("錢包") || lower.contains("wallet") || lower.contains("cash") ? .cash : .bank
        let a = Account(name: name, type: type, sortOrder: accounts.count)
        context.insert(a)
        accounts[name] = a
        summary.newAccounts += 1
        return a
    }

    private mutating func category(named name: String, kind: EntryKind) -> EntryCategory {
        let key = "\(kind.rawValue)|\(name)"
        if let c = categories[key] { return c }
        let c = EntryCategory(name: name, symbol: kind == .expense ? "tag" : "dollarsign.circle",
                              colorHex: Palette.colors[categories.count % Palette.colors.count],
                              kind: kind, sortOrder: 100 + categories.count)
        context.insert(c)
        categories[key] = c
        summary.newCategories += 1
        return c
    }

    private mutating func budget(named name: String) -> Budget? {
        guard !name.isEmpty else { return nil }
        if let b = budgets[name] { return b }
        let b = Budget(name: name, amount: nil, period: .custom)
        b.sortOrder = 100 + budgets.count
        context.insert(b)
        budgets[name] = b
        createdBudgets.append(b)
        summary.newBudgets += 1
        return b
    }

    static func parseDate(_ date: String, time: String) -> Date? {
        let parts = date.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        // Accept both yyyy/MM/dd and MM/dd/yyyy.
        let (y, m, d) = parts[0] > 31 ? (parts[0], parts[1], parts[2]) : (parts[2], parts[0], parts[1])
        let t = time.split(separator: ":").compactMap { Int($0) }
        var comps = DateComponents(year: y < 100 ? 2000 + y : y, month: m, day: d)
        comps.hour = t.first ?? 12
        comps.minute = t.count > 1 ? t[1] : 0
        return Calendar.current.date(from: comps)
    }
}

enum CSV {
    /// RFC 4180-ish parser: quoted fields, escaped quotes, CRLF.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }

        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r", let n = next(), n != "\n" { pending = n }
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else if c != "\u{FEFF}" {
                field.unicodeScalars.append(c)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
