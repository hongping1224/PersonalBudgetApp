import Foundation
import SwiftData

@MainActor
enum DataStore {
    static let schema = Schema([Account.self, EntryCategory.self, Budget.self, BudgetAdjustment.self, Entry.self,
                                BudgetRule.self])

    /// Shared by the app and the Siri / Shortcuts intents, which run in the same process.
    static let container: ModelContainer = {
        // UI tests start from an empty in-memory store.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uitest")
        let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
        Seed.insertDefaultsIfNeeded(container.mainContext)
        Seed.insertDefaultRulesIfNeeded(container.mainContext)
        return container
    }()

    static var context: ModelContext { container.mainContext }
}

@MainActor
enum Seed {
    static let expenseCategories: [(String, String, String)] = [
        ("食物", "fork.knife", "#E9C98F"), ("玩樂", "gamecontroller", "#8E7CC3"),
        ("家庭", "house", "#D9706F"), ("個人", "person", "#4A90E2"), ("交通", "scooter", "#5BA4A4"),
        ("保險", "shield.checkered", "#7A8B5C"),
        ("其他", "ellipsis", "#6C5FA7"),
    ]
    static let incomeCategories: [(String, String, String)] = [
        ("薪水", "banknote", "#7CB86A"), ("獎金", "dollarsign.circle", "#B8955A"),
        ("還款", "arrow.uturn.left.circle", "#B8955A"), ("投資", "chart.line.uptrend.xyaxis", "#3BB4C1"),
        ("其他收入", "ellipsis", "#6C5FA7"),
    ]

    /// One-time starter rules matching how the budgets are used: 食物 on weekdays 07:00–16:00 → lunch,
    /// 16:00–23:59 → Dinner, weekends → holiday; 家庭 → Claim; 個人 → 生活 (living); 玩樂 → fun.
    /// Only for budgets and categories that exist.
    static func insertDefaultRulesIfNeeded(_ context: ModelContext) {
        let key = "budgetRulesSeeded"
        guard !UserDefaults.standard.bool(forKey: key),
              ((try? context.fetchCount(FetchDescriptor<BudgetRule>())) ?? 0) == 0 else { return }
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        guard !budgets.isEmpty else { return }
        let categories = ((try? context.fetch(FetchDescriptor<EntryCategory>())) ?? []).filter { $0.kind == .expense }
        func budget(_ names: String) -> Budget? {
            let options = names.split(separator: "|").map { $0.lowercased() }
            return budgets.first { options.contains($0.name.lowercased()) && !$0.isArchived }
        }
        func category(_ name: String) -> EntryCategory? { categories.first { $0.name == name } }
        let wanted: [(String, String, RuleDays, Int, Int)] = [
            ("食物", "lunch", .weekdays, 7 * 60, 16 * 60),
            ("食物", "dinner", .weekdays, 16 * 60, 23 * 60 + 59),
            ("食物", "holiday", .weekends, 0, 23 * 60 + 59),
            ("家庭", "claim", .everyday, 0, 23 * 60 + 59),
            ("個人", "生活|living", .everyday, 0, 23 * 60 + 59),
            ("玩樂", "fun", .everyday, 0, 23 * 60 + 59),
        ]
        for (i, w) in wanted.enumerated() {
            guard let c = category(w.0), let b = budget(w.1) else { continue }
            context.insert(BudgetRule(categoryID: c.id, budgetID: b.id, days: w.2, startMinute: w.3, endMinute: w.4, sortOrder: i))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    static func insertDefaultsIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<EntryCategory>())) ?? 0
        guard count == 0 else { return }
        for (i, c) in expenseCategories.enumerated() {
            context.insert(EntryCategory(name: c.0, symbol: c.1, colorHex: c.2, kind: .expense, sortOrder: i))
        }
        for (i, c) in incomeCategories.enumerated() {
            context.insert(EntryCategory(name: c.0, symbol: c.1, colorHex: c.2, kind: .income, sortOrder: i))
        }
        if ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) == 0 {
            context.insert(Account(name: "錢包", type: .cash))
        }
        try? context.save()
    }
}

/// Remembers the last used account so new entries default to it.
enum Preferences {
    private static let lastAccountKey = "lastAccountID"

    static var lastAccountID: UUID? {
        get { UserDefaults.standard.string(forKey: lastAccountKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: lastAccountKey) }
    }

    @MainActor
    static func defaultAccount(in context: ModelContext) -> Account? {
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let active = accounts.filter { !$0.isArchived }
        return active.first { $0.id == lastAccountID } ?? active.first
    }
}

@MainActor
enum EntryService {
    /// Inserts an entry and updates the usage stats that drive category suggestions.
    @discardableResult
    static func add(kind: EntryKind, amount: Double, date: Date = .now, name: String = "",
                    category: EntryCategory?, account: Account?, toAccount: Account? = nil,
                    budget: Budget? = nil, in context: ModelContext) -> Entry {
        let entry = Entry(kind: kind, amount: amount, date: date, name: name, category: category,
                          account: account, toAccount: toAccount, budget: budget)
        entry.currency = account?.currency ?? Currency.base
        entry.rate = Currency.rate(entry.currency)
        entry.setAmount(amount)
        context.insert(entry)
        noteUsage(category: category, account: account)
        try? context.save()
        return entry
    }

