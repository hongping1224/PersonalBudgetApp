import SwiftUI
import SwiftData

/// How much history an account page shows at first (設定 → 帳戶明細).
enum AccountHistory {
    static let monthsKey = "accountHistoryMonths"
    static let defaultMonths = 2

    static var months: Int {
        max(1, UserDefaults.standard.object(forKey: monthsKey) as? Int ?? defaultMonths)
    }

    /// Start of the range showing the last `months` months, this month included.
    static func start(months: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -(months - 1), to: calendar.startOfMonth(for: now))!
    }
}

struct AccountDetailView: View {
    let account: Account
    @Environment(\.modelContext) private var context
    @Query private var checks: [BalanceCheck]
    @State private var editingAccount = false
    @State private var editingEntry: Entry?
    @State private var from: Date
    @State private var to: Date

    init(account: Account) {
        self.account = account
        let id = account.id
        _checks = Query(filter: #Predicate<BalanceCheck> { $0.accountID == id }, sort: \BalanceCheck.date, order: .reverse)
        _from = State(initialValue: AccountHistory.start(months: AccountHistory.months))
        _to = State(initialValue: Calendar.current.startOfDay(for: .now))
    }

    private var allEntries: [Entry] { (account.entries ?? []) + (account.incomingTransfers ?? []) }

    private var groupedEntries: [(month: Date, entries: [Entry])] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
        let shown = allEntries.filter { $0.date >= start && $0.date < end }
        let groups = Dictionary(grouping: shown) { cal.startOfMonth(for: $0.date) }
        return groups.keys.sorted(by: >).map { key in
            (key, groups[key]!.sorted { $0.date > $1.date })
        }
    }

    private enum Row {
        case entry(Entry)
        case check(BalanceCheck)
        var id: UUID { switch self { case .entry(let e): e.id; case .check(let c): c.id } }
        var date: Date { switch self { case .entry(let e): e.date; case .check(let c): c.date } }
    }

    /// A month's records with the check-ins made in it, newest first.
    private func rows(for group: (month: Date, entries: [Entry])) -> [Row] {
        let cal = Calendar.current
        let inMonth = checks.filter { cal.isDate($0.date, equalTo: group.month, toGranularity: .month) }
        return (group.entries.map(Row.entry) + inMonth.map(Row.check)).sorted { $0.date > $1.date }
    }

