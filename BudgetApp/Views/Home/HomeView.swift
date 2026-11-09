import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var editing: Entry?
    /// The month page the calendar's paging scroll view is on.
    @State private var visibleMonth: Date? = Calendar.current.startOfMonth(for: .now)

    var body: some View {
        NavigationStack {
            MonthContent(month: month, selectedDay: $selectedDay, editing: $editing, visibleMonth: $visibleMonth)
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
                .sheet(item: $editing) { EntryEditor(entry: $0) }
                .onChange(of: selectedDay, initial: true) { _, day in
                    AppRouter.shared.preferredDate = day
                }
                // Swiped (or scrolled by the buttons) to another month.
                .onChange(of: visibleMonth) { _, newMonth in
                    guard let newMonth, newMonth != month else { return }
                    let cal = Calendar.current
                    month = newMonth
                    // Keep the same day number when possible, unless a day in it is already chosen.
                    if !cal.isDate(selectedDay, equalTo: newMonth, toGranularity: .month) {
                        selectedDay = cal.day(cal.component(.day, from: selectedDay), inMonthOf: newMonth)
                    }
                }
        }
    }

    private func shiftMonth(_ delta: Int) {
        let target = Calendar.current.date(byAdding: .month, value: delta, to: month)!
        withAnimation { visibleMonth = target }
    }

    private func jump(to date: Date) {
        let cal = Calendar.current
        selectedDay = cal.startOfDay(for: date)
        let target = cal.startOfMonth(for: date)
        if target == month { return }
        let months = abs(cal.dateComponents([.month], from: month, to: target).month ?? 0)
        if months == 1 {
            withAnimation { visibleMonth = target }
        } else {
            visibleMonth = target
        }
    }
}

/// Everything that depends on the chosen month, so the query can be scoped to it.
private struct MonthContent: View {
    let month: Date
    @Binding var selectedDay: Date
    @Binding var editing: Entry?
    @Binding var visibleMonth: Date?

    /// Side margin of the cards; neighbouring months show a double gap while paging.
    static let margin: CGFloat = 16
    /// Months reachable by swiping.
    static let months: [Date] = {
        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        return (0..<(12 * 51)).map { cal.date(byAdding: .month, value: $0, to: first)! }
    }()

    @Environment(\.modelContext) private var context
    @Query private var entries: [Entry]
    @Query private var checks: [BalanceCheck]
    @Query private var accounts: [Account]
    /// +1 when the day just moved forward, so the records slide in from the right.
    @State private var dayDirection = 1
    /// A sideways swipe over the records is under way (or just ended): lifting the finger on a
    /// record then isn't a tap that opens it.
    @State private var swipingDay = false

    init(month: Date, selectedDay: Binding<Date>, editing: Binding<Entry?>, visibleMonth: Binding<Date?>) {
        self.month = month
        _selectedDay = selectedDay
        _editing = editing
        _visibleMonth = visibleMonth
        let cal = Calendar.current
        let start = cal.startOfMonth(for: month)
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        _entries = Query(filter: #Predicate<Entry> { $0.date >= start && $0.date < end },
                         sort: [SortDescriptor(\Entry.date, order: .reverse), SortDescriptor(\Entry.createdAt, order: .reverse)])
        _checks = Query(filter: #Predicate<BalanceCheck> { $0.date >= start && $0.date < end },
                        sort: \BalanceCheck.date, order: .reverse)
    }

