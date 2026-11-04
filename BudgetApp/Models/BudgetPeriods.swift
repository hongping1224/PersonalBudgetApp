import Foundation

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }

    /// The given day of the month containing `date`, clamped to the month's length (e.g. 31 → Feb 28).
    func day(_ day: Int, inMonthOf date: Date) -> Date {
        let first = startOfMonth(for: date)
        let length = range(of: .day, in: .month, for: first)!.count
        return self.date(byAdding: .day, value: min(max(day, 1), length) - 1, to: first)!
    }
}

extension Budget {
    /// Budgets that hold money others owe you (named like "Claim", 代墊 or 請款): their entries
    /// are listed regardless of period and can be marked as repaid.
    var isClaim: Bool {
        let n = name.lowercased()
        return n.contains("claim") || n.contains("代墊") || n.contains("請款")
    }

    /// The recurring period that contains `date`. End is exclusive.
    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        switch period {
        case .weekly:
            let weekday = calendar.component(.weekday, from: day)
            let back = (weekday - anchorDay + 7) % 7
            let start = calendar.date(byAdding: .day, value: -back, to: day)!
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
        case .monthly:
            var start = calendar.day(anchorDay, inMonthOf: day)
            if start > day {
                start = calendar.day(anchorDay, inMonthOf: calendar.date(byAdding: .month, value: -1, to: calendar.startOfMonth(for: day))!)
            }
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.startOfMonth(for: start))!
            return DateInterval(start: start, end: calendar.day(anchorDay, inMonthOf: nextMonth))
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customEnd, customStart)))!
            return DateInterval(start: start, end: end)
        }
    }

    /// Period shifted by `offset` periods from the one containing `date` (custom budgets never shift).
    func interval(offset: Int, from date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        var current = interval(containing: date, calendar: calendar)
        guard period != .custom, offset != 0 else { return current }
        for _ in 0..<abs(offset) {
            let probe = offset > 0 ? current.end : calendar.date(byAdding: .day, value: -1, to: current.start)!
            current = interval(containing: probe, calendar: calendar)
        }
        return current
    }

    func entries(in interval: DateInterval) -> [Entry] {
        (entries ?? []).filter { $0.date >= interval.start && $0.date < interval.end }
    }

    /// Expenses minus refunds/income tagged to this budget within the period.
    func spent(in interval: DateInterval) -> Double {
        entries(in: interval).reduce(0) { $0 - $1.signedAmount }
    }

    /// Net amount transferred in (+) or out (−) of this budget during the period.
    func transferred(in interval: DateInterval) -> Double {
        (adjustments ?? []).filter { $0.date >= interval.start && $0.date < interval.end }.reduce(0) { $0 + $1.amount }
    }

    /// Leftover rolled in from the periods between `carryOverStart` and `interval`.
    func carryIn(to interval: DateInterval) -> Double {
        guard carriesOver, period != .custom, let amount, let start = carryOverStart else { return 0 }
        var current = self.interval(containing: start)
        var total = 0.0
        var steps = 0
        while current.start < interval.start && steps < 600 {
            total += amount + transferred(in: current) - spent(in: current)
            if !carryOverspend { total = max(total, 0) }
            current = self.interval(containing: current.end)
            steps += 1
        }
        return total
    }

    /// This period's amount plus transfers and anything carried over.
    func available(in interval: DateInterval) -> Double? {
        amount.map { $0 + transferred(in: interval) + carryIn(to: interval) }
    }

    var currentInterval: DateInterval { interval(containing: .now) }
    var currentSpent: Double { spent(in: currentInterval) }
    var remaining: Double? { available(in: currentInterval).map { $0 - currentSpent } }

    var periodDescription: String {
        switch period {
        case .weekly:
            let symbols = Calendar.current.shortWeekdaySymbols
            return "每週，從\(symbols[(anchorDay - 1 + 7) % 7])開始"
        case .monthly: return "每月 \(anchorDay) 號開始"
        case .custom: return "自訂期間"
        }
    }
}

extension DateInterval {
    /// 0...1 progress of now through the interval.
    var elapsedFraction: Double {
        let now = Date.now
        if now <= start { return 0 }
        if now >= end { return 1 }
        return now.timeIntervalSince(start) / duration
    }

    /// Inclusive display, e.g. "26/10/14 – 26/11/13".
    var shortLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yy/MM/dd"
        let last = Calendar.current.date(byAdding: .day, value: -1, to: end)!
        return "\(f.string(from: start)) – \(f.string(from: last))"
    }
}
