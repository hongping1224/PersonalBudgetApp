import SwiftUI
import SwiftData

/// MOZE-style entry screen: category grid, calculator keypad and frequent amounts.
struct EntryEditor: View {
    /// nil creates a new entry.
    let entry: Entry?
    var initialDate: Date?
    var initialKind: EntryKind = .expense
    /// Category ID or name to preselect for a new entry (from the widget).
    var initialCategory: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \EntryCategory.sortOrder) private var allCategories: [EntryCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]
    @Query(filter: #Predicate<Budget> { !$0.isArchived }, sort: \Budget.sortOrder) private var budgets: [Budget]
    @Query(sort: \BudgetRule.sortOrder) private var rules: [BudgetRule]

    @State private var kind: EntryKind = .expense
    @State private var calculator = Calculator()
    @State private var category: EntryCategory?
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var budget: Budget?
    @State private var budgetTouched = false
    /// Transfers between currencies: what arrived, typed by hand.
    @State private var toAmountText = ""
    @State private var date = Date.now
    @State private var name = ""
    @State private var loaded = false
    @State private var showDeleteConfirm = false
    @State private var showDatePicker = false
    @State private var showSplit = false
    @State private var showAccountList = false
    @State private var showBudgetList = false
    @State private var knownNames: [NameSuggestion] = []
    @State private var recentEntries: [Entry] = []
    @FocusState private var nameFocused: Bool

    private var categories: [EntryCategory] {
        allCategories
            .filter { $0.kind == kind }
            .sorted { ($0.useCount, -$0.sortOrder) > ($1.useCount, -$1.sortOrder) }
    }

    /// Amounts are always in the account's currency.
    private var currency: String { account?.currency ?? Currency.base }

    private var crossCurrency: Bool {
        kind == .transfer && toAccount != nil && toAccount?.currency != account?.currency
    }

    private var toAmount: Double? {
        Double(toAmountText.replacingOccurrences(of: ",", with: "")).flatMap { $0 > 0 ? $0 : nil }
    }

    private var canSave: Bool {
        guard let v = calculator.value, v > 0, account != nil else { return false }
        if kind == .transfer {
            return toAccount != nil && toAccount?.id != account?.id && (!crossCurrency || toAmount != nil)
        }
        return category != nil
    }

    var body: some View {
        // The stack only hosts the keyboard toolbar; its bar stays hidden.
        NavigationStack {
            editor
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    // With the keyboard up the header can be pushed off screen, so offer a way out here too.
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("取消紀錄", role: .cancel) { dismiss() }
                            .tint(Color.expense)
                        Spacer()
                        Button("完成") { nameFocused = false }.fontWeight(.semibold)
                    }
                }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header
            Picker("類型", selection: $kind) {
                ForEach(EntryKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if kind == .transfer {
                transferAccounts
            } else {
                categoryGrid
            }

            fields
            Keypad(onKey: { calculator.press($0) }, onDone: save)
                .frame(height: 290)
        }
        .background(Color.themeBackground)
        .onAppear(perform: load)
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
        .background {
            Color.clear.sheet(isPresented: $showSplit) {
                if let entry { SplitEntrySheet(entry: entry) { dismiss() } }
            }
        }
        .onChange(of: date) { _, _ in
            // A different time of day or weekday may mean a different budget.
            if entry == nil, !budgetTouched { budget = suggestedBudget(for: category) }
        }
        .onChange(of: kind) { _, newKind in
            if category?.kind != newKind { category = nil }
        }
        .confirmationDialog("刪除這筆紀錄？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                if let entry { context.delete(entry); try? context.save() }
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            Spacer()
            Text(entry == nil ? "記一筆" : "編輯").font(.headline)
            Spacer()
            if let entry, entry.kind == .expense, kind == .expense {
                Button {
                    // Keep edits made so far; the split works on the saved entry.
                    if canSave { applyEdits(to: entry) }
                    showSplit = true
                } label: {
                    Image(systemName: "square.split.2x1").frame(width: 44, height: 44)
                }
                .accessibilityLabel("拆分")
            }
            if entry != nil {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }
            }
            Button(action: save) {
                Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .disabled(!canSave)
            .accessibilityLabel("儲存")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var categoryGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 10) {
                ForEach(categories) { c in
                    Button {
                        category = c
                        if !budgetTouched { budget = suggestedBudget(for: c) }
                        // Next step is the name: open the keyboard on it.
                        if name.isEmpty { nameFocused = true }
                    } label: {
                        VStack(spacing: 4) {
                            SymbolBadge(symbol: c.symbol, color: Color(hex: c.colorHex), size: 48)
                                .overlay(Circle().stroke(Color.primary, lineWidth: category?.id == c.id ? 3 : 0).padding(-4))
                            Text(c.name)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(category?.id == c.id ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("category-\(c.name)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var transferAccounts: some View {
        VStack(spacing: 12) {
            accountMenu(title: "從", selection: $account)
            Button {
                (account, toAccount) = (toAccount, account)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.themeFill, in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("交換轉出轉入")
            accountMenu(title: "到", selection: $toAccount)
            if crossCurrency, let to = toAccount {
                // Different currencies: type what actually arrived; the app doesn't convert.
                HStack {
                    Text("轉入金額").foregroundStyle(.secondary)
                    Spacer()
                    TextField("0", text: $toAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .accessibilityLabel("轉入金額")
                    Text(to.currency).foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.themeFill, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    /// Accounts grouped under their type (現金, 銀行, 信用卡 …), in the 帳戶 tab's order.
    @ViewBuilder
    private func accountItems(_ select: @escaping (Account) -> Void) -> some View {
        ForEach(AccountType.allCases) { type in
            let group = accounts.filter { $0.type == type }
            if !group.isEmpty {
                Section(type.title) {
                    ForEach(group) { a in
                        Button { select(a) } label: { Label(a.name, systemImage: a.type.symbol) }
                    }
                }
            }
        }
    }

    // MARK: Pop-down lists

    /// Compact list under the account chip, grouped by type; first items sit right under the finger.
    private var accountList: some View {
        DropList {
            ForEach(AccountType.allCases) { type in
                let group = accounts.filter { $0.type == type }
                if !group.isEmpty {
                    DropItem.header(type.title)
                    ForEach(group) { a in
                        DropItem.row(a.name, symbol: a.type.symbol, selected: a.id == account?.id) {
                            account = a
                            showAccountList = false
                        }
                    }
                }
            }
        }
    }

    private var budgetList: some View {
        DropList {
            DropItem.row("不歸入預算", symbol: "minus.circle", selected: budget == nil) {
                budget = nil; budgetTouched = true; showBudgetList = false
            }
            ForEach(budgets) { b in
                DropItem.row(b.name, symbol: b.symbol, selected: b.id == budget?.id) {
                    budget = b; budgetTouched = true; showBudgetList = false
                }
            }
        }
    }

    private func accountMenu(title: String, selection: Binding<Account?>) -> some View {
        Menu {
            accountItems { selection.wrappedValue = $0 }
        } label: {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(selection.wrappedValue?.name ?? "選擇帳戶")
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .padding()
            .background(Color.themeFill, in: RoundedRectangle(cornerRadius: 12))
        }
        .menuOrder(.fixed)
        .tint(.primary)
    }

    private var fields: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                currencyMenu
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    if calculator.hasOperator {
                        Text(calculator.expression).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(displayAmount)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(kind == .expense ? Color.expense : kind == .income ? Color.income : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                }
            }

            TextField("名稱", text: $name)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(10)
                .background(Color.themeFill, in: RoundedRectangle(cornerRadius: 10))

            // Shown until a name is filled in, so picking a category is enough to see its names.
            if nameFocused || name.isEmpty {
                nameSuggestions
            }

            HStack(spacing: 8) {
                if kind != .transfer {
                    Button { showAccountList = true } label: {
                        chip(account?.name ?? "帳戶", systemImage: account?.type.symbol ?? "wallet.pass")
                    }
                    .popover(isPresented: $showAccountList, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                        accountList
                    }
                    Button { showBudgetList = true } label: {
                        chip(budget?.name ?? "無預算", systemImage: "target")
                    }
                    .popover(isPresented: $showBudgetList, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                        budgetList
                    }
                }
                Button { showDatePicker = true } label: {
                    chip(dateLabel, systemImage: "calendar")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var nameSuggestions: some View {
        // Typing → similar names; category chosen → its recent names; neither → what was
        // usually recorded around this time on previous days.
        let suggestions = !name.isEmpty || category != nil
            ? NameSuggester.suggest(name, in: knownNames, kind: kind, categoryID: category?.id)
            : NameSuggester.aroundTime(date, entries: recentEntries, items: knownNames, kind: kind)
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { s in
                        Button { apply(s) } label: {
                            HStack(spacing: 4) {
                                if let c = allCategories.first(where: { $0.id == s.categoryID }) {
                                    Image(systemName: c.symbol).foregroundStyle(Color(hex: c.colorHex))
                                }
                                Text(s.name)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("name-suggestion")
                    }
                }
            }
        }
    }

    /// Fills the name and copies the category, account and budget from its latest entry.
    private func apply(_ s: NameSuggestion) {
        name = s.name
        if let c = allCategories.first(where: { $0.id == s.categoryID }), c.kind == kind {
            category = c
        }
        if let a = accounts.first(where: { $0.id == s.accountID }) {
            account = a
        }
        budget = budgets.first { $0.id == s.budgetID }
        budgetTouched = true
        nameFocused = false
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.body.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.themeFill, in: RoundedRectangle(cornerRadius: 12))
            .tint(.primary)
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }

    private var datePickerSheet: some View {
        NavigationStack {
            ThemedForm {
                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                DatePicker("時間", selection: $date, displayedComponents: .hourAndMinute)
            }
            .themedBackground()
            .navigationTitle("日期")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button { showDatePicker = false } label: {
                        Text("完成").font(.headline).padding(.horizontal, 28).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .presentationDetents([.large])
    }

    private func suggestedBudget(for category: EntryCategory?) -> Budget? {
        kind == .expense
            ? EntryService.suggestedBudget(for: category, at: date, recent: recentEntries, rules: rules, budgets: budgets)
            : EntryService.suggestedBudget(for: category)
    }

    /// The account's currency (amounts are always in it).
    private var currencyMenu: some View {
        Text(currency)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.themeFill, in: Capsule())
            .accessibilityLabel("幣別 \(currency)")
    }

    private var displayAmount: String {
        guard let v = calculator.value else { return "0" }
        return Money.string(v, currency: currency).replacingOccurrences(of: Currency.info(currency).symbol, with: "")
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        var recent = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        recent.fetchLimit = 3000
        recentEntries = (try? context.fetch(recent)) ?? []
        knownNames = NameSuggester.build(from: recentEntries)
        if let entry {
            kind = entry.kind
            calculator.expression = Money.plain(entry.amount)
            toAmountText = entry.toAmount.map(Money.plain) ?? ""
            category = entry.category
            account = entry.account
            toAccount = entry.toAccount
            budget = entry.budget
            budgetTouched = true
            date = entry.date
            name = entry.name
        } else {
            kind = initialKind
            if let initialCategory, let c = allCategories.first(where: {
                $0.kind == initialKind && ($0.id.uuidString == initialCategory || $0.name == initialCategory)
            }) {
                category = c
                budget = suggestedBudget(for: c)
                // From the widget the category is already chosen, so start on the name.
                Task { try? await Task.sleep(for: .milliseconds(500)); nameFocused = true }
            }
            account = Preferences.defaultAccount(in: context)
            toAccount = accounts.first { $0.id != account?.id }
            if let initialDate, !Calendar.current.isDateInToday(initialDate) {
                // Keep the current time so entries on the same day stay in input order.
                let time = Calendar.current.dateComponents([.hour, .minute], from: .now)
                date = Calendar.current.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: initialDate) ?? initialDate
            }
            if category == nil { budget = suggestedBudget(for: nil) }
        }
    }

    private func save() {
        guard canSave, let amount = calculator.value else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let entry {
            applyEdits(to: entry)
        } else {
            let new = EntryService.add(kind: kind, amount: amount, date: date, name: trimmed,
                                       category: kind == .transfer ? nil : category, account: account,
                                       toAccount: kind == .transfer ? toAccount : nil,
                                       budget: kind == .transfer ? nil : budget, in: context)
            new.setAmount(amount, toAmount: crossCurrency ? toAmount : nil)
            try? context.save()
        }
        dismiss()
    }

    private func applyEdits(to entry: Entry) {
        guard let amount = calculator.value else { return }
        entry.kind = kind
        entry.date = date
        entry.name = name.trimmingCharacters(in: .whitespaces)
        entry.account = account
        entry.category = kind == .transfer ? nil : category
        entry.toAccount = kind == .transfer ? toAccount : nil
        entry.setAmount(amount, toAmount: crossCurrency ? toAmount : nil)
        entry.budget = kind == .transfer ? nil : budget
        try? context.save()
    }
}

/// Small scrolling list shown as a popover below a chip (instead of a full-size system menu).
private struct DropList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.vertical, 6)
        }
        .frame(width: 210)
        .frame(maxHeight: 300)
        .presentationBackground(Color.themeSurface)
        .presentationCompactAdaptation(.popover)
    }
}

private enum DropItem {
    static func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }

    static func row(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            }
            .font(.subheadline)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .tint(.primary)
    }
}
