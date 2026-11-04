import SwiftUI
import SwiftData
import Charts

struct AccountsView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Entry.date) private var entries: [Entry]
    @State private var creating = false
    @State private var showArchived = false
    @State private var hideAmounts = false
    @State private var expanded: Set<AccountType> = Set(AccountType.allCases)
    @AppStorage("netWorthCollapsed") private var netWorthCollapsed = false

    var body: some View {
        NavigationStack {
            ThemedList {
                let active = accounts.filter { !$0.isArchived }
                let balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balance) })
                // Net worth in TWD; foreign-currency accounts at today's rate.
                let baseBalances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.baseBalance) })
                let assets = active.map { baseBalances[$0.id] ?? 0 }.filter { $0 > 0 }.reduce(0, +)
                let debts = active.map { baseBalances[$0.id] ?? 0 }.filter { $0 < 0 }.reduce(0, +)

                Section {
                    if netWorthCollapsed {
                        // Collapsed: just the net worth figure.
                        Button { withAnimation { netWorthCollapsed = false } } label: {
                            HStack {
                                Text("淨資產").foregroundStyle(.secondary)
                                Spacer()
                                Text(mask(Money.string(assets + debts)))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(assets + debts >= 0 ? Color.income : Color.expense)
                                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                        .accessibilityLabel("展開淨資產")
                    } else {
                        VStack(spacing: 6) {
                            Text("淨資產").font(.subheadline).foregroundStyle(.secondary)
                            Text(mask(Money.string(assets + debts)))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(assets + debts >= 0 ? Color.income : Color.expense)
                                .monospacedDigit()
                            HStack(spacing: 16) {
                                Text("資產 ") + Text(mask(Money.plain(assets))).foregroundColor(.income)
                                Text("負債 ") + Text(mask(Money.plain(-debts))).foregroundColor(.expense)
                            }
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(alignment: .topTrailing) {
                            Button { withAnimation { netWorthCollapsed = true } } label: {
                                Image(systemName: "chevron.up").font(.caption).padding(6)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("收合淨資產")
                        }

                        TrendChart(entries: entries, accounts: accounts)
                            .frame(height: 220)
                            .padding(.vertical, 8)
                    }
                }

                ForEach(AccountType.allCases) { type in
                    let group = active.filter { $0.type == type }
                    if !group.isEmpty {
                        Section(isExpanded: binding(for: type)) {
                            ForEach(group) { account in
                                NavigationLink { AccountDetailView(account: account) } label: {
                                    AccountRow(account: account, balance: balances[account.id] ?? 0, masked: hideAmounts)
                                }
                            }
                        } header: {
                            HStack {
                                Text("\(type.title) (\(group.count))")
                                Spacer()
                                Text(mask(Money.string(group.map { baseBalances[$0.id] ?? 0 }.reduce(0, +), signed: true)))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                let archived = accounts.filter(\.isArchived)
                if !archived.isEmpty {
                    Section("已封存 (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { account in
                            NavigationLink { AccountDetailView(account: account) } label: {
                                AccountRow(account: account, balance: balances[account.id] ?? 0, masked: hideAmounts)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink { SettingsView() } label: { Label("設定、分類與備份", systemImage: "gearshape") }
                }
            }
            .listStyle(.sidebar)
            .themedBackground()
            .navigationTitle("帳戶")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { hideAmounts.toggle() } label: { Image(systemName: hideAmounts ? "eye.slash" : "eye") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AppRouter.shared.showCarrier = true } label: { Image(systemName: "barcode") }
                        .accessibilityLabel("載具條碼")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新增帳戶")
                }
            }
            .sheet(isPresented: $creating) { AccountEditor(account: nil) }
        }
    }

    private func mask(_ s: String) -> String { hideAmounts ? "＊＊＊＊" : s }

    private func binding(for type: AccountType) -> Binding<Bool> {
        Binding(get: { expanded.contains(type) },
                set: { if $0 { expanded.insert(type) } else { expanded.remove(type) } })
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Double
    var masked = false

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: account.type.symbol, color: Color(hex: "#5C6F82"), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if account.type == .creditCard, let limit = account.creditLimit {
                    Text("可用額度 \(masked ? "＊＊＊" : Money.string(limit + balance, currency: account.currency))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(masked ? "＊＊＊" : Money.string(balance, currency: account.currency))
                    .monospacedDigit()
                    .foregroundStyle(balance >= 0 ? Color.income : Color.expense)
                if account.type == .creditCard, balance < 0, let due = account.nextDueDate {
                    Text("\(due.formatted(.dateTime.month(.defaultDigits).day())) 繳款")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.teal, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

extension Account {
    /// Next occurrence of the payment due day, today included.
    var nextDueDate: Date? {
        guard let day = paymentDueDay else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let thisMonth = cal.day(day, inMonthOf: today)
        if thisMonth >= today { return thisMonth }
        return cal.day(day, inMonthOf: cal.date(byAdding: .month, value: 1, to: cal.startOfMonth(for: today))!)
    }
}

/// Monthly expense/income bars, or net worth over the last 12 months.
struct TrendChart: View {
    let entries: [Entry]
    let accounts: [Account]

    enum Mode: String, CaseIterable { case flow = "收支", netWorth = "淨資產" }
    @State private var mode: Mode = .flow

    private struct MonthPoint: Identifiable {
        let month: Date
        let expense: Double
        let income: Double
        let netWorth: Double
        var id: Date { month }
    }

    private var points: [MonthPoint] {
        let cal = Calendar.current
        let thisMonth = cal.startOfMonth(for: .now)
        let months = (0..<12).reversed().map { cal.date(byAdding: .month, value: -$0, to: thisMonth)! }
        let initial = accounts.reduce(0) { $0 + $1.initialBalance * Currency.rate($1.currency) }
        // entries are sorted by date, so walk them once.
        var running = initial
        var index = 0
        var result: [MonthPoint] = []
        for month in months {
            let end = cal.date(byAdding: .month, value: 1, to: month)!
            var expense = 0.0, income = 0.0
            while index < entries.count && entries[index].date < end {
                let e = entries[index]
                running += e.signedAmount
                if e.date >= month {
                    if e.kind == .expense { expense += e.baseAmount }
                    if e.kind == .income { income += e.baseAmount }
                }
                index += 1
            }
            result.append(MonthPoint(month: month, expense: expense, income: income, netWorth: running))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("圖表", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(points) { p in
                if mode == .flow {
                    BarMark(x: .value("月份", p.month, unit: .month), y: .value("金額", p.expense))
                        .foregroundStyle(by: .value("類型", "支出"))
                        .position(by: .value("類型", "支出"))
                    BarMark(x: .value("月份", p.month, unit: .month), y: .value("金額", p.income))
                        .foregroundStyle(by: .value("類型", "收入"))
                        .position(by: .value("類型", "收入"))
                } else {
                    AreaMark(x: .value("月份", p.month, unit: .month), y: .value("淨資產", p.netWorth))
                        .foregroundStyle(Color.purple.opacity(0.2).gradient)
                    LineMark(x: .value("月份", p.month, unit: .month), y: .value("淨資產", p.netWorth))
                        .foregroundStyle(Color.purple)
                        .symbol(.circle)
                }
            }
            .chartForegroundStyleScale(["支出": Color.expense, "收入": Color.income])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(abs(v) >= 10_000 ? "\(Money.plain((v / 1000).rounded()))K" : Money.plain(v))
                        }
                    }
                }
            }
        }
    }
}
