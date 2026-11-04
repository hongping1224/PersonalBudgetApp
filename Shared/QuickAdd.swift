import Foundation

/// What the widget shows, written by the app into the shared App Group
/// (the widget can't open the app's database).
struct WidgetSnapshot: Codable, Equatable {
    struct Category: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var symbol: String
        var colorHex: String
    }

    var categories: [Category] = []
    var todaySpent: Double = 0
    var monthSpent: Double = 0
    /// Day the totals belong to; after midnight the widget shows 0 until the app updates them.
    var day: Date = .distantPast

    static let appGroup = "group.com.hongping.budgetapp"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    func todaySpent(on date: Date) -> Double {
        Calendar.current.isDate(day, inSameDayAs: date) ? todaySpent : 0
    }

    func monthSpent(on date: Date) -> Double {
        Calendar.current.isDate(day, equalTo: date, toGranularity: .month) ? monthSpent : 0
    }
}

/// budgetapp://add?kind=expense&category=<id or name> — opens the entry editor.
struct QuickAddLink: Equatable {
    var kind: String = "expense"
    var category: String?

    static let scheme = "budgetapp"

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "add"
        c.queryItems = [URLQueryItem(name: "kind", value: kind)]
            + (category.map { [URLQueryItem(name: "category", value: $0)] } ?? [])
        return c.url!
    }

    init(kind: String = "expense", category: String? = nil) {
        self.kind = kind
        self.category = category
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "add" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        kind = items.first { $0.name == "kind" }?.value ?? "expense"
        category = items.first { $0.name == "category" }?.value
    }
}
