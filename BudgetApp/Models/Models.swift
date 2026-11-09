import Foundation
import SwiftData

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case expense, income, transfer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "轉帳"
        }
    }
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash, creditCard, bank, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cash: "現金"
        case .creditCard: "信用卡"
        case .bank: "銀行"
        case .other: "其他"
        }
    }
    var symbol: String {
        switch self {
        case .cash: "banknote"
        case .creditCard: "creditcard"
        case .bank: "building.columns"
        case .other: "tray"
        }
    }
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: "每週"
        case .monthly: "每月"
        case .custom: "自訂期間"
        }
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.cash.rawValue
    /// Balance before any recorded entry. Editing "current balance" adjusts this.
    var initialBalance: Double = 0
    var creditLimit: Double?
    /// Day of month the credit card bill is due.
    var paymentDueDay: Int?
    /// Day of month the credit card statement closes (出帳日); nil = not set.
    var statementDay: Int?
    /// Currency the balance and its entries are kept in.
    var currency: String = "TWD"
    /// Bank or other group this account is listed under with a total; empty = on its own.
    var groupName: String = ""
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Entry.account)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .nullify, inverse: \Entry.toAccount)
    var incomingTransfers: [Entry]? = []

    init(name: String, type: AccountType, initialBalance: Double = 0, sortOrder: Int = 0) {
        self.name = name
        self.typeRaw = type.rawValue
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var balance: Double { balance(upTo: nil) }

    /// Balance including entries strictly before `date` (all entries when nil).
    func balance(upTo date: Date?) -> Double {
        var total = initialBalance
        for e in entries ?? [] where date == nil || e.date < date! {
            switch e.kind {
            case .expense, .transfer: total -= e.amount
            case .income: total += e.amount
            }
        }
        for e in incomingTransfers ?? [] where date == nil || e.date < date! {
            total += e.toAmount ?? e.amount
        }
        return total
    }

    var entryCount: Int { (entries?.count ?? 0) + (incomingTransfers?.count ?? 0) }

    /// Name with its group, for lists where accounts from different groups mix.
    var fullName: String { groupName.isEmpty ? name : "\(groupName)・\(name)" }

    /// Balance in TWD at today's rate, for net worth.
    var baseBalance: Double { balance * Currency.rate(currency) }
}

/// A row in the 帳戶 list: an account on its own, or a group of them with a total.
enum AccountListItem: Identifiable {
    case single(Account)
    case group(name: String, accounts: [Account])

    var id: String {
        switch self {
        case .single(let account): account.id.uuidString
        case .group(let name, _): "group-" + name
        }
    }

    /// Accounts in list order; a group sits where its first account is.
    static func items(for accounts: [Account]) -> [AccountListItem] {
        var seen = Set<String>()
        return accounts.compactMap { account in
            if account.groupName.isEmpty { return .single(account) }
            guard seen.insert(account.groupName).inserted else { return nil }
            return .group(name: account.groupName, accounts: accounts.filter { $0.groupName == account.groupName })
        }
    }

    /// A group's total: in its currency when all its accounts share one, otherwise in TWD.
    static func total(of accounts: [Account]) -> (amount: Double, currency: String) {
        if let currency = accounts.first?.currency, accounts.allSatisfy({ $0.currency == currency }) {
            return (accounts.reduce(0) { $0 + $1.balance }, currency)
        }
        return (accounts.reduce(0) { $0 + $1.baseBalance }, Currency.base)
    }
}

@Model
final class EntryCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "ellipsis"
    var colorHex: String = "#8A9099"
    var kindRaw: String = EntryKind.expense.rawValue
    var sortOrder: Int = 0
    var useCount: Int = 0
    var lastUsed: Date?

    @Relationship(deleteRule: .nullify, inverse: \Entry.category)
    var entries: [Entry]? = []

    init(name: String, symbol: String, colorHex: String, kind: EntryKind, sortOrder: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "target"
    /// nil = no limit, only tracks the total like a MOZE project.
    var amount: Double?
    var periodRaw: String = BudgetPeriod.monthly.rawValue
    /// Weekly: Calendar weekday (1 = Sunday). Monthly: day of month the period starts.
    var anchorDay: Int = 1
    var customStart: Date = Date()
    var customEnd: Date = Date()
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0
    /// Roll each period's leftover (or overspend) into the next one, starting from `carryOverStart`.
    var carriesOver: Bool = false
    /// When false, overspending is forgiven instead of reducing the next period.
    var carryOverspend: Bool = true
    var carryOverStart: Date?
    /// Show the amount usable per day, with a bar for today, on this budget's row.
    var showsDaily: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Entry.budget)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \BudgetAdjustment.budget)
    var adjustments: [BudgetAdjustment]? = []

    init(name: String, symbol: String = "target", amount: Double?, period: BudgetPeriod, anchorDay: Int = 1) {
        self.name = name
        self.symbol = symbol
        self.amount = amount
        self.periodRaw = period.rawValue
        self.anchorDay = anchorDay
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }
}