    static func noteUsage(category: EntryCategory?, account: Account?) {
        if let category {
            category.useCount += 1
            category.lastUsed = .now
        }
        if let account { Preferences.lastAccountID = account.id }
    }

    /// Moves `part` of an expense into a new entry, e.g. a friend's share of a bill you paid.
    /// The original keeps the rest; the new one gets `budget` (usually the claim budget).
    @discardableResult
    static func split(_ entry: Entry, part: Double, name: String, budget: Budget?, in context: ModelContext) -> Entry? {
        guard part > 0, part < entry.amount else { return nil }
        let share = part / entry.amount
        entry.amount -= part
        let piece = Entry(kind: entry.kind, amount: part, date: entry.date, name: name,
                          category: entry.category, account: entry.account, budget: budget)
        piece.note = entry.note
        piece.currency = entry.currency
        piece.rate = entry.rate
        if let foreign = entry.foreignAmount {
            let digits = Currency.info(entry.foreignCurrency ?? "").digits
            piece.foreignAmount = Currency.round(foreign * share, digits: digits)
            piece.foreignCurrency = entry.foreignCurrency
            entry.foreignAmount = foreign - (piece.foreignAmount ?? 0)
        }
        context.insert(piece)
        try? context.save()
        return piece
    }

    /// Someone paid back a claimed expense: it leaves its budget and the money is recorded as
    /// income (category 還款 when it exists) in `account`.
    @discardableResult
    static func settleClaim(_ entry: Entry, into account: Account, date: Date = .now, in context: ModelContext) -> Entry {
        entry.budget = nil
        let income = ((try? context.fetch(FetchDescriptor<EntryCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { $0.kind == .income }
        let category = income.first { $0.name == "還款" } ?? income.first
        return add(kind: .income, amount: entry.amount, date: date, name: entry.name, category: category, account: account, in: context)
    }

    /// The budget usually used at this time: past expenses within ±90 minutes of the time of day,
    /// on the same kind of day (weekday or weekend), and in the same category when there are enough
    /// of those. Recent ones count more. Falls back to the category's last budget without history.
    static func suggestedBudget(for category: EntryCategory?, at date: Date, recent: [Entry],
                                rules: [BudgetRule] = [], budgets: [Budget] = [],
                                calendar: Calendar = .current) -> Budget? {
        // Rules set in 設定 → 預算規則 come first.
        if let ruled = rules.budget(for: category, at: date, budgets: budgets) { return ruled }
        let minute = { (d: Date) -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let target = minute(date)
        let weekend = calendar.isDateInWeekend(date)
        let since = calendar.date(byAdding: .day, value: -120, to: date)!
        let nearby = recent.filter { e in
            guard e.kind == .expense, e.date >= since, e.date < date,
                  calendar.isDateInWeekend(e.date) == weekend, e.budget?.isArchived != true else { return false }
            let d = abs(minute(e.date) - target)
            return min(d, 1440 - d) <= 90
        }
        let sameCategory = nearby.filter { $0.category?.id == category?.id }
        let pool = category != nil && sameCategory.count >= 3 ? sameCategory : nearby
        guard !pool.isEmpty else { return suggestedBudget(for: category) }

        var scores: [UUID?: Double] = [:]
        var budgets: [UUID: Budget] = [:]
        for e in pool {
            let days = date.timeIntervalSince(e.date) / 86_400
            scores[e.budget?.id, default: 0] += exp(-days / 30)
            if let b = e.budget { budgets[b.id] = b }
        }
        let best = scores.max { $0.value < $1.value }?.key ?? nil
        return best.flatMap { budgets[$0] }
    }

    /// Same, loading the last few months of entries itself (for Siri and Shortcuts).
    static func suggestedBudget(for category: EntryCategory?, at date: Date, in context: ModelContext) -> Budget? {
        let since = Calendar.current.date(byAdding: .day, value: -120, to: date)!
        let recent = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= since }))) ?? []
        return suggestedBudget(for: category, at: date, recent: recent,
                               rules: (try? context.fetch(FetchDescriptor<BudgetRule>())) ?? [],
                               budgets: (try? context.fetch(FetchDescriptor<Budget>())) ?? [])
    }

    /// The budget most recently used with this category, if still active — mirrors MOZE's project memory.
    static func suggestedBudget(for category: EntryCategory?) -> Budget? {
        guard let entries = category?.entries, !entries.isEmpty else { return nil }
        let latest = entries.filter { $0.budget != nil }.max { $0.date < $1.date }
        guard let budget = latest?.budget, !budget.isArchived else { return nil }
        return budget
    }
}
