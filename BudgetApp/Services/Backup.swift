import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Full JSON snapshot of the database, used for manual backup and restore.
struct BackupFile: Codable {
    struct AccountDTO: Codable {
        var id: UUID, name: String, type: String, initialBalance: Double
        var creditLimit: Double?, paymentDueDay: Int?, isArchived: Bool, sortOrder: Int
        var statementDay: Int?
        var currency: String?
        var groupName: String?
    }
    struct CategoryDTO: Codable {
        var id: UUID, name: String, symbol: String, colorHex: String, kind: String
        var sortOrder: Int, useCount: Int
    }
    struct BudgetDTO: Codable {
        var id: UUID, name: String, symbol: String, amount: Double?, period: String, anchorDay: Int
        var customStart: Date, customEnd: Date, isPinned: Bool, isArchived: Bool, sortOrder: Int
        // Optional so backups made before carry-over existed still decode.
        var carriesOver: Bool?, carryOverspend: Bool?, carryOverStart: Date?
        var showsDaily: Bool?
    }
    struct RuleDTO: Codable {
        var id: UUID, categoryID: UUID?, budgetID: UUID, days: String
        var startMinute: Int, endMinute: Int, sortOrder: Int
    }
    struct AdjustmentDTO: Codable {
        var id: UUID, transferID: UUID, amount: Double, date: Date, note: String
        var budgetID: UUID?, counterpartName: String
    }
    struct EntryDTO: Codable {
        var id: UUID, kind: String, amount: Double, date: Date, name: String, note: String
        var currency: String, createdAt: Date
        var categoryID: UUID?, accountID: UUID?, toAccountID: UUID?, budgetID: UUID?
        var statementOffset: Int?
        var rate: Double?, foreignAmount: Double?, foreignCurrency: String?, toAmount: Double?
    }

    var version = 1
    var exportedAt = Date()
    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var budgets: [BudgetDTO]
    /// Optional so backups made before budget transfers existed still decode.
    var budgetAdjustments: [AdjustmentDTO]?
    /// Optional so backups made before budget rules existed still decode.
    var budgetRules: [RuleDTO]?
    var entries: [EntryDTO]

