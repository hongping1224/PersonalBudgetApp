import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var editing: Entry?

    var body: some View {
        NavigationStack {
            MonthContent(month: month, selectedDay: $selectedDay, editing: $editing)
                .themedBackground()
                .navigationTitle(selectedDay.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("今天") { jump(to: .now) }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        shiftMonth(value.translation.width < 0 ? 1 : -1)
                    }
                )
                .sheet(item: $editing) { EntryEditor(entry: $0) }
                .onChange(of: selectedDay, initial: true) { _, day in
                    AppRouter.shared.preferredDate = day
                }
        }
    }

    private func shiftMonth(_ delta: Int) {
        let cal = Calendar.current
        let newMonth = cal.date(byAdding: .month, value: delta, to: month)!
        month = newMonth
        // Keep the same day number when possible.
        let day = cal.component(.day, from: selectedDay)
        selectedDay = cal.day(day, inMonthOf: newMonth)
    }

    private func jump(to date: Date) {
        month = Calendar.current.startOfMonth(for: date)
        selectedDay = Calendar.current.startOfDay(for: date)
    }
}

/// Everything that depends on the visible month, so the query can be scoped to it.
private struct MonthContent: View {
    let month: Date
    @Binding var selectedDay: Date
    @Binding var editing: Entry?

    @Environment(\.modelContext) private var context
    @Query private var entries: [Entry]

    private let gridDays: [Date]

    init(month: Date, selectedDay: Binding<Date>, editing: Binding<Entry?>) {
        self.month = month
        _selectedDay = selectedDay
        _editing = editing
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: month) // grid starts on Sunday
        let start = cal.date(byAdding: .day, value: -(weekday - 1), to: month)!
        gridDays = (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let end = gridDays.last!.addingTimeInterval(86_400)
        _entries = Query(filter: #Predicate<Entry> { $0.date >= start && $0.date < end },
                         sort: [SortDescriptor(\Entry.date, order: .reverse), SortDescriptor(\Entry.createdAt, order: .reverse)])
    }

    private var dayEntries: [Entry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private var monthTotals: (expense: Double, income: Double) {
        let cal = Calendar.current
        let inMonth = entries.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        return (inMonth.filter { $0.kind == .expense }.reduce(0) { $0 + $1.baseAmount },
                inMonth.filter { $0.kind == .income }.reduce(0) { $0 + $1.baseAmount })
    }

    var body: some View {
        ThemedList {
            Section {
                VStack(spacing: 6) {
                    Text(month.monthTitle).font(.headline)
                    CalendarGrid(month: month, days: gridDays, selectedDay: $selectedDay,
                                 markedDays: Set(entries.map { Calendar.current.startOfDay(for: $0.date) }))
                    HStack {
                        Label(Money.string(monthTotals.expense), systemImage: "arrow.up.right")
                            .foregroundStyle(Color.expense)
                        Spacer()
                        Label(Money.string(monthTotals.income), systemImage: "arrow.down.left")
                            .foregroundStyle(Color.income)
                    }
                    .font(.footnote.monospacedDigit())
                    .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                if dayEntries.isEmpty {
                    Text("這天沒有紀錄").foregroundStyle(.secondary)
                }
                ForEach(dayEntries) { entry in
                    Button { editing = entry } label: { EntryRow(entry: entry) }
                        .tint(.primary)
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(entry)
                                try? context.save()
                            } label: { Label("刪除", systemImage: "trash") }
                        }
                }
            } header: {
                HStack {
                    Text(selectedDay.dayTitle)
                    Spacer()
                    let spent = dayEntries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.baseAmount }
                    if spent > 0 { Text("支出 \(Money.string(spent))").monospacedDigit() }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct CalendarGrid: View {
    let month: Date
    let days: [Date]
    @Binding var selectedDay: Date
    let markedDays: Set<Date>

    private let cal = Calendar.current

    var body: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[i]).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let selected = cal.isDate(day, inSameDayAs: selectedDay)
        let weekday = cal.component(.weekday, from: day)
        let color: Color = weekday == 1 ? .expense : weekday == 7 ? .income : .primary

        return Button { selectedDay = day } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.body.weight(cal.isDateInToday(day) ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(color.opacity(inMonth ? 1 : 0.3))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.accent, lineWidth: selected ? 2.5 : 0))
                Circle()
                    .fill(markedDays.contains(day) ? Color.income : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SearchView: View {
    @State private var text = ""
    @State private var editing: Entry?
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]

    private var results: [Entry] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.category?.name.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.budget?.name.localizedCaseInsensitiveContains(q) ?? false)
                || Money.plain($0.amount) == q
        }
    }

    var body: some View {
        List(results.prefix(300)) { entry in
            Button { editing = entry } label: { EntryRow(entry: entry, showDate: true) }
                .tint(.primary)
        }
        .overlay {
            if !text.isEmpty && results.isEmpty { ContentUnavailableView.search(text: text) }
        }
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "名稱、分類、預算或金額")
        .themedBackground()
        .navigationTitle("搜尋")
        .sheet(item: $editing) { EntryEditor(entry: $0) }
    }
}
