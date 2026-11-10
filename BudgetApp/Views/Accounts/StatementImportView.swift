import SwiftUI
import SwiftData

/// A bank's PDF bill shared into the app (from Mail or Files).
struct SharedStatement: Identifiable {
    let id = UUID()
    let data: Data
}

/// Pick the card, unlock the PDF and compare the bank's bill with the records.
struct StatementImportView: View {
    let data: Data
    var preselected: Account?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("lastStatementImportAccount") private var lastAccountID = ""

    @State private var accountID: UUID?
    @State private var password = ""
    @State private var remember = false
    @State private var statement: ParsedStatement?
    @State private var problem: String?
    @State private var editingEntry: Entry?
    @State private var checkedIn = false
    /// Bills before (negative) or after the one picked by default, when it guessed wrong.
    @State private var billOffset = 0

    private var cards: [Account] {
        let active = accounts.filter { !$0.isArchived }
        let credit = active.filter { $0.type == .creditCard }
        return credit.isEmpty ? active : credit
    }

    private var account: Account? { cards.first { $0.id == accountID } }
    private var locked: Bool { ParsedStatement.isLocked(data) }

    var body: some View {
        NavigationStack {
            ThemedList {
                if let statement, let account {
                    results(statement, account: account)
                } else {
                    setup
                }
            }
            .themedBackground()
            .navigationTitle("帳單對帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } }
                if statement != nil {
                    ToolbarItem(placement: .primaryAction) { Button("重選") { statement = nil } }
                }
            }
            .sheet(item: $editingEntry) { EntryEditor(entry: $0) }
            .onAppear(perform: start)
        }
    }

    // MARK: Setup