/// One side of a budget-to-budget transfer: adds `amount` (negative = given away) to the
/// budget's period containing `date`. Both sides share a `transferID`.
@Model
final class BudgetAdjustment {
    var id: UUID = UUID()
    var transferID: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date()
    var note: String = ""
    var budget: Budget?
    /// Name of the budget on the other side, for display.
    var counterpartName: String = ""

    init(transferID: UUID, amount: Double, date: Date, budget: Budget, counterpartName: String, note: String = "") {
        self.transferID = transferID
        self.amount = amount
        self.date = date
        self.budget = budget
        self.counterpartName = counterpartName
        self.note = note
    }
}

@Model
final class Entry {
    var id: UUID = UUID()
    var kindRaw: String = EntryKind.expense.rawValue
    /// Always positive; `kind` decides the direction.
    var amount: Double = 0
    var date: Date = Date()
    var name: String = ""
    var note: String = ""
    /// Currency of `amount`: the account's.
    var currency: String = "TWD"
    /// TWD for one unit of `currency` when this was recorded.
    var rate: Double = 1
    /// What was actually paid when it was in another currency than the account's (e.g. ¥ on a TWD card).
    var foreignAmount: Double?
    var foreignCurrency: String?
    /// Transfers between accounts in different currencies: what arrived, in the destination's currency.
    var toAmount: Double?
    var createdAt: Date = Date()

    var category: EntryCategory?
    /// Source account (the paying account for transfers).
    var account: Account?
    /// Destination account, transfers only.
    var toAccount: Account?
    var budget: Budget?
    /// Credit cards: how many statements later than its date this entry is billed
    /// (moved to the next bill because the bank hasn't posted it yet).
    var statementOffset: Int = 0

    init(kind: EntryKind, amount: Double, date: Date, name: String = "",
         category: EntryCategory? = nil, account: Account? = nil,
         toAccount: Account? = nil, budget: Budget? = nil) {
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.date = date
        self.name = name
        self.category = category
        self.account = account
        self.toAccount = toAccount
        self.budget = budget
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// Amount in TWD, for totals across currencies.
    var baseAmount: Double { currency == Currency.base ? amount : amount * rate }

    /// Signed TWD amount from the owner's point of view (expense negative).
    var signedAmount: Double {
        switch kind {
        case .expense: -baseAmount
        case .income: baseAmount
        case .transfer: 0
        }
    }

    /// Sets the amount (in the account's currency) and, for transfers between currencies, what arrived
    /// as typed by hand. Keeps the recorded rate unless the account's currency changed. A transfer
    /// between TWD and another currency also updates that currency's rate (設定 → 匯率) to the one
    /// it implies, so totals follow the rate actually exchanged at.
    func setAmount(_ value: Double, toAmount arrived: Double? = nil) {
        let accountCurrency = account?.currency ?? Currency.base
        amount = value
        foreignAmount = nil
        foreignCurrency = nil
        if currency != accountCurrency || rate <= 0 {
            currency = accountCurrency
            rate = Currency.rate(accountCurrency)
        }
        guard kind == .transfer, let to = toAccount, to.currency != accountCurrency, let arrived, arrived > 0 else {
            toAmount = nil
            return
        }
        toAmount = arrived
        if accountCurrency == Currency.base {
            Currency.setRate(value / arrived, for: to.currency)
        } else if to.currency == Currency.base {
            Currency.setRate(arrived / value, for: accountCurrency)
            rate = arrived / value
        }
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if kind == .transfer { return "轉帳" }
        return category?.name ?? "未分類"
    }
}
