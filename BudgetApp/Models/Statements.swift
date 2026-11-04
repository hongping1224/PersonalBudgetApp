import Foundation

/// Credit card statements: each one runs from the day after the previous closing day (出帳日)
/// through the closing day. End is exclusive (the day after closing).
extension Account {
    /// The statement that contains `date`, or nil when no closing day is set.
    func statementInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let statementDay else { return nil }
        let day = calendar.startOfDay(for: date)
        var closing = calendar.day(statementDay, inMonthOf: day)
        if closing < day {
            closing = calendar.day(statementDay, inMonthOf: calendar.date(byAdding: .month, value: 1, to: calendar.startOfMonth(for: day))!)
        }
        let previous = calendar.day(statementDay, inMonthOf: calendar.date(byAdding: .month, value: -1, to: calendar.startOfMonth(for: closing))!)
        return DateInterval(start: calendar.date(byAdding: .day, value: 1, to: previous)!,
                            end: calendar.date(byAdding: .day, value: 1, to: closing)!)
    }

    /// The statement `offset` bills after (negative: before) `interval`.
    func statementInterval(offset: Int, from interval: DateInterval, calendar: Calendar = .current) -> DateInterval? {
        guard let statementDay else { return nil }
        let month = calendar.date(byAdding: .month, value: offset, to: calendar.startOfMonth(for: interval.closingDate))!
        return statementInterval(containing: calendar.day(statementDay, inMonthOf: month), calendar: calendar)
    }

    /// The statement an entry is billed in: the one containing its date, moved later by its offset.
    func billedStatement(for entry: Entry, calendar: Calendar = .current) -> DateInterval? {
        guard let base = statementInterval(containing: entry.date, calendar: calendar) else { return nil }
        return entry.statementOffset == 0 ? base : statementInterval(offset: entry.statementOffset, from: base, calendar: calendar)
    }

    /// Charges and refunds billed in this statement, including ones moved here from earlier ones.
    func statementEntries(in interval: DateInterval) -> [Entry] {
        (entries ?? []).filter { e in
            guard e.date < interval.end else { return false }
            if e.statementOffset == 0 { return e.date >= interval.start }
            return billedStatement(for: e) == interval
        }
        .sorted { $0.date > $1.date }
    }

    /// Payments into the card made during this statement's dates.
    func statementPayments(in interval: DateInterval) -> [Entry] {
        (incomingTransfers ?? []).filter { interval.contains($0.date) && $0.date != interval.end }
            .sorted { $0.date > $1.date }
    }

    /// Amount billed: charges (and transfers out, like cash advances) minus refunds.
    func statementTotal(in interval: DateInterval) -> Double {
        statementEntries(in: interval).reduce(0) { $0 + ($1.kind == .income ? -$1.amount : $1.amount) }
    }

    /// Payment due date for a statement: the first due day after it closes.
    func dueDate(for interval: DateInterval, calendar: Calendar = .current) -> Date? {
        guard let paymentDueDay else { return nil }
        let thisMonth = calendar.day(paymentDueDay, inMonthOf: interval.end)
        if thisMonth >= interval.end { return thisMonth }
        return calendar.day(paymentDueDay, inMonthOf: calendar.date(byAdding: .month, value: 1, to: calendar.startOfMonth(for: interval.end))!)
    }

    /// The statement to show first: the one that just closed (within a week), otherwise the open one.
    func defaultStatement(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        guard let current = statementInterval(containing: now, calendar: calendar),
              let previous = statementInterval(offset: -1, from: current, calendar: calendar) else { return nil }
        let daysSinceClosing = calendar.dateComponents([.day], from: previous.closingDate, to: calendar.startOfDay(for: now)).day ?? 99
        return daysSinceClosing <= 7 ? previous : current
    }
}

extension DateInterval {
    /// Last day of a statement.
    var closingDate: Date { Calendar.current.date(byAdding: .day, value: -1, to: end)! }
}
