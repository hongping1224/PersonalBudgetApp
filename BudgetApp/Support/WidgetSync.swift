import Foundation
import SwiftData
import WidgetKit

/// Copies what the quick-add widget shows into the App Group and refreshes it when it changed.
@MainActor
enum WidgetSync {
    static func snapshot(_ context: ModelContext, now: Date = .now) -> WidgetSnapshot {
        let calendar = Calendar.current
        let categories = ((try? context.fetch(FetchDescriptor<EntryCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { $0.kind == .expense }
            .map { WidgetSnapshot.Category(id: $0.id, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex) }

        let monthStart = calendar.startOfMonth(for: now)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let expense = EntryKind.expense.rawValue
        let month = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate {
            $0.kindRaw == expense && $0.date >= monthStart && $0.date < monthEnd
        }))) ?? []
        let today = month.filter { $0.date >= dayStart && $0.date < dayEnd }

        return WidgetSnapshot(categories: categories,
                              todaySpent: today.reduce(0) { $0 + $1.baseAmount },
                              monthSpent: month.reduce(0) { $0 + $1.baseAmount },
                              day: dayStart)
    }

    static func publish(_ context: ModelContext) {
        let current = snapshot(context)
        guard current != WidgetSnapshot.load() else { return }
        current.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
