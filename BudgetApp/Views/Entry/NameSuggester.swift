import Foundation

/// A name used before, with how often and what its latest entry was filed under.
struct NameSuggestion: Hashable {
    let name: String
    let count: Int
    let lastUsed: Date
    let categoryID: UUID?
    let accountID: UUID?
    let budgetID: UUID?
    let kind: EntryKind
}

/// Recent, similar and time-of-day entry names for the editor's name field.
enum NameSuggester {
    /// One suggestion per (name, kind), carrying the category, account and budget of its latest use.
    static func build(from entries: [Entry]) -> [NameSuggestion] {
        var byKey: [String: (count: Int, last: Entry)] = [:]
        for e in entries where !e.name.isEmpty {
            let key = key(e.name, e.kind)
            if let existing = byKey[key] {
                byKey[key] = (existing.count + 1, e.date > existing.last.date ? e : existing.last)
            } else {
                byKey[key] = (1, e)
            }
        }
        return byKey.values.map {
            NameSuggestion(name: $0.last.name, count: $0.count, lastUsed: $0.last.date,
                           categoryID: $0.last.category?.id, accountID: $0.last.account?.id,
                           budgetID: $0.last.budget?.id, kind: $0.last.kind)
        }
    }

    private static func key(_ name: String, _ kind: EntryKind) -> String { "\(kind.rawValue)|\(name)" }

    /// With a query: similar names. Without: the category's recent names (or all recent names).
    static func suggest(_ query: String, in items: [NameSuggestion], kind: EntryKind,
                        categoryID: UUID?, limit: Int = 8) -> [NameSuggestion] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let pool = items.filter { $0.kind == kind && $0.name != q }

        if q.isEmpty {
            return pool
                .filter { categoryID == nil || $0.categoryID == categoryID }
                .sorted { $0.lastUsed > $1.lastUsed }
                .prefix(limit).map { $0 }
        }

        return pool
            .compactMap { s -> (NameSuggestion, Int)? in
                let score = score(s.name, query: q)
                return score > 0 ? (s, score) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.count != b.0.count { return a.0.count > b.0.count }
                return a.0.lastUsed > b.0.lastUsed
            }
            .prefix(limit).map(\.0)
    }

    /// Names from the previous `days` days (not today) whose time of day was within `window`
    /// minutes of `now`, closest first — e.g. lunch places around noon.
    static func aroundTime(_ now: Date, entries: [Entry], items: [NameSuggestion], kind: EntryKind,
                           days: Int = 14, window: Int = 90, limit: Int = 8,
                           calendar: Calendar = .current) -> [NameSuggestion] {
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -days, to: today)!
        let nowMinute = minuteOfDay(now, calendar)
        var best: [String: Int] = [:] // key → closest distance in minutes
        for e in entries where !e.name.isEmpty && e.kind == kind && e.date >= since && e.date < today {
            let d = abs(minuteOfDay(e.date, calendar) - nowMinute)
            let distance = min(d, 1440 - d)
            guard distance <= window else { continue }
            let k = key(e.name, e.kind)
            best[k] = min(best[k] ?? .max, distance)
        }
        let byKey = Dictionary(items.map { (key($0.name, $0.kind), $0) }, uniquingKeysWith: { a, _ in a })
        return best
            .compactMap { k, distance in byKey[k].map { ($0, distance) } }
            .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.count > b.0.count }
            .prefix(limit).map(\.0)
    }

    private static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 3 = starts with, 2 = contains, 1 = query's characters appear in order, 0 = no match.
    static func score(_ name: String, query: String) -> Int {
        let n = name.lowercased(), q = query.lowercased()
        if n.hasPrefix(q) { return 3 }
        if n.contains(q) { return 2 }
        var rest = Substring(n)
        for ch in q where !ch.isWhitespace {
            guard let i = rest.firstIndex(of: ch) else { return 0 }
            rest = rest[rest.index(after: i)...]
        }
        return 1
    }
}
