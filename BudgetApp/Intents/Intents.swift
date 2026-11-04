import AppIntents
import SwiftData

// MARK: Entities

struct CategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "分類"
    static var defaultQuery = CategoryQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ category: EntryCategory) {
        id = category.id
        name = category.name
    }
}

struct CategoryQuery: EntityStringQuery {
    @MainActor
    private func expenseCategories() throws -> [EntryCategory] {
        try DataStore.context.fetch(FetchDescriptor<EntryCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
            .filter { $0.kind == .expense }
            .sorted { $0.useCount > $1.useCount }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        try DataStore.context.fetch(FetchDescriptor<EntryCategory>())
            .filter { identifiers.contains($0.id) }
            .map(CategoryEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CategoryEntity] {
        try expenseCategories().filter { string.localizedCaseInsensitiveContains($0.name) || $0.name.localizedCaseInsensitiveContains(string) }
            .map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        try expenseCategories().map(CategoryEntity.init)
    }
}

struct AccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "帳戶"
    static var defaultQuery = AccountQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ account: Account) {
        id = account.id
        name = account.name
    }
}

struct AccountQuery: EntityStringQuery {
    @MainActor
    private func activeAccounts() throws -> [Account] {
        try DataStore.context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
            .filter { !$0.isArchived }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        try activeAccounts().filter { identifiers.contains($0.id) }.map(AccountEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [AccountEntity] {
        try activeAccounts().filter { $0.name.localizedCaseInsensitiveContains(string) }.map(AccountEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        try activeAccounts().map(AccountEntity.init)
    }
}

struct BudgetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "預算"
    static var defaultQuery = BudgetQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ budget: Budget) {
        id = budget.id
        name = budget.name
    }
}

struct BudgetQuery: EntityStringQuery {
    @MainActor
    private func activeBudgets() throws -> [Budget] {
        try DataStore.context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)]))
            .filter { !$0.isArchived }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BudgetEntity] {
        try DataStore.context.fetch(FetchDescriptor<Budget>())
            .filter { identifiers.contains($0.id) }
            .map(BudgetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [BudgetEntity] {
        try activeBudgets().filter { $0.name.localizedCaseInsensitiveContains(string) }.map(BudgetEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [BudgetEntity] {
        try activeBudgets().map(BudgetEntity.init)
    }
}

@MainActor
private func budgetModel(for entity: BudgetEntity?) throws -> Budget? {
    guard let id = entity?.id else { return nil }
    return try DataStore.context.fetch(FetchDescriptor<Budget>()).first { $0.id == id }
}

// MARK: Intents

/// Voice-friendly: one sentence such as "午餐 120 用信用卡".
struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "快速記帳"
    static var description = IntentDescription("說一句話記一筆，例如「午餐 120」或「計程車 250 用信用卡」。")

    @Parameter(title: "內容", requestValueDialog: "要記什麼？例如「午餐 120」")
    var text: String

    @Parameter(title: "預算", description: "不選的話，會用說出的預算名稱或這個分類上次用的預算。")
    var budget: BudgetEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("快速記帳 \(\.$text)") {
            \.$budget
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = DataStore.context
        let categories = try context.fetch(FetchDescriptor<EntryCategory>())
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { !$0.isArchived }
        let budgets = try context.fetch(FetchDescriptor<Budget>()).filter { !$0.isArchived }
        let parsed = QuickEntryParser(categoryNames: categories.map(\.name), accountNames: accounts.map(\.name),
                                      budgetNames: budgets.map(\.name)).parse(text)

        guard let amount = parsed.amount, amount > 0 else {
            throw $text.needsValueError("沒聽到金額，請再說一次，例如「午餐 120」")
        }

        let category = categories.first { $0.name == parsed.categoryName }
            ?? categories.first { $0.kind == .expense && $0.name == "其他" }
            ?? categories.first { $0.kind == .expense }
        let kind: EntryKind = category?.kind == .income ? .income : .expense
        let account = accounts.first { $0.name == parsed.accountName } ?? Preferences.defaultAccount(in: context)
        let chosenBudget = try budgetModel(for: budget)
            ?? budgets.first { $0.name == parsed.budgetName }
            ?? EntryService.suggestedBudget(for: category, at: .now, in: context)

        EntryService.add(kind: kind, amount: amount, name: parsed.name, category: category, account: account,
                         budget: chosenBudget, in: context)

        let label = parsed.name.isEmpty ? (category?.name ?? "") : parsed.name
        let budgetNote = chosenBudget.map { "，預算 \($0.name)" } ?? ""
        return .result(dialog: "已記下\(kind == .income ? "收入" : "")\(label) \(Money.string(amount))，\(account?.name ?? "")\(budgetNote)")
    }
}

/// Structured version for building custom shortcuts (e.g. one shortcut per category).
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "記一筆支出"
    static var description = IntentDescription("指定金額和分類，新增一筆支出。")

    @Parameter(title: "金額", requestValueDialog: "多少錢？")
    var amount: Double

    @Parameter(title: "分類", requestValueDialog: "什麼分類？")
    var category: CategoryEntity

    @Parameter(title: "名稱")
    var name: String?

    @Parameter(title: "帳戶")
    var account: AccountEntity?

    @Parameter(title: "預算", description: "不選的話，用這個分類上次用的預算。")
    var budget: BudgetEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("在 \(\.$category) 記 \(\.$amount)") {
            \.$name
            \.$account
            \.$budget
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = DataStore.context
        let categoryID = category.id
        let model = try context.fetch(FetchDescriptor<EntryCategory>()).first { $0.id == categoryID }
        let accountID = account?.id
        let accountModel = try context.fetch(FetchDescriptor<Account>()).first { $0.id == accountID }
            ?? Preferences.defaultAccount(in: context)

        let chosenBudget = try budgetModel(for: budget) ?? EntryService.suggestedBudget(for: model, at: .now, in: context)
        EntryService.add(kind: .expense, amount: amount, name: name ?? "", category: model, account: accountModel,
                         budget: chosenBudget, in: context)
        return .result(dialog: "已記下\(category.name) \(Money.string(amount))\(chosenBudget.map { "，預算 \($0.name)" } ?? "")")
    }
}

/// Opens the app straight into the keypad — good for the Action Button.
struct OpenAddEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "開啟記帳畫面"
    static var description = IntentDescription("打開記帳本並直接進入記一筆畫面。")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.preferredDate = nil
        AppRouter.shared.showAddEntry = true
        return .result()
    }
}

/// For a Shortcuts widget: 取得載具號碼 → 拷貝到剪貼簿 copies without opening the app
/// (iOS doesn't let the app's own widget write to the clipboard).
struct GetCarrierIntent: AppIntent {
    static var title: LocalizedStringResource = "取得載具號碼"
    static var description = IntentDescription("回傳在記帳本設定的手機條碼載具號碼，可以接「拷貝到剪貼簿」。")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let number = Carrier.number else {
            throw NoCarrier()
        }
        return .result(value: number)
    }

    struct NoCarrier: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource { "還沒設定載具，請到記帳本的 設定 → 載具 輸入號碼。" }
    }
}

struct BudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddIntent(),
            phrases: [
                "用\(.applicationName)記帳",
                "\(.applicationName)記一筆",
                "在\(.applicationName)記帳",
            ],
            shortTitle: "快速記帳",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: OpenAddEntryIntent(),
            phrases: ["打開\(.applicationName)記一筆", "\(.applicationName)新增紀錄"],
            shortTitle: "開啟記帳畫面",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: GetCarrierIntent(),
            phrases: ["\(.applicationName)載具號碼", "取得\(.applicationName)載具"],
            shortTitle: "取得載具號碼",
            systemImageName: "barcode"
        )
    }
}