    /// 對帳打卡: tap when the cash counted matches the recorded balance.
    private var checkInRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                BalanceCheck.record(account, in: context)
            } label: {
                Label("金額相符，對帳打卡", systemImage: "checkmark.seal.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(BalanceCheck.color)
            Group {
                if let last = checks.first {
                    Text("上次對帳 \(last.date.formatted(.dateTime.month(.defaultDigits).day().hour().minute()))，餘額 \(Money.string(last.balance, currency: account.currency))")
                } else {
                    Text("點錢包裡的錢和這裡的餘額一樣時，打一次卡。之後回頭核對只需要看到上次打卡的日期。")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var hasOlder: Bool {
        let start = Calendar.current.startOfDay(for: from)
        return allEntries.contains { $0.date < start }
    }

    var body: some View {
        ThemedList {
            Section {
                HStack {
                    Text("目前餘額")
                    Spacer()
                    Text(Money.string(account.balance, currency: account.currency))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(account.balance >= 0 ? Color.income : Color.expense)
                }
                if account.canCheckBalance {
                    checkInRow
                }
                if account.type == .creditCard {
                    if let limit = account.creditLimit {
                        LabeledContent("可用額度", value: Money.string(limit + account.balance, currency: account.currency))
                    }
                    if let due = account.nextDueDate {
                        LabeledContent("下次繳款", value: due.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let current = account.statementInterval(containing: .now) {
                        NavigationLink { StatementView(account: account) } label: {
                            LabeledContent("帳單明細") {
                                Text("本期 \(Money.string(account.statementTotal(in: current), currency: account.currency))，\(current.closingDate.formatted(.dateTime.month(.defaultDigits).day())) 出帳")
                            }
                        }
                    }
                }
            }
            Section {
                HStack(spacing: 4) {
                    DatePicker("從", selection: $from, in: ...to, displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    Text("–").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    DatePicker("到", selection: $to, in: from..., displayedComponents: .date)
                        .labelsHidden()
                }
            } header: {
                Text("顯示範圍")
            } footer: {
                Text("共 \(groupedEntries.reduce(0) { $0 + $1.entries.count }) 筆")
            }
            ForEach(groupedEntries, id: \.month) { group in
                Section(group.month.monthTitle) {
                    // Check-ins sit among the records at their time, so it's clear where checking back can stop.
                    ForEach(rows(for: group), id: \.id) { row in
                        switch row {
                        case .entry(let entry):
                            Button { editingEntry = entry } label: { EntryRow(entry: entry, showDate: true) }
                                .tint(.primary)
                        case .check(let check):
                            CheckInRow(check: check, currency: account.currency)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        context.delete(check)
                                        try? context.save()
                                    } label: { Label("刪除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            Section {
                if hasOlder {
                    Button {
                        withAnimation { from = Calendar.current.date(byAdding: .month, value: -1, to: from)! }
                    } label: {
                        Label("再載入一個月", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("沒有更早的紀錄").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .themedBackground()
        .navigationTitle(account.name)
        .toolbar { Button("編輯") { editingAccount = true } }
        .sheet(isPresented: $editingAccount) { AccountEditor(account: account) }
        .sheet(item: $editingEntry) { EntryEditor(entry: $0) }
    }
}

struct AccountEditor: View {
    let account: Account?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allAccounts: [Account]

    @State private var name = ""
    @State private var type: AccountType = .bank
    @State private var currency = Currency.base
    @State private var groupName = ""
    @State private var balanceText = ""
    @State private var limitText = ""
    @State private var hasDueDay = false
    @State private var dueDay = 1
    @State private var hasStatementDay = false
    @State private var statementDay = 1
    @State private var isArchived = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    TextField("名稱，例如 我的信用卡", text: $name)
                    Picker("類型", selection: $type) {
                        ForEach(AccountType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("幣別", selection: $currency) {
                        ForEach(Currency.all) { Text("\($0.name) \($0.code)").tag($0.code) }
                    }
                    .disabled((account?.entryCount ?? 0) > 0)
                } footer: {
                    if (account?.entryCount ?? 0) > 0 {
                        Text("已有紀錄的帳戶不能改幣別。")
                    }
                }
                Section {
                    TextField("例如 銀行名稱（可不填）", text: $groupName)
                        .accessibilityLabel("銀行或群組")
                    let others = existingGroups
                    if !others.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(others, id: \.self) { group in
                                    Button(group) { groupName = group }
                                        .font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.themeFill, in: Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: {
                    Text("銀行或群組")
                } footer: {
                    Text("同類型帳戶填一樣的名字，會排在一起並顯示合計。同一個銀行帳戶裡分開管理的錢，也可以各建一個帳戶放進同一組。")
                }
                Section {
                    TextField("0", text: $balanceText).keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("目前餘額")
                } footer: {
                    Text(type == .creditCard ? "信用卡欠款請填負數，例如 -5000。" : "修改這個數字會自動調整帳戶的初始餘額，不會影響任何紀錄。")
                }
                if type == .creditCard {
                    Section("信用卡") {
                        TextField("信用額度", text: $limitText).keyboardType(.decimalPad)
                        Toggle("繳款截止日", isOn: $hasDueDay)
                        if hasDueDay {
                            Stepper("每月 \(dueDay) 號", value: $dueDay, in: 1...31)
                        }
                        Toggle("出帳日", isOn: $hasStatementDay)
                        if hasStatementDay {
                            Stepper("每月 \(statementDay) 號", value: $statementDay, in: 1...31)
                        }
                    }
                }
                if let account {
                    Section {
                        Toggle("封存", isOn: $isArchived)
                        if account.entryCount == 0 {
                            Button("刪除帳戶", role: .destructive) { confirmDelete = true }
                        }
                    } footer: {
                        if account.entryCount > 0 {
                            Text("這個帳戶有 \(account.entryCount) 筆紀錄，不能刪除，可以改用封存。")
                        }
                    }
                }
            }
            .themedBackground()
            .navigationTitle(account == nil ? "新增帳戶" : "編輯帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("刪除「\(name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let account { context.delete(account); try? context.save() }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    /// Group names already used, to pick from.
    private var existingGroups: [String] {
        let trimmed = groupName.trimmingCharacters(in: .whitespaces)
        return Array(Set(allAccounts.map(\.groupName))).filter { !$0.isEmpty && $0 != trimmed }.sorted()
    }

    private func load() {
        guard let account else { return }
        name = account.name
        groupName = account.groupName
        type = account.type
        currency = account.currency
        balanceText = Money.plain(account.balance)
        limitText = account.creditLimit.map(Money.plain) ?? ""
        hasDueDay = account.paymentDueDay != nil
        dueDay = account.paymentDueDay ?? 1
        hasStatementDay = account.statementDay != nil
        statementDay = account.statementDay ?? 1
        isArchived = account.isArchived
    }

    private func save() {
        let target = account ?? {
            let a = Account(name: "", type: type)
            a.sortOrder = (allAccounts.map(\.sortOrder).max() ?? 0) + 1
            context.insert(a)
            return a
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.groupName = groupName.trimmingCharacters(in: .whitespaces)
        target.type = type
        if target.entryCount == 0 { target.currency = currency }
        if let wanted = Double(balanceText.replacingOccurrences(of: ",", with: "")) {
            target.initialBalance += wanted - target.balance
        }
        target.creditLimit = type == .creditCard ? Double(limitText.replacingOccurrences(of: ",", with: "")) : nil
        target.paymentDueDay = type == .creditCard && hasDueDay ? dueDay : nil
        target.statementDay = type == .creditCard && hasStatementDay ? statementDay : nil
        target.isArchived = isArchived
        try? context.save()
        StatementReminder.reschedule(context: context)
        dismiss()
    }
}

/// A check-in among an account's records.
struct CheckInRow: View {
    let check: BalanceCheck
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: "checkmark.seal.fill", color: BalanceCheck.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("對帳打卡")
                Text(check.date.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(check.balance, currency: currency))
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(BalanceCheck.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("check-in")
    }
}
