import Foundation
import PDFKit
import Security

/// A credit card bill read from the bank's PDF (on device, no network).
struct ParsedStatement {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        /// 消費日
        var date: Date
        var name: String
        /// From the card's side: charges positive, refunds and payments negative.
        var amount: Double
        /// Payment to the card (自動扣繳, 繳款) rather than a charge or refund.
        var isPayment: Bool

        static func == (a: Item, b: Item) -> Bool {
            a.date == b.date && a.name == b.name && a.amount == b.amount && a.isPayment == b.isPayment
        }
    }

    var closingDate: Date?
    /// 本期新增款項: charges minus refunds, without payments.
    var newCharges: Double?
    /// 本期累計應繳金額
    var amountDue: Double?
    var items: [Item] = []

    var charges: [Item] { items.filter { !$0.isPayment } }
    var payments: [Item] { items.filter(\.isPayment) }

    enum Failure: Error { case unreadable, locked, wrongPassword, noItems }

    /// Opens the PDF, unlocking it with `password` when it has one, and reads the text.
    static func read(_ data: Data, password: String?) throws -> ParsedStatement {
        guard let doc = PDFDocument(data: data) else { throw Failure.unreadable }
        if doc.isLocked {
            guard let password, !password.isEmpty else { throw Failure.locked }
            guard doc.unlock(withPassword: password) else { throw Failure.wrongPassword }
        }
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        let parsed = parse(text)
        if parsed.items.isEmpty { throw Failure.noItems }
        return parsed
    }

    static func isLocked(_ data: Data) -> Bool { PDFDocument(data: data)?.isLocked ?? false }

    // MARK: Text

    private static let dateToken = #"(\d{7}|\d{3,4}/\d{1,2}/\d{1,2}|\d{1,2}/\d{1,2})"#
    private static let amountToken = #"(-?[\d,]+(?:\.\d+)?)"#
    /// 消費日 入帳日 明細 金額 [外幣折算日 消費地 幣別 外幣金額]
    private static let foreignLine = try! NSRegularExpression(pattern:
        "^\(dateToken)\\s+\(dateToken)\\s+(.+?)\\s+\(amountToken)\\s+\(dateToken)\\s+[A-Z]{2}\\s+[A-Z]{3}\\s+[\\d,.]+$")
    /// 消費日 入帳日 明細 金額 [消費地]
    private static let localLine = try! NSRegularExpression(pattern:
        "^\(dateToken)\\s+\(dateToken)\\s+(.+)\\s+\(amountToken)(?:\\s+[A-Z]{2})?$")

    static func parse(_ text: String) -> ParsedStatement {
        var result = ParsedStatement()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        // Header first: short dates (MM/DD) take their year from the closing date.
        for line in lines {
            if result.closingDate == nil, line.contains("結帳日"),
               let token = firstMatch(#"\d{3,4}/\d{1,2}/\d{1,2}"#, in: line) {
                result.closingDate = date(from: token, near: nil)
            }
            if result.newCharges == nil, line.contains("本期新增款項") {
                result.newCharges = trailingAmount(line)
            }
            if result.amountDue == nil, line.contains("本期累計應繳") || line.contains("本期應繳總額") {
                result.amountDue = trailingAmount(line)
            }
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = foreignLine.firstMatch(in: line, range: range) ?? localLine.firstMatch(in: line, range: range),
                  let dateText = Range(m.range(at: 1), in: line).map({ String(line[$0]) }),
                  let nameText = Range(m.range(at: 3), in: line).map({ String(line[$0]) }),
                  let amountText = Range(m.range(at: 4), in: line).map({ String(line[$0]) }),
                  let date = date(from: dateText, near: result.closingDate),
                  let amount = number(amountText) else { continue }
            let name = nameText.trimmingCharacters(in: .whitespaces)
            let isPayment = amount < 0 && (name.contains("繳") || name.contains("付款") || name.contains("還款"))
            result.items.append(Item(date: date, name: name, amount: amount, isPayment: isPayment))
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    private static func trailingAmount(_ line: String) -> Double? {
        firstMatch(#"-?[\d,]+(\.\d+)?$"#, in: line).flatMap(number)
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    /// 1151022, 115/10/22, 2026/10/22 or 10/22 (民國 years are below 1911).
    static func date(from token: String, near closing: Date?) -> Date? {
        let cal = Calendar.current
        var parts: [Int]
        if token.count == 7, !token.contains("/") {
            let digits = Array(token)
            parts = [String(digits[0..<3]), String(digits[3..<5]), String(digits[5..<7])].compactMap { Int($0) }
        } else {
            parts = token.split(separator: "/").compactMap { Int($0) }
        }
        if parts.count == 2 {
            guard let closing else { return nil }
            let c = cal.dateComponents([.year, .month], from: closing)
            // A December charge on a January bill belongs to the year before.
            parts.insert(parts[0] > c.month! ? c.year! - 1 : c.year!, at: 0)
        }
        guard parts.count == 3 else { return nil }
        let year = parts[0] < 1911 ? parts[0] + 1911 : parts[0]
        guard (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return cal.date(from: DateComponents(year: year, month: parts[1], day: parts[2]))
    }
}

/// Bill lines matched against an account's records.
struct StatementReconciliation {
    struct Match: Identifiable {
        var id: UUID { item.id }
        let item: ParsedStatement.Item
        let entry: Entry
        /// The record is counted in a different bill in the app (date or 移到下期).
        let otherBill: Bool
    }

    var matched: [Match] = []
    /// On the bill but not recorded.
    var missing: [ParsedStatement.Item] = []
    /// In this bill in the app but not on the bank's.
    var extra: [Entry] = []
    /// The app's bill the statement was compared with.
    var interval: DateInterval?
    /// What the app bills for the period (charges minus refunds).
    var appTotal: Double = 0

    var allMatch: Bool { missing.isEmpty && extra.isEmpty }

    /// How far apart a bill line and a record may be dated and still be the same purchase.
    static let maxDays = 7

    /// The app's bill closing nearest the bank's 結帳日, so a 出帳日 a day or two off still lands on it.
    static func defaultInterval(for statement: ParsedStatement, account: Account,
                                calendar: Calendar = .current) -> DateInterval? {
        let closing = statement.closingDate ?? statement.items.map(\.date).max() ?? .now
        guard let containing = account.statementInterval(containing: closing, calendar: calendar) else { return nil }
        let candidates = [-1, 0, 1].compactMap { account.statementInterval(offset: $0, from: containing, calendar: calendar) }
        return candidates.min { abs($0.closingDate.timeIntervalSince(closing)) < abs($1.closingDate.timeIntervalSince(closing)) }
    }

    /// Compares with the app's bill `interval` (default: `defaultInterval`).
    init(statement: ParsedStatement, account: Account, interval chosen: DateInterval? = nil,
         calendar: Calendar = .current) {
        let closing = statement.closingDate ?? statement.items.map(\.date).max() ?? .now
        interval = chosen ?? Self.defaultInterval(for: statement, account: account, calendar: calendar)
        let earliest = statement.items.map(\.date).min() ?? closing
        let billed: [Entry]
        let payments: [Entry]
        if let interval {
            billed = account.statementEntries(in: interval)
            payments = account.statementPayments(in: interval)
        } else {
            // No 出帳日 set: compare with what's dated within the bill's lines.
            let end = calendar.date(byAdding: .day, value: 1, to: closing)!
            billed = (account.entries ?? []).filter { $0.date >= earliest && $0.date < end }
            payments = (account.incomingTransfers ?? []).filter { $0.date >= earliest && $0.date < end }
        }
        appTotal = billed.reduce(0) { $0 + Self.cardAmount($1, account: account) }

        let inBill = Set((billed + payments).map(\.persistentModelID))
        var pool = (account.entries ?? []) + (account.incomingTransfers ?? [])
        // Exact dates first, so two same-priced lunches pair up with the right days.
        let items = statement.items.sorted { $0.date < $1.date }
        var unmatched: [ParsedStatement.Item] = []
        for item in items {
            let candidates = pool.enumerated().compactMap { index, entry -> (Int, Int, Bool)? in
                guard abs(Self.cardAmount(entry, account: account) - item.amount) < 0.5 else { return nil }
                let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: item.date),
                                                       to: calendar.startOfDay(for: entry.date)).day ?? 99)
                let isIn = inBill.contains(entry.persistentModelID)
                guard isIn || days <= Self.maxDays else { return nil }
                return (index, days, isIn)
            }
            // Prefer records in this bill, then the closest date.
            if let best = candidates.min(by: { ($0.2 ? 0 : 1, $0.1) < ($1.2 ? 0 : 1, $1.1) }) {
                let entry = pool.remove(at: best.0)
                matched.append(Match(item: item, entry: entry, otherBill: !best.2))
            } else {
                unmatched.append(item)
            }
        }
        missing = unmatched
        let used = Set(matched.map(\.entry.persistentModelID))
        extra = (billed + payments).filter { !used.contains($0.persistentModelID) }.sorted { $0.date < $1.date }
    }

    /// An entry's effect from the card's side, like the bill shows it: charges positive.
    static func cardAmount(_ entry: Entry, account: Account) -> Double {
        if entry.toAccount?.persistentModelID == account.persistentModelID,
           entry.account?.persistentModelID != account.persistentModelID {
            return -(entry.toAmount ?? entry.amount)
        }
        return entry.kind == .income ? -entry.amount : entry.amount
    }
}

/// PDF passwords kept in this device's keychain only (never synced or backed up), one per card.
enum StatementPasswords {
    private static let service = "com.hongping.budgetapp.statement-pdf"

    private static func query(_ accountID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: accountID.uuidString]
    }

    static func load(for accountID: UUID) -> String? {
        var q = query(accountID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String, for accountID: UUID) {
        delete(for: accountID)
        var q = query(accountID)
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(for accountID: UUID) {
        SecItemDelete(query(accountID) as CFDictionary)
    }
}
