import SwiftUI

enum Money {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    static func string(_ value: Double, signed: Bool = false, currency: String = Currency.base) -> String {
        let digits = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        let symbol = Currency.info(currency).symbol
        if value < 0 { return "-" + symbol + digits }
        return (signed && value > 0 ? "+" : "") + symbol + digits
    }

    /// Plain number for the calculator, e.g. 120 or 12.5.
    static func plain(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x8A9099
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    // Follow the chosen themes (設定 → 主題顏色): the light theme in light mode, the dark one in dark mode.
    static var expense: Color { themed(\.expense) }
    static var income: Color { themed(\.income) }
    static var accent: Color { themed(\.accent) }
    /// Page background behind lists and cards.
    static var themeBackground: Color { themed(\.background) }
    /// Cards and list rows.
    static var themeSurface: Color { themed(\.surface) }
    /// Chips, text fields and keypad keys.
    static var themeFill: Color { themed(\.fill) }

    private static func themed(_ color: KeyPath<AppTheme, String>) -> Color {
        let light = UIColor(Color(hex: AppTheme.light[keyPath: color]))
        let dark = UIColor(Color(hex: AppTheme.dark[keyPath: color]))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension View {
    /// The theme's page background and card color instead of the system white/black
    /// (lists and forms included).
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.themeBackground.ignoresSafeArea())
    }
}

/// A color theme. Light themes are used in light mode, dark themes in dark mode.
struct AppTheme: Identifiable, Equatable {
    var id: String
    var name: String
    var isDark: Bool
    /// Buttons, selection, keypad ✓.
    var accent: String
    var expense: String
    var income: String
    var background: String
    var surface: String
    var fill: String

    private static func light(_ id: String, _ name: String, accent: String, expense: String, income: String,
                              background: String, surface: String, fill: String) -> AppTheme {
        AppTheme(id: id, name: name, isDark: false, accent: accent, expense: expense, income: income,
                 background: background, surface: surface, fill: fill)
    }

    private static func dark(_ id: String, _ name: String, accent: String, expense: String, income: String,
                             background: String, surface: String, fill: String) -> AppTheme {
        AppTheme(id: id, name: name, isDark: true, accent: accent, expense: expense, income: income,
                 background: background, surface: surface, fill: fill)
    }

    static let lightThemes: [AppTheme] = [
        light("sky", "天空", accent: "#3AA6D0", expense: "#E5605C", income: "#5DB04A",
              background: "#EAF3F8", surface: "#F8FCFE", fill: "#DCEAF2"),
        light("mint", "薄荷", accent: "#24A88F", expense: "#E86A5F", income: "#3FA66B",
              background: "#E7F4EF", surface: "#F7FCFA", fill: "#D5ECE4"),
        light("lavender", "薰衣草", accent: "#8569D6", expense: "#E0607E", income: "#4FA885",
              background: "#EFECF9", surface: "#FAF8FE", fill: "#E1DBF3"),
        light("orange", "橘子", accent: "#EE8424", expense: "#D9534F", income: "#5FA84A",
              background: "#FAEFE2", surface: "#FFF9F2", fill: "#F1E1CC"),
        light("berry", "莓果", accent: "#D6457A", expense: "#C9423F", income: "#4E9F74",
              background: "#FAEBF0", surface: "#FFF8FA", fill: "#F2DAE3"),
        light("graphite", "石墨", accent: "#5A6270", expense: "#C8553D", income: "#4E8F5A",
              background: "#ECEDEF", surface: "#F9F9FA", fill: "#DFE1E5"),
        // Cream, honey and woodland green.
        light("cream-forest", "奶油森林", accent: "#D9932B", expense: "#CC5A45", income: "#6A9A4A",
              background: "#F7EFD9", surface: "#FFF9EA", fill: "#EEE1C0"),
        light("khaki", "卡其", accent: "#8C7A4F", expense: "#C0573F", income: "#5F8A4A",
              background: "#EDE6D3", surface: "#F8F4EA", fill: "#E0D6BD"),
        // Taiwan stock style: income red, expense green.
        light("stock", "台股紅綠", accent: "#D94A3D", expense: "#2E9E5B", income: "#E0473A",
              background: "#F6EEEC", surface: "#FDF8F7", fill: "#EBDDDA"),
    ]

