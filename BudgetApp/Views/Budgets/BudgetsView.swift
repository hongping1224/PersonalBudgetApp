import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Query(sort: \Budget.sortOrder) private var budgets: [Budget]
    @State private var creating = false
    @State private var transferring = false
    @State private var showArchived = false

    var body: some View {
        NavigationStack {
            ThemedList {
                let active = budgets.filter { !$0.isArchived }
                Section("進行中 (\(active.count))") {
                    if active.isEmpty {
                        Text("按右上角 ＋ 新增預算，例如每週午餐 750").foregroundStyle(.secondary)
                    }
                    ForEach(active) { budget in
                        NavigationLink { BudgetDetailView(budget: budget) } label: { BudgetRow(budget: budget) }
                    }
                }
                let archived = budgets.filter(\.isArchived)
                if !archived.isEmpty {
                    Section("已結束 (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { budget in
                            NavigationLink { BudgetDetailView(budget: budget) } label: { BudgetRow(budget: budget) }
                        }
                    }
                }
                Section {
                    NavigationLink { BudgetTransferHistoryView() } label: {
                        Label("轉移紀錄", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            .listStyle(.sidebar)
            .themedBackground()
            .navigationTitle("預算")
            .toolbar {
                Button { transferring = true } label: { Image(systemName: "arrow.left.arrow.right") }
                    .accessibilityLabel("轉移預算")
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新增預算")
            }
            .sheet(isPresented: $creating) { BudgetEditor(budget: nil) }
            .sheet(isPresented: $transferring) { BudgetTransferSheet(from: nil) }
        }
    }
}

struct BudgetRow: View {
    let budget: Budget
    /// The period to show on the detail page; nil is the current period in the budget list.
    var interval: DateInterval?

    var body: some View {
        let period = interval ?? budget.currentInterval
        let spent = budget.spent(in: period)
        let available = budget.available(in: period)
        let carry = budget.carryIn(to: period)
        let moved = budget.transferred(in: period)
        HStack(alignment: .top, spacing: 12) {
            SymbolBadge(symbol: budget.symbol, color: Color(hex: "#5C6F82"), size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(budget.name).font(.headline)
                    Spacer()
                    if let available {
                        let left = available - spent
                        Text(Money.string(left)).font(.headline.monospacedDigit())
                            .foregroundStyle(left >= 0 ? Color.income : Color.expense)
                    } else {
                        Text(Money.string(spent)).font(.headline.monospacedDigit())
                            .foregroundStyle(spent > 0 ? Color.expense : Color.income)
                    }
                }
                if let available {
                    BudgetBar(fraction: available > 0 ? spent / available : 1, timeFraction: period.elapsedFraction)
                }
                HStack {
                    if interval == nil, let today = todayText(in: period) {
                        today
                    } else {
                        Text(period.shortLabel)
                    }
                    Spacer()
                    if let available {
                        Text(Money.plain(spent)).foregroundStyle(spent > available ? Color.expense : .secondary)
                        + Text(" / \(Money.plain(available))")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if interval != nil, let today = todayText(in: period) {
                    today.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                // The list stays short; how the amount adds up is on the detail page.
                if interval != nil, let amount = budget.amount, carry != 0 || moved != 0 {
                    let parts = ["本期 \(Money.plain(amount))"]
                        + (carry != 0 ? ["上期結轉 \(Money.string(carry, signed: true))"] : [])
                        + (moved != 0 ? ["轉移 \(Money.string(moved, signed: true))"] : [])
                    Text(parts.joined(separator: "，"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(carry + moved > 0 ? Color.income : Color.expense)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// "今日 35 / 140" when the budget shows its daily amount and the period is the current one.
    private func todayText(in period: DateInterval) -> Text? {
        guard budget.showsDaily, let daily = budget.dailyAvailable(in: period) else { return nil }
        let used = budget.spentToday(in: period)
        return Text("今日 ")
            + Text(Money.plain(used)).foregroundColor(used > daily ? .expense : .secondary)
            + Text(" / \(Money.plain(daily))")
    }
}

/// Spending bar with an hourglass marker for how much of the period has passed.
struct BudgetBar: View {
    var fraction: Double
    var timeFraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(fraction > timeFraction ? Color.expense : Color.income)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#E9C98F"))
                    .offset(x: geo.size.width * timeFraction - 5.5, y: 0)
            }
        }
        .frame(height: 5)
        .padding(.vertical, 5)
    }
}

struct BudgetDetailView: View {
    @Bindable var budget: Budget
    @State private var offset = 0
    @State private var editingBudget = false
    @State private var transferring = false
    @State private var deletingTransfer: UUID?
    @State private var editingEntry: Entry?
    @State private var settlingEntry: Entry?

    var body: some View {
        let interval = budget.interval(offset: offset)
        let entries = budget.entries(in: interval).sorted { $0.date > $1.date }
        let transfers = (budget.adjustments ?? [])
            .filter { $0.date >= interval.start && $0.date < interval.end }
            .sorted { $0.date > $1.date }
        ThemedList {
            Section {
                BudgetRow(budget: budget, interval: interval)
                if budget.period != .custom {
                    HStack {
                        Button { offset -= 1 } label: { Label("上一期", systemImage: "chevron.left") }
                        Spacer()
                        if offset != 0 { Button("本期") { offset = 0 } }
                        Spacer()
                        Button { offset += 1 } label: { Label("下一期", systemImage: "chevron.right").labelStyle(TrailingIconLabel()) }
                            .disabled(offset >= 0)
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
            } footer: {
                Text(budget.periodDescription)
            }

            if !transfers.isEmpty {
                Section {
                    ForEach(transfers) { t in
                        BudgetTransferRow(
                            title: t.amount > 0 ? "從「\(t.counterpartName)」轉入" : "轉給「\(t.counterpartName)」",
                            adjustment: t, signed: true
                        ) { deletingTransfer = t.transferID }
                    }
                } header: {
                    Text("預算轉移")
                } footer: {
                    Text("刪除轉移會同時還原兩邊預算的金額。")
                }
            }

            if budget.isClaim {
                // Everything still owed, whatever period it was paid in.
                let owed = (budget.entries ?? []).sorted { $0.date > $1.date }
                Section {
                    if owed.isEmpty { Text("沒有待收的款項").foregroundStyle(.secondary) }
                    ForEach(owed) { entry in
                        HStack {
                            Button { editingEntry = entry } label: { EntryRow(entry: entry, showDate: true) }
                                .tint(.primary)
                            Button("已還款") { settlingEntry = entry }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("待收款 (\(owed.count))，共 \(Money.string(owed.reduce(0) { $0 + $1.baseAmount }))")
                } footer: {
                    Text("對方還錢後按「已還款」，這筆會移到無預算，並記一筆收入。")
                }
            } else {
                Section("紀錄 (\(entries.count))") {
                    if entries.isEmpty { Text("這期沒有紀錄").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        Button { editingEntry = entry } label: { EntryRow(entry: entry, showDate: true) }
                            .tint(.primary)
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle(budget.name)
        .toolbar {
            if budget.amount != nil {
                Button("轉移") { transferring = true }
            }
            Button("編輯") { editingBudget = true }
        }
        .sheet(isPresented: $editingBudget) { BudgetEditor(budget: budget) }
        .sheet(isPresented: $transferring) { BudgetTransferSheet(from: budget) }
        .sheet(item: $editingEntry) { EntryEditor(entry: $0) }
        .background { Color.clear.sheet(item: $settlingEntry) { ClaimSettleSheet(entry: $0) } }
        .deleteTransferDialog(id: $deletingTransfer)
    }
}

/// One transfer line with a visible delete button (swipe left also works).
struct BudgetTransferRow: View {
    let title: String
    let adjustment: BudgetAdjustment
    /// Show +/− from this budget's point of view; otherwise the plain amount moved.
    var signed = false
    let onDelete: () -> Void

    var body: some View {
        let amount = adjustment.amount
        HStack {
            Image(systemName: signed ? (amount > 0 ? "arrow.down.left" : "arrow.up.right") : "arrow.left.arrow.right")
                .foregroundStyle(signed ? (amount > 0 ? Color.income : Color.expense) : Color.secondary)
            VStack(alignment: .leading) {
                Text(title)
                Text([adjustment.date.formatted(.dateTime.year().month().day()), adjustment.note]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(signed ? Money.string(amount, signed: true) : Money.string(abs(amount)))
                .monospacedDigit()
                .foregroundStyle(signed ? (amount > 0 ? Color.income : Color.expense) : Color.primary)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(Color.expense)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("刪除轉移")
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) { Label("刪除", systemImage: "trash") }
        }
    }
}

extension View {
    /// Confirms and deletes both sides of the transfer whose ID is bound.
    func deleteTransferDialog(id: Binding<UUID?>) -> some View {
        modifier(DeleteTransferDialog(transferID: id))
    }
}

private struct DeleteTransferDialog: ViewModifier {
    @Binding var transferID: UUID?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog("刪除這筆轉移？兩邊預算的金額會還原。",
                                   isPresented: Binding(get: { transferID != nil }, set: { if !$0 { transferID = nil } }),
                                   titleVisibility: .visible, presenting: transferID) { id in
            Button("刪除", role: .destructive) {
                let both = (try? context.fetch(FetchDescriptor<BudgetAdjustment>(predicate: #Predicate { $0.transferID == id }))) ?? []
                both.forEach(context.delete)
                try? context.save()
            }
        }
    }
}

/// Every budget transfer, newest first, each deletable.
struct BudgetTransferHistoryView: View {
    // The giving side (negative amount) stands for the whole transfer.
    @Query(filter: #Predicate<BudgetAdjustment> { $0.amount < 0 }, sort: \BudgetAdjustment.date, order: .reverse)
    private var outgoing: [BudgetAdjustment]
    @State private var deleting: UUID?

    var body: some View {
        ThemedList {
            if outgoing.isEmpty {
                ContentUnavailableView("還沒有預算轉移", systemImage: "arrow.left.arrow.right")
            }
            ForEach(outgoing) { t in
                BudgetTransferRow(title: "\(t.budget?.name ?? "（已刪除）") → \(t.counterpartName)", adjustment: t) {
                    deleting = t.transferID
                }
            }
        }
        .themedBackground()
        .navigationTitle("轉移紀錄")
        .deleteTransferDialog(id: $deleting)
    }
}

/// Moves part of one budget's current period to another budget's current period.
struct BudgetTransferSheet: View {
    let from: Budget?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Budget> { !$0.isArchived && $0.amount != nil }, sort: \Budget.sortOrder)
    private var budgets: [Budget]

    @State private var source: Budget?
    @State private var target: Budget?
    @State private var amountText = ""
    @State private var note = ""

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: "")) }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    budgetPicker("從", selection: $source)
                    budgetPicker("到", selection: $target)
                } footer: {
                    Text("金額會從「從」的本期可用預算扣掉，加到「到」的本期可用預算。")
                }
                Section {
                    TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    TextField("備註（選填）", text: $note)
                    if let source, let left = source.remaining {
                        Button("轉出「\(source.name)」全部剩餘 \(Money.string(max(left, 0)))") {
                            amountText = Money.plain(max(left, 0))
                        }
                        .disabled(left <= 0)
                    }
                }
            }
            .themedBackground()
            .navigationTitle("轉移預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("轉移", action: save)
                        .disabled(source == nil || target == nil || source?.id == target?.id || !((amount ?? 0) > 0))
                }
            }
            .onAppear {
                source = source ?? from ?? budgets.first
                target = target ?? budgets.first { $0.id != source?.id }
            }
        }
    }

    private func budgetPicker(_ title: String, selection: Binding<Budget?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(budgets) { b in
                let left = b.remaining.map { "（剩 \(Money.string($0))）" } ?? ""
                Text(b.name + left).tag(Optional(b))
            }
        }
    }

    private func save() {
        guard let source, let target, let amount, amount > 0 else { return }
        let id = UUID()
        let now = Date.now
        context.insert(BudgetAdjustment(transferID: id, amount: -amount, date: now, budget: source,
                                        counterpartName: target.name, note: note))
        context.insert(BudgetAdjustment(transferID: id, amount: amount, date: now, budget: target,
                                        counterpartName: source.name, note: note))
        try? context.save()
        dismiss()
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

struct BudgetEditor: View {
    let budget: Budget?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allBudgets: [Budget]

    @State private var name = ""
    @State private var symbol = "target"
    @State private var hasAmount = true
    @State private var amountText = ""
    @State private var period: BudgetPeriod = .monthly
    @State private var weekday = 2
    @State private var monthDay = 1
    @State private var customStart = Date.now
    @State private var customEnd = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
    @State private var isArchived = false
    @State private var carriesOver = false
    @State private var carryOverspend = true
    @State private var carryOverStart = Date.now
    @State private var showsDaily = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    TextField("名稱，例如 午餐", text: $name)
                    SymbolPicker(symbol: $symbol, color: Color(hex: "#5C6F82"))
                }
                Section {
                    Toggle("設定預算金額", isOn: $hasAmount)
                    if hasAmount {
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("不設金額時只統計花費，跟 MOZE 的專案一樣。")
                }
                Section("週期") {
                    Picker("週期", selection: $period) {
                        ForEach(BudgetPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch period {
                    case .weekly:
                        Picker("每週開始於", selection: $weekday) {
                            ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                        }
                    case .monthly:
                        Stepper("每月 \(monthDay) 號開始", value: $monthDay, in: 1...31)
                    case .custom:
                        DatePicker("開始", selection: $customStart, displayedComponents: .date)
                        DatePicker("結束", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    }
                }
                if hasAmount {
                    Section {
                        Toggle("顯示每日可用", isOn: $showsDaily)
                    } footer: {
                        Text("每天可用 = 到昨天為止剩下的預算 ÷ 剩下的天數（含今天），顯示成「今日 已用 / 可用」。")
                    }
                }
                if hasAmount && period != .custom {
                    Section {
                        Toggle("延續上期剩餘金額", isOn: $carriesOver)
                        if carriesOver {
                            Toggle("超支也從下期扣除", isOn: $carryOverspend)
                            DatePicker("從這天開始累計", selection: $carryOverStart, displayedComponents: .date)
                        }
                    } footer: {
                        Text(carriesOver
                             ? "每期沒花完的錢會加到下一期\(carryOverspend ? "，超支的部分會從下一期扣掉" : "；超支不影響下一期")。從包含這天的那一期開始累計。"
                             : "開啟後，沒花完的預算會留到下一期。")
                    }
                }
                Section {
                    if budget != nil { Toggle("已結束（封存）", isOn: $isArchived) }
                }
                if budget != nil {
                    Section {
                        Button("刪除預算", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("刪除後，原本歸在這個預算的紀錄會保留，只是不再屬於任何預算。")
                    }
                }
            }
            .themedBackground()
            .navigationTitle(budget == nil ? "新增預算" : "編輯預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("刪除「\(name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let budget { context.delete(budget); try? context.save() }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let budget else { return }
        name = budget.name
        symbol = budget.symbol
        hasAmount = budget.amount != nil
        amountText = budget.amount.map(Money.plain) ?? ""
        period = budget.period
        if period == .weekly { weekday = budget.anchorDay } else { monthDay = budget.anchorDay }
        customStart = budget.customStart
        customEnd = budget.customEnd
        isArchived = budget.isArchived
        carriesOver = budget.carriesOver
        carryOverspend = budget.carryOverspend
        showsDaily = budget.showsDaily
        // Default to the previous period so turning it on has an effect right away.
        carryOverStart = budget.carryOverStart ?? budget.interval(offset: -1).start
    }

    private func save() {
        let target = budget ?? {
            let b = Budget(name: "", amount: nil, period: period)
            b.sortOrder = (allBudgets.map(\.sortOrder).max() ?? 0) + 1
            context.insert(b)
            return b
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.symbol = symbol
        target.amount = hasAmount ? Double(amountText.replacingOccurrences(of: ",", with: "")) : nil
        target.period = period
        target.anchorDay = period == .weekly ? weekday : monthDay
        target.customStart = customStart
        target.customEnd = customEnd
        target.isArchived = isArchived
        target.carriesOver = carriesOver && target.amount != nil && period != .custom
        target.carryOverspend = carryOverspend
        target.carryOverStart = carriesOver ? carryOverStart : nil
        target.showsDaily = showsDaily && target.amount != nil
        try? context.save()
        dismiss()
    }
}

struct SymbolPicker: View {
    @Binding var symbol: String
    var color: Color

    var body: some View {
        DisclosureGroup {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(Palette.symbols, id: \.self) { s in
                    SymbolBadge(symbol: s, color: s == symbol ? color : Color(.systemGray3), size: 38)
                        .onTapGesture { symbol = s }
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Text("圖示")
                Spacer()
                SymbolBadge(symbol: symbol, color: color, size: 30)
            }
        }
    }
}
