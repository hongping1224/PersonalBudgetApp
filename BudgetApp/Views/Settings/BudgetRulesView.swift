import SwiftUI
import SwiftData

/// 設定 → 預算規則: which budget a new entry gets by category, day and time.
struct BudgetRuleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetRule.sortOrder) private var rules: [BudgetRule]
    @Query private var categories: [EntryCategory]
    @Query private var budgets: [Budget]
    @State private var editing: BudgetRule?
    @State private var creating = false

    var body: some View {
        ThemedList {
            Section {
                if rules.isEmpty { Text("還沒有規則").foregroundStyle(.secondary) }
                ForEach(rules) { rule in
                    Button { editing = rule } label: { row(rule) }.tint(.primary)
                }
                .onMove { from, to in
                    var items = rules
                    items.move(fromOffsets: from, toOffset: to)
                    for (i, r) in items.enumerated() { r.sortOrder = i }
                    try? context.save()
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(rules[i]) }
                    try? context.save()
                }
            } footer: {
                Text("由上往下比對，用第一條符合的規則。手動選的預算不會被改掉。")
            }
        }
        .themedBackground()
        .navigationTitle("預算規則")
        .toolbar {
            EditButton()
            Button { creating = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("新增規則")
        }
        .sheet(item: $editing) { BudgetRuleEditor(rule: $0) }
        .sheet(isPresented: $creating) { BudgetRuleEditor(rule: nil) }
    }

    private func row(_ rule: BudgetRule) -> some View {
        let category = categories.first { $0.id == rule.categoryID }
        let budget = budgets.first { $0.id == rule.budgetID }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.categoryID == nil ? "任何分類" : category?.name ?? "（已刪除的分類）")
                Text(rule.days.title + (rule.isAllDay ? " 整天" : " \(BudgetRule.timeText(rule.startMinute))–\(BudgetRule.timeText(rule.endMinute))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(budget?.name ?? "（已刪除的預算）")
                .foregroundStyle(budget == nil || budget?.isArchived == true ? .secondary : .primary)
        }
    }
}

struct BudgetRuleEditor: View {
    let rule: BudgetRule?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EntryCategory.sortOrder) private var allCategories: [EntryCategory]
    @Query(filter: #Predicate<Budget> { !$0.isArchived }, sort: \Budget.sortOrder) private var budgets: [Budget]
    @Query private var rules: [BudgetRule]

    @State private var categoryID: UUID?
    @State private var budgetID: UUID?
    @State private var days: RuleDays = .weekdays
    @State private var allDay = true
    @State private var start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
    @State private var end = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now)!
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ThemedForm {
                Picker("分類", selection: $categoryID) {
                    Text("任何分類").tag(UUID?.none)
                    ForEach(allCategories.filter { $0.kind == .expense }) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("日子", selection: $days) {
                    ForEach(RuleDays.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Section {
                    Toggle("整天", isOn: $allDay)
                    if !allDay {
                        DatePicker("從", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("到", selection: $end, displayedComponents: .hourAndMinute)
                    }
                }
                Picker("預算", selection: $budgetID) {
                    Text("選擇預算").tag(UUID?.none)
                    ForEach(budgets) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .themedBackground()
            .navigationTitle(rule == nil ? "新增規則" : "編輯規則")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save).disabled(budgetID == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func minute(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func date(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now)!
    }

    private func load() {
        guard !loaded, let rule else { return }
        loaded = true
        categoryID = rule.categoryID
        budgetID = rule.budgetID
        days = rule.days
        allDay = rule.isAllDay
        start = date(rule.startMinute)
        end = date(rule.endMinute)
    }

    private func save() {
        guard let budgetID else { return }
        let target = rule ?? {
            let r = BudgetRule(categoryID: nil, budgetID: budgetID, days: days,
                               sortOrder: (rules.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(r)
            return r
        }()
        target.categoryID = categoryID
        target.budgetID = budgetID
        target.days = days
        target.startMinute = allDay ? 0 : minute(start)
        target.endMinute = allDay ? 23 * 60 + 59 : minute(end)
        try? context.save()
        dismiss()
    }
}