    static let darkThemes: [AppTheme] = [
        dark("night", "夜空", accent: "#5BB8E8", expense: "#FF7A70", income: "#7FD46B",
             background: "#0E1620", surface: "#18232F", fill: "#243242"),
        dark("forest", "深林", accent: "#3CC4A5", expense: "#FF7F73", income: "#6FD08F",
             background: "#0C1714", surface: "#16241F", fill: "#22352E"),
        dark("midnight", "午夜紫", accent: "#A58CF0", expense: "#FF7C99", income: "#74D3A8",
             background: "#14111E", surface: "#1F1B2D", fill: "#2C273F"),
        dark("espresso", "咖啡", accent: "#E0A15A", expense: "#F07C6C", income: "#8CC97A",
             background: "#19130E", surface: "#251D16", fill: "#352A20"),
        dark("wine", "酒紅", accent: "#E86A93", expense: "#FF7B76", income: "#73C994",
             background: "#1B0F14", surface: "#28171E", fill: "#38212B"),
        dark("charcoal", "石墨黑", accent: "#9AA4B5", expense: "#F07B66", income: "#7CC98A",
             background: "#121315", surface: "#1D1F22", fill: "#2B2E33"),
        dark("cream-forest-dark", "蜂蜜森林", accent: "#F0B54A", expense: "#F0806A", income: "#8CC46A",
             background: "#17150E", surface: "#232017", fill: "#343020"),
        dark("khaki-dark", "卡其", accent: "#C8B47F", expense: "#EE8268", income: "#93C27A",
             background: "#1A1813", surface: "#26231C", fill: "#363228"),
        dark("stock-dark", "台股紅綠", accent: "#FF6B5E", expense: "#4CC47F", income: "#FF6B5E",
             background: "#161112", surface: "#221A1B", fill: "#312728"),
    ]

    static var all: [AppTheme] { lightThemes + darkThemes }

    /// Stored in the App Group so the widget uses the same colors.
    static let store = UserDefaults(suiteName: "group.com.hongping.budgetapp") ?? .standard
    static let lightKey = "lightTheme"
    static let darkKey = "darkTheme"
    static let appearanceKey = "appearance"

    // Reading the revision makes every view that draws with a theme color redraw when the theme changes.
    static var light: AppTheme {
        _ = ThemeChanges.shared.revision
        return lightNamed(store.string(forKey: lightKey) ?? store.string(forKey: "colorTheme"))
    }
    static var dark: AppTheme {
        _ = ThemeChanges.shared.revision
        return darkNamed(store.string(forKey: darkKey))
    }
    static func lightNamed(_ id: String?) -> AppTheme { lightThemes.first { $0.id == id } ?? lightThemes[0] }
    static func darkNamed(_ id: String?) -> AppTheme { darkThemes.first { $0.id == id } ?? darkThemes[0] }
}

/// Bumped when the chosen themes change, so open screens update in place (and keep their navigation).
@Observable
final class ThemeChanges {
    static let shared = ThemeChanges()
    var revision = 0
}

extension AppTheme {
    /// The theme in effect when the phone is in `scheme`, after the 淺色／深色 setting.
    /// Widgets use it to pick colors explicitly instead of relying on trait-based colors.
    static func current(for scheme: ColorScheme) -> AppTheme {
        switch AppAppearance(rawValue: store.string(forKey: appearanceKey) ?? "") ?? .system {
        case .light: light
        case .dark: dark
        case .system: scheme == .dark ? dark : light
        }
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

/// Light / dark choice; "system" follows the phone.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟隨系統"
        case .light: "淺色"
        case .dark: "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Palette {
    static let colors = ["#E9C98F", "#B8955A", "#D9706F", "#4A90E2", "#6C5FA7", "#A8A69A",
                         "#7CB86A", "#3BB4C1", "#F0A35E", "#E58AB3", "#8E7CC3", "#5C6F82"]

    static let symbols = [
        "fork.knife", "takeoutbag.and.cup.and.straw", "cup.and.saucer", "birthday.cake", "sun.horizon",
        "moon.stars", "cart", "basket", "bag", "tshirt", "house", "bolt", "drop", "wifi", "iphone",
        "tram", "train.side.front.car", "bus", "car", "fuelpump", "airplane", "bicycle",
        "gamecontroller", "film", "music.note", "book", "graduationcap", "dumbbell",
        "cross.case", "pills", "heart", "gift", "person.2", "pawprint", "scissors", "sparkles",
        "banknote", "dollarsign.circle", "creditcard", "building.columns", "chart.line.uptrend.xyaxis",
        "arrow.uturn.left.circle", "briefcase", "shield.checkered", "beach.umbrella", "target",
        "calendar", "star", "ellipsis",
    ]
}

/// Round colored icon used for categories, budgets and accounts.
struct SymbolBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
    }
}

struct TagCapsule: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
    }
}

extension Date {
    var monthTitle: String { formatted(.dateTime.year().month(.wide)) }
    var dayTitle: String { formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)) }
}