    private var setup: some View {
        Group {
            Section("要對帳的帳戶") {
                Picker("帳戶", selection: $accountID) {
                    ForEach(cards) { Text($0.fullName).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: accountID) { _, id in loadPassword(for: id) }
            }
            if locked {
                Section {
                    SecureField("PDF 密碼", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("pdf-password")
                        .onSubmit(read)
                    Toggle("記住這張卡的密碼", isOn: $remember)
                } header: {
                    Text("這份 PDF 有密碼")
                } footer: {
                    Text("密碼只用來在手機上打開 PDF。記住的密碼存在這支手機的鑰匙圈，不會同步或備份。")
                }
            }
            Section {
                Button("開始對帳", action: read)
                    .frame(maxWidth: .infinity)
                    .disabled(account == nil || (locked && password.isEmpty))
                if let problem {
                    Text(problem).foregroundStyle(Color.expense).font(.subheadline)
                }
            }
        }
    }

    private func start() {
        guard accountID == nil else { return }
        accountID = preselected?.id ?? cards.first { $0.id.uuidString == lastAccountID }?.id ?? cards.first?.id
        loadPassword(for: accountID)
    }

    private func loadPassword(for id: UUID?) {
        guard let id, let saved = StatementPasswords.load(for: id) else {
            password = ""; remember = false; return
        }
        password = saved
        remember = true
    }

    private func read() {
        guard let account else { return }
        do {
            statement = try ParsedStatement.read(data, password: locked ? password : nil)
            billOffset = 0
            problem = nil
            lastAccountID = account.id.uuidString
            if locked {
                if remember { StatementPasswords.save(password, for: account.id) }
                else { StatementPasswords.delete(for: account.id) }
            }
        } catch ParsedStatement.Failure.wrongPassword {
            problem = "密碼不對，請再試一次。"
        } catch ParsedStatement.Failure.locked {
            problem = "請輸入 PDF 密碼。"
        } catch ParsedStatement.Failure.noItems {
            problem = "打開了，但讀不到消費明細。這家銀行的帳單格式可能還不支援。"
        } catch {
            problem = "無法讀取這份 PDF。"
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ statement: ParsedStatement, account: Account) -> some View {
        let base = StatementReconciliation.defaultInterval(for: statement, account: account)
        let bill = base.flatMap { account.statementInterval(offset: billOffset, from: $0) }
        let r = StatementReconciliation(statement: statement, account: account, interval: bill)
        let bankTotal = statement.newCharges ?? statement.charges.reduce(0) { $0 + $1.amount }
        let difference = r.appTotal - bankTotal
        let elsewhere = r.matched.filter(\.otherBill)
        let ok = r.allMatch && elsewhere.isEmpty && abs(difference) < 0.5

        Section {
            VStack(spacing: 6) {
                Label(ok ? "完全相符" : "有 \(r.missing.count + r.extra.count + elsewhere.count) 筆對不上",
                      systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ok ? BalanceCheck.color : Color.expense)
                    .accessibilityIdentifier("reconcile-status")
                Text(account.fullName).font(.subheadline).foregroundStyle(.secondary)
                if let closing = statement.closingDate {
                    Text("結帳日 \(closing.formatted(.dateTime.year().month(.defaultDigits).day()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            if let bill {
                HStack {
                    Button { billOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("上一期")
                    Spacer()
                    VStack(spacing: 2) {
                        Text("App 的帳單").font(.caption).foregroundStyle(.secondary)
                        Text(bill.shortLabel).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .accessibilityIdentifier("reconcile-bill")
                    }
                    Spacer()
                    Button { billOffset += 1 } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("下一期")
                }
                .buttonStyle(.borderless)
            }
            LabeledContent("銀行帳單新增", value: Money.string(bankTotal))
            LabeledContent("App 這期消費", value: Money.string(r.appTotal))
            if abs(difference) >= 0.5 {
                LabeledContent("差額", value: Money.string(difference, signed: true))
                    .foregroundStyle(Color.expense)
            }
            if let due = statement.amountDue {
                LabeledContent("本期應繳", value: Money.string(due))
            }
            if ok {
                Button {
                    let end = Calendar.current.date(byAdding: .day, value: 1,
                                                    to: Calendar.current.startOfDay(for: statement.closingDate ?? .now))!
                    context.insert(BalanceCheck(account: account, date: end.addingTimeInterval(-1)))
                    try? context.save()
                    checkedIn = true
                } label: {
                    Label(checkedIn ? "已打卡" : "對帳打卡", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BalanceCheck.color)
                .disabled(checkedIn)
            }
        }

        if !r.missing.isEmpty {
            Section {
                ForEach(r.missing) { item in
                    HStack {
                        itemLabel(item)
                        if !item.isPayment {
                            Button("加到 App") { add(item, to: account) }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("帳單有、App 沒有 (\(r.missing.count))")
            } footer: {
                Text("「加到 App」會用帳單上的日期和金額記一筆，再打開讓你選分類。繳款請記成轉帳到這張卡。")
            }
        }

        if !r.extra.isEmpty {
            Section {
                ForEach(r.extra) { entry in
                    HStack {
                        Button { editingEntry = entry } label: { EntryRow(entry: entry, showDate: true) }
                            .tint(.primary)
                        if r.interval != nil, entry.account?.persistentModelID == account.persistentModelID {
                            Button("移到下期") {
                                entry.statementOffset += 1
                                try? context.save()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text("App 有、帳單沒有 (\(r.extra.count))")
            } footer: {
                Text("通常是銀行還沒入帳的消費，可以移到下期；也可能是記錯金額或記錯卡。")
            }
        }

        if !r.matched.isEmpty {
            let movable = r.matched.filter {
                $0.otherBill && $0.entry.account?.persistentModelID == account.persistentModelID
            }
            Section("已對上 (\(r.matched.count))") {
                if let interval = r.interval, movable.count > 1 {
                    Button {
                        for match in movable { account.move(match.entry, toBill: interval) }
                        try? context.save()
                    } label: {
                        Label("全部 \(movable.count) 筆移到這期", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                ForEach(r.matched) { match in
                    HStack {
                        Button { editingEntry = match.entry } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                itemLabel(match.item)
                                if match.otherBill {
                                    Text("App 裡算在別期").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                        .tint(.primary)
                        if match.otherBill, let interval = r.interval,
                           match.entry.account?.persistentModelID == account.persistentModelID {
                            Button("移到這期") {
                                account.move(match.entry, toBill: interval)
                                try? context.save()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func itemLabel(_ item: ParsedStatement.Item) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.date.formatted(.dateTime.month(.defaultDigits).day()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(item.amount))
                .monospacedDigit()
                .foregroundStyle(item.amount < 0 ? Color.income : Color.expense)
        }
    }

    private func add(_ item: ParsedStatement.Item, to account: Account) {
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: item.date))!
        let entry = EntryService.add(kind: item.amount < 0 ? .income : .expense, amount: abs(item.amount), date: noon,
                                     name: item.name, category: nil, account: account, in: context)
        editingEntry = entry
    }
}