    private var dayChecks: [BalanceCheck] {
        checks.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private var dayEntries: [Entry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }

    // The months are pages of a paging scroll view: it follows the finger, slides to the screen
    // edge and settles on a whole month by itself. (A hand-made sliding strip drew stale numbers
    // on the card coming in.)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Self.months, id: \.self) { m in
                            MonthPanel(month: m, selectedDay: $selectedDay,
                                       highlighted: m == month ? selectedDay
                                        : Calendar.current.day(Calendar.current.component(.day, from: selectedDay), inMonthOf: m))
                                .padding(.horizontal, Self.margin)
                                .containerRelativeFrame(.horizontal)
                                // Each page draws only within itself.
                                .compositingGroup()
                                .clipped()
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleMonth)
                .scrollIndicators(.hidden)
                // The initial position isn't applied on first layout; scroll there once laid out.
                .onAppear {
                    let target = visibleMonth ?? month
                    visibleMonth = nil
                    DispatchQueue.main.async { visibleMonth = target }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Swipe left or right over the day's records for the next or previous day.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selectedDay.dayTitle)
                        Spacer()
                        let spent = dayEntries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.baseAmount }
                        if spent > 0 { Text("支出 \(Money.string(spent))").monospacedDigit() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                    dayCard
                        .id(selectedDay)
                        .transition(.asymmetric(
                            insertion: .move(edge: dayDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                            removal: .opacity))
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .top)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            if abs(value.translation.width) > abs(value.translation.height) { swipingDay = true }
                        }
                        .onEnded { value in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { swipingDay = false }
                            let w = value.translation.width
                            guard abs(w) > 60, abs(w) > abs(value.translation.height) * 1.5 else { return }
                            shiftDay(w < 0 ? 1 : -1)
                        }
                )
                .clipped()
            }
        }
    }

    /// Moves to the next or previous day, paging the calendar when it's in another month.
    private func shiftDay(_ delta: Int) {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: delta, to: selectedDay) else { return }
        dayDirection = delta
        withAnimation(.easeOut(duration: 0.22)) { selectedDay = day }
        let dayMonth = cal.startOfMonth(for: day)
        if dayMonth != month { withAnimation { visibleMonth = dayMonth } }
    }

    /// The selected day's records; long-press one to delete it.
    private var dayCard: some View {
        VStack(spacing: 0) {
            // 對帳打卡 made this day (a personal note, not a record).
            ForEach(dayChecks) { check in
                let account = accounts.first { $0.id == check.accountID }
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(BalanceCheck.color)
                    Text("\(account?.fullName ?? "帳戶") 對帳 \(check.date.formatted(.dateTime.hour().minute()))")
                    Spacer()
                    Text(Money.string(check.balance, currency: account?.currency ?? Currency.base)).monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(BalanceCheck.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("day-check-in")
                Divider().padding(.leading, 16)
            }
            if dayEntries.isEmpty {
                Text("這天沒有紀錄")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            ForEach(Array(dayEntries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().padding(.leading, 68) }
                Button { if !swipingDay { editing = entry } } label: {
                    EntryRow(entry: entry)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-entry")
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(entry)
                        try? context.save()
                    } label: { Label("刪除", systemImage: "trash") }
                }
            }
        }
        .background(Color.themeSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// One month's card: its grid with record dots, and the month's totals.
private struct MonthPanel: View {
    let month: Date
    @Binding var selectedDay: Date
    /// The day drawn as selected (a neighbouring month shows the day it will select).
    let highlighted: Date

    @Query private var entries: [Entry]
    @Query private var checks: [BalanceCheck]
    private let days: [Date]

    init(month: Date, selectedDay: Binding<Date>, highlighted: Date) {
        self.month = month
        _selectedDay = selectedDay
        self.highlighted = highlighted
        days = Self.gridDays(for: month)
        let start = days[0]
        let end = days[41].addingTimeInterval(86_400)
        _entries = Query(filter: #Predicate<Entry> { $0.date >= start && $0.date < end })
        _checks = Query(filter: #Predicate<BalanceCheck> { $0.date >= start && $0.date < end })
    }

    /// The 6-week grid shown for `month`, starting on Sunday.
    static func gridDays(for month: Date) -> [Date] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: month)
        let start = cal.date(byAdding: .day, value: -(weekday - 1), to: month)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    var body: some View {
        let cal = Calendar.current
        let inMonth = entries.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        let expense = inMonth.filter { $0.kind == .expense }.reduce(0) { $0 + $1.baseAmount }
        let income = inMonth.filter { $0.kind == .income }.reduce(0) { $0 + $1.baseAmount }
        VStack(spacing: 6) {
            Text(month.monthTitle).font(.headline)
            CalendarGrid(month: month, days: days, selectedDay: $selectedDay, highlighted: highlighted,
                         markedDays: Set(entries.map { cal.startOfDay(for: $0.date) }),
                         checkedDays: Set(checks.map { cal.startOfDay(for: $0.date) }))
            HStack {
                Label(Money.string(expense), systemImage: "arrow.up.right")
                    .foregroundStyle(Color.expense)
                Spacer()
                Label(Money.string(income), systemImage: "arrow.down.left")
                    .foregroundStyle(Color.income)
            }
            .font(.footnote.monospacedDigit())
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Color.themeSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct CalendarGrid: View {
    let month: Date
    let days: [Date]
    @Binding var selectedDay: Date
    /// The day drawn as selected.
    let highlighted: Date
    let markedDays: Set<Date>
    /// Days with a 對帳打卡, drawn with a filled circle in the check-in color.
    var checkedDays: Set<Date> = []

    private let cal = Calendar.current

    var body: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        // A fixed 6 × 7 grid keyed by position.
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[i]).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { weekday in dayCell(days[week * 7 + weekday]) }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let selected = cal.isDate(day, inSameDayAs: highlighted)
        let weekday = cal.component(.weekday, from: day)
        let color: Color = weekday == 1 ? .expense : weekday == 7 ? .income : .primary

        return Button { selectedDay = day } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.body.weight(cal.isDateInToday(day) ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(color.opacity(inMonth ? 1 : 0.3))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(BalanceCheck.color.opacity(checkedDays.contains(day) ? 0.3 : 0)))
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
