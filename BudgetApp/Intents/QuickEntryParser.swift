import Foundation

/// Turns a dictated sentence like "午餐 120 用信用卡" into an entry.
struct QuickEntryParser {
    struct Result: Equatable {
        var amount: Double?
        var categoryName: String?
        var accountName: String?
        var budgetName: String? = nil
        var name: String
    }

    let categoryNames: [String]
    let accountNames: [String]
    var budgetNames: [String] = []

    private static let fillers = ["花了", "用了", "付了", "記一筆", "記帳", "元", "塊錢", "塊", "用", "在", "的", "刷", "$", "NT"]

    func parse(_ text: String) -> Result {
        var rest = Self.normalizeDigits(text)

        var amount: Double?
        if let range = rest.range(of: #"[0-9][0-9,]*(\.[0-9]+)?"#, options: .regularExpression) {
            amount = Double(rest[range].replacingOccurrences(of: ",", with: ""))
            rest.removeSubrange(range)
        }

        // Longest names first so "高鐵" wins over "鐵", "甲銀行 卡" over "甲銀行".
        let account = accountNames.sorted { $0.count > $1.count }
            .first { rest.localizedCaseInsensitiveContains($0) }
        if let account, let r = rest.range(of: account, options: .caseInsensitive) { rest.removeSubrange(r) }

        let budget = budgetNames.sorted { $0.count > $1.count }
            .first { rest.localizedCaseInsensitiveContains($0) }
        // A budget named like a category (e.g. both "午餐") must stay in the text for the category match.
        if let budget, !categoryNames.contains(budget), let r = rest.range(of: budget, options: .caseInsensitive) {
            rest.removeSubrange(r)
        }

        let category = categoryNames.sorted { $0.count > $1.count }
            .first { rest.localizedCaseInsensitiveContains($0) }

        var name = rest
        for filler in Self.fillers { name = name.replacingOccurrences(of: filler, with: " ") }
        name = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if name == category { name = "" }

        return Result(amount: amount, categoryName: category, accountName: account, budgetName: budget, name: name)
    }

    /// Full-width digits from dictation → ASCII, and simple Chinese numbers like 一百二十 → 120.
    static func normalizeDigits(_ text: String) -> String {
        var s = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        if s.range(of: #"[0-9]"#, options: .regularExpression) == nil, let (range, value) = chineseNumber(in: s) {
            s.replaceSubrange(range, with: String(value))
        }
        return s
    }

    private static let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4,
                                                   "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
    private static let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "萬": 10000]

    private static func chineseNumber(in s: String) -> (Range<String.Index>, Int)? {
        guard let start = s.firstIndex(where: { digits[$0] != nil || units[$0] != nil }) else { return nil }
        var end = start
        while end < s.endIndex, digits[s[end]] != nil || units[s[end]] != nil { end = s.index(after: end) }
        let chars = Array(s[start..<end])

        var total = 0, section = 0, current = 0
        var lastUnit = 1
        for c in chars {
            if let d = digits[c] {
                current = d
            } else if let u = units[c] {
                if u == 10000 {
                    total += (section + current) * u
                    section = 0
                } else {
                    section += (current == 0 && u == 10 ? 1 : current) * u
                }
                current = 0
                lastUnit = u
            }
        }
        // "一百二" means 120: a trailing digit takes one unit below the last unit.
        if current > 0, lastUnit >= 100, chars.count >= 2, units[chars[chars.count - 2]] != nil {
            current *= lastUnit / 10
        }
        let value = total + section + current
        return value > 0 ? (start..<end, value) : nil
    }
}
