import Foundation

/// Currencies an account or entry can be in. Totals (budgets, stats, net worth, widget) are in TWD,
/// converted with rates set in 設定 → 匯率.
struct CurrencyInfo: Identifiable, Equatable {
    var code: String
    var name: String
    var symbol: String
    /// Decimal places normally used.
    var digits: Int
    var id: String { code }
}

enum Currency {
    static let base = "TWD"

    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "TWD", name: "新台幣", symbol: "$", digits: 0),
        CurrencyInfo(code: "JPY", name: "日圓", symbol: "¥", digits: 0),
        CurrencyInfo(code: "USD", name: "美元", symbol: "US$", digits: 2),
        CurrencyInfo(code: "EUR", name: "歐元", symbol: "€", digits: 2),
        CurrencyInfo(code: "KRW", name: "韓元", symbol: "₩", digits: 0),
        CurrencyInfo(code: "CNY", name: "人民幣", symbol: "CN¥", digits: 2),
        CurrencyInfo(code: "HKD", name: "港幣", symbol: "HK$", digits: 2),
        CurrencyInfo(code: "GBP", name: "英鎊", symbol: "£", digits: 2),
        CurrencyInfo(code: "THB", name: "泰銖", symbol: "฿", digits: 2),
        CurrencyInfo(code: "SGD", name: "新加坡幣", symbol: "S$", digits: 2),
        CurrencyInfo(code: "AUD", name: "澳幣", symbol: "A$", digits: 2),
        CurrencyInfo(code: "MYR", name: "馬來西亞令吉", symbol: "RM", digits: 2),
        CurrencyInfo(code: "VND", name: "越南盾", symbol: "₫", digits: 0),
    ]

    static func info(_ code: String) -> CurrencyInfo {
        all.first { $0.code == code } ?? CurrencyInfo(code: code, name: code, symbol: code + " ", digits: 2)
    }

    /// Rough TWD rates to start from; meant to be updated in 設定 → 匯率.
    static let defaultRates: [String: Double] = [
        "TWD": 1, "JPY": 0.21, "USD": 31, "EUR": 35.5, "KRW": 0.022, "CNY": 4.35, "HKD": 4,
        "GBP": 41.5, "THB": 0.95, "SGD": 23.8, "AUD": 20.5, "MYR": 7.2, "VND": 0.0012,
    ]

    static let ratesKey = "currencyRates"
    private static var store: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroup) ?? .standard }

    /// TWD for one unit of `code`.
    static func rate(_ code: String) -> Double {
        if code == base { return 1 }
        let saved = store.dictionary(forKey: ratesKey) as? [String: Double]
        return saved?[code] ?? defaultRates[code] ?? 1
    }

    static func setRate(_ value: Double, for code: String) {
        guard code != base, value > 0 else { return }
        var saved = store.dictionary(forKey: ratesKey) as? [String: Double] ?? [:]
        saved[code] = value
        store.set(saved, forKey: ratesKey)
    }

    /// `amount` of `from` in `to`, rounded to `to`'s usual decimals.
    static func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }
        return round(amount * rate(from) / rate(to), digits: info(to).digits)
    }

    static func round(_ value: Double, digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        return (value * scale).rounded() / scale
    }
}
