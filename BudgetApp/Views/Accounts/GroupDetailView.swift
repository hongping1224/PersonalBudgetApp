import SwiftUI
import SwiftData

/// A bank (or other group) of accounts: its total, its accounts, and all their records together.
struct GroupDetailView: View {
    let name: String
    let type: AccountType

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage(BalanceMode.includeFutureKey) private var includeFuture = false
    /// The range end is set once on first appearance, so coming back keeps a range picked by hand.
    @State private var rangeSet = false
    @State private var editingEntry: Entry?
    @State private var editingNumber = false
    @State private var from = AccountHistory.start(months: AccountHistory.months)
    @State private var to = Calendar.current.startOfDay(for: .now)

    private var members: [Account] {
        accounts.filter { !$0.isArchived && $0.type == type && $0.groupName == name }
    }

    /// Every record touching the group; a transfer between two of its accounts counts once.
    private var allEntries: [Entry] {
        var seen = Set<PersistentIdentifier>()
        return members.flatMap { ($0.entries ?? []) + ($0.incomingTransfers ?? []) }
            .filter { seen.insert($0.persistentModelID).inserted }
    }

    private var groupedEntries: [(month: Date, entries: [Entry])] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
        let groups = Dictionary(grouping: allEntries.filter { $0.date >= start && $0.date < end }) {
            cal.startOfMonth(for: $0.date)
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        let total = AccountListItem.total(of: members, includeFuture: includeFuture)
        let futureCount = allEntries.filter { $0.date >= BalanceMode.cutoff() }.count
        ThemedList {
            Section {
                HStack {
                    Text(includeFuture ? "含未來紀錄的合計" : "合計")
                    Spacer()
                    Text(Money.string(total.amount, currency: total.currency))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(total.amount >= 0 ? Color.income : Color.expense)
                        .accessibilityIdentifier("group-total")
                }
                if futureCount > 0 {
                    let other = AccountListItem.total(of: members, includeFuture: !includeFuture)
                    BalanceModeRow(includeFuture: $includeFuture, futureCount: futureCount,
                                   otherAmount: Money.string(other.amount, currency: other.currency))
                }
                ForEach(members) { account in
                    NavigationLink { AccountDetailView(account: account) } label: {
                        AccountRow(account: account, balance: account.balance(includeFuture: includeFuture))
                    }
                }
            }
            if type == .bank {
                Section {
                    if let shared = AccountGroupNumber(of: members) {
                        AccountNumberRow(bankCode: shared.bankCode, number: shared.number)
                        Button("修改帳號") { editingNumber = true }
                    } else if members.contains(where: { !$0.accountNumber.isEmpty }) {
                        Text("群組裡的帳戶帳號不一樣。").foregroundStyle(.secondary)
                        Button("設成同一個帳號") { editingNumber = true }
                    } else {
                        Button { editingNumber = true } label: { Label("新增帳號", systemImage: "plus") }
                    }
                } header: {
                    Text("銀行帳號")
                } footer: {
                    Text("同一個銀行帳戶分成幾個部分時，帳號設在這裡，群組裡的帳戶都會用這個帳號。")
                }
            }
            Section {
                HStack(spacing: 4) {
                    DatePicker("從", selection: $from, in: ...to, displayedComponents: .date).labelsHidden()
                    Spacer(minLength: 0)
                    Text("–").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    DatePicker("到", selection: $to, in: from..., displayedComponents: .date).labelsHidden()
                }
            } header: {
                Text("顯示範圍")
            } footer: {
                Text("共 \(groupedEntries.reduce(0) { $0 + $1.entries.count }) 筆")
            }
            ForEach(groupedEntries, id: \.month) { group in
                Section(group.month.monthTitle) {
                    ForEach(group.entries) { entry in
                        Button { editingEntry = entry } label: { EntryRow(entry: entry, showDate: true) }
                            .tint(.primary)
                            .accessibilityIdentifier("group-entry")
                    }
                }
            }
            Section {
                if allEntries.contains(where: { $0.date < Calendar.current.startOfDay(for: from) }) {
                    Button {
                        withAnimation { from = Calendar.current.date(byAdding: .month, value: -1, to: from)! }
                    } label: {
                        Label("再載入一個月", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                    }
                } else {
                    Text("沒有更早的紀錄").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .themedBackground()
        .navigationTitle(name)
        .sheet(item: $editingEntry) { EntryEditor(entry: $0) }
        .sheet(isPresented: $editingNumber) { GroupNumberEditor(name: name, members: members) }
        .onAppear {
            guard !rangeSet else { return }
            rangeSet = true
            to = BalanceMode.rangeEnd(includeFuture: includeFuture, entries: allEntries)
        }
        .onChange(of: includeFuture) { _, _ in to = BalanceMode.rangeEnd(includeFuture: includeFuture, entries: allEntries) }
    }
}

/// Shown when there are future-dated records: the other way of counting, and a switch to it.
struct BalanceModeRow: View {
    @Binding var includeFuture: Bool
    let futureCount: Int
    let otherAmount: String

    var body: some View {
        HStack {
            Text(includeFuture ? "只算到今天 \(otherAmount)" : "含未來 \(futureCount) 筆 \(otherAmount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button(includeFuture ? "只算到今天" : "納入未來紀錄") { includeFuture.toggle() }
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }
}

extension BalanceMode {
    /// Last day a record list shows: today, or the last future record when those are counted.
    static func rangeEnd(includeFuture: Bool, entries: [Entry]) -> Date {
        let today = Calendar.current.startOfDay(for: .now)
        guard includeFuture, let last = entries.map(\.date).max() else { return today }
        return max(today, Calendar.current.startOfDay(for: last))
    }
}

/// A bank group's 帳號: the one its accounts share, when they all have the same one.
struct AccountGroupNumber {
    let bankCode: String
    let number: String

    init?(of members: [Account]) {
        let withNumber = members.filter { !$0.accountNumber.isEmpty }
        guard let first = withNumber.first,
              withNumber.allSatisfy({ $0.accountNumber.filter(\.isNumber) == first.accountNumber.filter(\.isNumber) })
        else { return nil }
        bankCode = withNumber.first { !$0.bankCode.isEmpty }?.bankCode ?? ""
        number = first.accountNumber
    }
}

/// 帳號 with a copy button; copies digits only, the way bank apps take it.
struct AccountNumberRow: View {
    let bankCode: String
    let number: String
    @State private var copied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("帳號").font(.caption).foregroundStyle(.secondary)
                Text(bankCode.isEmpty ? number : "(\(bankCode)) \(number)")
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = number.filter(\.isNumber)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "已複製" : "複製帳號", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
            .accessibilityIdentifier("copy-account-number")
        }
    }
}

/// Sets one 銀行代碼 and 帳號 on every account in a bank group.
struct GroupNumberEditor: View {
    let name: String
    let members: [Account]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var bankCode = ""
    @State private var number = ""

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    TextField("銀行代碼，例如 812", text: $bankCode).keyboardType(.numberPad)
                    TextField("帳號", text: $number).keyboardType(.numbersAndPunctuation)
                } footer: {
                    Text("會套用到「\(name)」裡的 \(members.count) 個帳戶。")
                }
            }
            .navigationTitle("\(name) 帳號")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        for account in members {
                            account.bankCode = bankCode.trimmingCharacters(in: .whitespaces)
                            account.accountNumber = number.trimmingCharacters(in: .whitespaces)
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let shared = AccountGroupNumber(of: members)
                bankCode = shared?.bankCode ?? members.first { !$0.bankCode.isEmpty }?.bankCode ?? ""
                number = shared?.number ?? ""
            }
        }
    }
}
