import SwiftUI
import SwiftData

/// Splits part of an expense into its own entry, e.g. a friend's share of a bill you paid.
struct SplitEntrySheet: View {
    let entry: Entry
    var onSplit: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Budget> { !$0.isArchived }, sort: \Budget.sortOrder) private var budgets: [Budget]

    @State private var amountText = ""
    @State private var name = ""
    @State private var budget: Budget?
    @State private var loaded = false

    private var part: Double? { Double(amountText) }
    private var isValid: Bool { (part ?? 0) > 0 && (part ?? 0) < entry.amount }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    LabeledContent("原本金額", value: Money.string(entry.amount))
                    TextField("拆出金額", text: $amountText)
                        .keyboardType(.decimalPad)
                    if let part, isValid {
                        LabeledContent("原本這筆留下", value: Money.string(entry.amount - part))
                    }
                    Button("拆一半") { amountText = Money.plain((entry.amount / 2).rounded()) }
                } footer: {
                    Text("拆出的金額會變成另一筆支出，日期、分類和帳戶都一樣。")
                }
                Section {
                    TextField("名稱", text: $name)
                    Picker("預算", selection: $budget) {
                        Text("無預算").tag(Budget?.none)
                        ForEach(budgets) { Text($0.name).tag(Optional($0)) }
                    }
                } header: {
                    Text("拆出的這筆")
                }
            }
            .themedBackground()
            .navigationTitle("拆分支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("拆分", action: split).disabled(!isValid)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = entry.name
                budget = budgets.first { $0.isClaim }
            }
        }
    }

    private func split() {
        guard let part, isValid else { return }
        EntryService.split(entry, part: part, name: name.trimmingCharacters(in: .whitespaces),
                           budget: budget, in: context)
        onSplit()
    }
}

/// Marks a claimed expense as paid back: picks the account the money went into.
struct ClaimSettleSheet: View {
    let entry: Entry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]

    @State private var account: Account?
    @State private var date = Date.now
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    LabeledContent("名稱", value: entry.displayName)
                    LabeledContent("金額", value: Money.string(entry.amount))
                }
                Section {
                    Picker("收到的帳戶", selection: $account) {
                        ForEach(AccountType.allCases) { type in
                            // Repaid in the same currency, so only accounts in it.
                            let group = accounts.filter { $0.type == type && $0.currency == entry.currency }
                            if !group.isEmpty {
                                Section(type.title) {
                                    ForEach(group) { Text($0.name).tag(Optional($0)) }
                                }
                            }
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } footer: {
                    Text("這筆支出會移出「\(entry.budget?.name ?? "")」，並記一筆 \(Money.string(entry.amount)) 的收入。")
                }
            }
            .themedBackground()
            .navigationTitle("已還款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        if let account { EntryService.settleClaim(entry, into: account, date: date, in: context) }
                        dismiss()
                    }
                    .disabled(account == nil)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                account = accounts.first { $0.id == entry.account?.id } ?? accounts.first
            }
        }
        .presentationDetents([.medium, .large])
    }
}
