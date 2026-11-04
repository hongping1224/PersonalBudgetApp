import Foundation
import SwiftData

/// Which days a budget rule applies to.
enum RuleDays: String, CaseIterable, Identifiable, Codable {
    case weekdays, weekends, everyday
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekdays: "平日"
        case .weekends: "週末"
        case .everyday: "每天"
        }
    }

    func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .weekdays: !calendar.isDateInWeekend(date)
        case .weekends: calendar.isDateInWeekend(date)
        case .everyday: true
        }
    }
}

/// "食物 on weekdays 07:00–16:00 → lunch": picks a new entry's budget before the learned suggestion.
/// Refers to its category and budget by ID so deleting either just makes the rule inactive.
@Model
final class BudgetRule {
    var id: UUID = UUID()
    /// nil = any category.
    var categoryID: UUID?
    var budgetID: UUID = UUID()
    var daysRaw: String = RuleDays.everyday.rawValue
    /// Minutes after midnight, both ends included.
    var startMinute: Int = 0
    var endMinute: Int = 23 * 60 + 59
    var sortOrder: Int = 0

    init(categoryID: UUID?, budgetID: UUID, days: RuleDays, startMinute: Int = 0,
         endMinute: Int = 23 * 60 + 59, sortOrder: Int = 0) {
        self.categoryID = categoryID
        self.budgetID = budgetID
        self.daysRaw = days.rawValue
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.sortOrder = sortOrder
    }

    var days: RuleDays {
        get { RuleDays(rawValue: daysRaw) ?? .everyday }
        set { daysRaw = newValue.rawValue }
    }

    var isAllDay: Bool { startMinute == 0 && endMinute >= 23 * 60 + 59 }

    func matches(category: EntryCategory?, date: Date, calendar: Calendar = .current) -> Bool {
        if let categoryID, categoryID != category?.id { return false }
        guard days.matches(date, calendar: calendar) else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        // A range like 22:00–02:00 wraps past midnight.
        return startMinute <= endMinute
            ? (startMinute...endMinute).contains(minute)
            : minute >= startMinute || minute <= endMinute
    }

    static func timeText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

extension Array where Element == BudgetRule {
    /// The first rule (in list order) that matches and still points at an active budget.
    func budget(for category: EntryCategory?, at date: Date, budgets: [Budget]) -> Budget? {
        for rule in sorted(by: { $0.sortOrder < $1.sortOrder }) where rule.matches(category: category, date: date) {
            if let b = budgets.first(where: { $0.id == rule.budgetID && !$0.isArchived }) { return b }
        }
        return nil
    }
}
