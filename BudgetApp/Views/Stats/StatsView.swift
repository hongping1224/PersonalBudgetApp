import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var kind: EntryKind = .expense

    var body: some View {
        NavigationStack {
            MonthStats(month: month, kind: kind)
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 8) {
                        HStack {
                            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: {
                                Image(systemName: "chevron.left")
                            }
                            Spacer()
                            Text(month.monthTitle).font(.headline)
                            Spacer()
                            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: {
                                Image(systemName: "chevron.right")
                            }
                        }
                        Picker("類型", selection: $kind) {
                            Text("支出").tag(EntryKind.expense)
                            Text("收入").tag(EntryKind.income)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
                .themedBackground()
                .navigationTitle("統計")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MonthStats: View {
    let month: Date
    let kind: EntryKind
    @Query private var entries: [Entry]

    init(month: Date, kind: EntryKind) {
        self.month = month
        self.kind = kind
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month)!
        let raw = kind.rawValue
        _entries = Query(filter: #Predicate<Entry> { $0.date >= month && $0.date < end && $0.kindRaw == raw },
                         sort: \Entry.date, order: .reverse)
    }

    private struct Slice: Identifiable {
        let category: EntryCategory?
        let total: Double
        let entries: [Entry]
        var id: String { category?.id.uuidString ?? "none" }
        var name: String { category?.name ?? "未分類" }
        var color: Color { Color(hex: category?.colorHex ?? "#8A9099") }
    }

    private var slices: [Slice] {
        Dictionary(grouping: entries) { $0.category?.id }
            .map { _, items in Slice(category: items.first?.category, total: items.reduce(0) { $0 + $1.baseAmount }, entries: items) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        let slices = slices
        let total = slices.reduce(0) { $0 + $1.total }
        ThemedList {
            if slices.isEmpty {
                ContentUnavailableView("這個月沒有\(kind.title)", systemImage: "chart.pie")
            } else {
                Section {
                    Chart(slices) { s in
                        SectorMark(angle: .value("金額", s.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(s.color)
                    }
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("總\(kind.title)").font(.caption).foregroundStyle(.secondary)
                            Text(Money.string(total)).font(.title3.weight(.bold).monospacedDigit())
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    ForEach(slices) { s in
                        NavigationLink {
                            List(s.entries) { EntryRow(entry: $0, showDate: true) }
                                .themedBackground()
                                .navigationTitle(s.name)
                        } label: {
                            HStack(spacing: 12) {
                                SymbolBadge(symbol: s.category?.symbol ?? "questionmark", color: s.color, size: 36)
                                VStack(alignment: .leading) {
                                    Text(s.name)
                                    Text("\(s.entries.count) 筆").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(Money.string(s.total)).monospacedDigit()
                                    Text(String(format: "%.1f%%", s.total / total * 100))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
