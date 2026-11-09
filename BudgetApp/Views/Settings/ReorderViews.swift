import SwiftUI
import SwiftData

/// Drag to reorder budgets (archived ones stay at the end, as in the 預算 tab).
struct BudgetOrderView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Budget> { !$0.isArchived }, sort: \Budget.sortOrder) private var budgets: [Budget]

    var body: some View {
        ThemedList {
            ForEach(budgets) { b in
                Label(b.name, systemImage: b.symbol)
            }
            .onMove { from, to in
                var items = budgets
                items.move(fromOffsets: from, toOffset: to)
                for (i, b) in items.enumerated() { b.sortOrder = i }
                try? context.save()
            }
        }
        .environment(\.editMode, .constant(.active))
        .themedBackground()
        .navigationTitle("預算排序")
    }
}

/// Drag to reorder accounts within each type, matching how the 帳戶 tab groups them.
struct AccountOrderView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        ThemedList {
            ForEach(AccountType.allCases) { type in
                let group = accounts.filter { $0.type == type }
                if !group.isEmpty {
                    Section(type.title) {
                        ForEach(group) { a in
                            Label(a.fullName, systemImage: a.type.symbol)
                        }
                        .onMove { from, to in move(in: group, from: from, to: to) }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .themedBackground()
        .navigationTitle("帳戶排序")
    }

    private func move(in group: [Account], from: IndexSet, to: Int) {
        var items = group
        items.move(fromOffsets: from, toOffset: to)
        // Put the reordered group back into the slots it held, then renumber everything.
        var all = accounts
        let slots = all.indices.filter { all[$0].type == group.first?.type }
        for (slot, account) in zip(slots, items) { all[slot] = account }
        for (i, a) in all.enumerated() { a.sortOrder = i }
        try? context.save()
    }
}