    @MainActor
    init(context: ModelContext) throws {
        accounts = try context.fetch(FetchDescriptor<Account>()).map {
            AccountDTO(id: $0.id, name: $0.name, type: $0.typeRaw, initialBalance: $0.initialBalance,
                       creditLimit: $0.creditLimit, paymentDueDay: $0.paymentDueDay,
                       isArchived: $0.isArchived, sortOrder: $0.sortOrder, statementDay: $0.statementDay,
                       currency: $0.currency == Currency.base ? nil : $0.currency,
                       groupName: $0.groupName.isEmpty ? nil : $0.groupName)
        }
        categories = try context.fetch(FetchDescriptor<EntryCategory>()).map {
            CategoryDTO(id: $0.id, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                        kind: $0.kindRaw, sortOrder: $0.sortOrder, useCount: $0.useCount)
        }
        budgets = try context.fetch(FetchDescriptor<Budget>()).map {
            BudgetDTO(id: $0.id, name: $0.name, symbol: $0.symbol, amount: $0.amount, period: $0.periodRaw,
                      anchorDay: $0.anchorDay, customStart: $0.customStart, customEnd: $0.customEnd,
                      isPinned: $0.isPinned, isArchived: $0.isArchived, sortOrder: $0.sortOrder,
                      carriesOver: $0.carriesOver, carryOverspend: $0.carryOverspend, carryOverStart: $0.carryOverStart,
                      showsDaily: $0.showsDaily)
        }
        budgetAdjustments = try context.fetch(FetchDescriptor<BudgetAdjustment>()).map {
            AdjustmentDTO(id: $0.id, transferID: $0.transferID, amount: $0.amount, date: $0.date, note: $0.note,
                          budgetID: $0.budget?.id, counterpartName: $0.counterpartName)
        }
        budgetRules = try context.fetch(FetchDescriptor<BudgetRule>()).map {
            RuleDTO(id: $0.id, categoryID: $0.categoryID, budgetID: $0.budgetID, days: $0.daysRaw,
                    startMinute: $0.startMinute, endMinute: $0.endMinute, sortOrder: $0.sortOrder)
        }
        entries = try context.fetch(FetchDescriptor<Entry>()).map {
            EntryDTO(id: $0.id, kind: $0.kindRaw, amount: $0.amount, date: $0.date, name: $0.name,
                     note: $0.note, currency: $0.currency, createdAt: $0.createdAt,
                     categoryID: $0.category?.id, accountID: $0.account?.id,
                     toAccountID: $0.toAccount?.id, budgetID: $0.budget?.id,
                     statementOffset: $0.statementOffset == 0 ? nil : $0.statementOffset,
                     rate: $0.rate == 1 ? nil : $0.rate, foreignAmount: $0.foreignAmount,
                     foreignCurrency: $0.foreignCurrency, toAmount: $0.toAmount)
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Replaces everything in the database with this backup.
    @MainActor
    func restore(into context: ModelContext) throws {
        try context.fetch(FetchDescriptor<Entry>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Account>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<EntryCategory>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<BudgetAdjustment>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Budget>()).forEach(context.delete)
        if let budgetRules {
            try context.fetch(FetchDescriptor<BudgetRule>()).forEach(context.delete)
            for r in budgetRules {
                let m = BudgetRule(categoryID: r.categoryID, budgetID: r.budgetID, days: RuleDays(rawValue: r.days) ?? .everyday,
                                   startMinute: r.startMinute, endMinute: r.endMinute, sortOrder: r.sortOrder)
                m.id = r.id
                context.insert(m)
            }
        }
        try context.save()

        var accountMap: [UUID: Account] = [:]
        for a in accounts {
            let m = Account(name: a.name, type: AccountType(rawValue: a.type) ?? .other,
                            initialBalance: a.initialBalance, sortOrder: a.sortOrder)
            m.id = a.id
            m.creditLimit = a.creditLimit
            m.paymentDueDay = a.paymentDueDay
            m.statementDay = a.statementDay
            m.currency = a.currency ?? Currency.base
            m.groupName = a.groupName ?? ""
            m.isArchived = a.isArchived
            context.insert(m)
            accountMap[a.id] = m
        }
        var categoryMap: [UUID: EntryCategory] = [:]
        for c in categories {
            let m = EntryCategory(name: c.name, symbol: c.symbol, colorHex: c.colorHex,
                                  kind: EntryKind(rawValue: c.kind) ?? .expense, sortOrder: c.sortOrder)
            m.id = c.id
            m.useCount = c.useCount
            context.insert(m)
            categoryMap[c.id] = m
        }
        var budgetMap: [UUID: Budget] = [:]
        for b in budgets {
            let m = Budget(name: b.name, symbol: b.symbol, amount: b.amount,
                           period: BudgetPeriod(rawValue: b.period) ?? .monthly, anchorDay: b.anchorDay)
            m.id = b.id
            m.customStart = b.customStart
            m.customEnd = b.customEnd
            m.isPinned = b.isPinned
            m.isArchived = b.isArchived
            m.sortOrder = b.sortOrder
            m.carriesOver = b.carriesOver ?? false
            m.carryOverspend = b.carryOverspend ?? true
            m.carryOverStart = b.carryOverStart
            m.showsDaily = b.showsDaily ?? false
            context.insert(m)
            budgetMap[b.id] = m
        }
        for a in budgetAdjustments ?? [] {
            guard let budget = a.budgetID.flatMap({ budgetMap[$0] }) else { continue }
            let m = BudgetAdjustment(transferID: a.transferID, amount: a.amount, date: a.date, budget: budget,
                                     counterpartName: a.counterpartName, note: a.note)
            m.id = a.id
            context.insert(m)
        }
        for e in entries {
            let m = Entry(kind: EntryKind(rawValue: e.kind) ?? .expense, amount: e.amount, date: e.date, name: e.name,
                          category: e.categoryID.flatMap { categoryMap[$0] },
                          account: e.accountID.flatMap { accountMap[$0] },
                          toAccount: e.toAccountID.flatMap { accountMap[$0] },
                          budget: e.budgetID.flatMap { budgetMap[$0] })
            m.id = e.id
            m.note = e.note
            m.currency = e.currency
            m.createdAt = e.createdAt
            m.statementOffset = e.statementOffset ?? 0
            m.rate = e.rate ?? 1
            m.foreignAmount = e.foreignAmount
            m.foreignCurrency = e.foreignCurrency
            m.toAmount = e.toAmount
            context.insert(m)
        }
        try context.save()
    }
}

/// Wraps backup data for `.fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
