import SwiftUI

/// 手機條碼載具 (Taiwan e-invoice mobile carrier): "/" + 7 of 0-9 A-Z . + -, shown as a Code 39 barcode.
/// Stored in the App Group so the widget can show it too.
enum Carrier {
    static let key = "carrierNumber"
    private static var store: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroup) ?? .standard }

    static var number: String? {
        get { store.string(forKey: key).flatMap { isValid($0) ? $0 : nil } }
        set { store.set(newValue, forKey: key) }
    }

    /// Upper-cases and adds the leading "/" if it was left out.
    static func normalized(_ text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespaces).uppercased()
        return s.hasPrefix("/") || s.isEmpty ? s : "/" + s
    }

    static func isValid(_ text: String) -> Bool {
        text.count == 8 && text.first == "/"
            && text.dropFirst().allSatisfy { "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.+-".contains($0) }
    }

    /// budgetapp://carrier — opens the app on the barcode and copies the number.
    static let link = URL(string: "budgetapp://carrier")!
}

/// Code 39: each character is 9 elements (bar, space, bar, …), three of them wide; "*" starts and stops.
enum Code39 {
    static let patterns: [Character: String] = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw", "3": "wnwwnnnnn", "4": "nnnwwnnnw",
        "5": "wnnwwnnnn", "6": "nnwwwnnnn", "7": "nnnwnnwnw", "8": "wnnwnnwnn", "9": "nnwwnnwnn",
        "A": "wnnnnwnnw", "B": "nnwnnwnnw", "C": "wnwnnwnnn", "D": "nnnnwwnnw", "E": "wnnnwwnnn",
        "F": "nnwnwwnnn", "G": "nnnnnwwnw", "H": "wnnnnwwnn", "I": "nnwnnwwnn", "J": "nnnnwwwnn",
        "K": "wnnnnnnww", "L": "nnwnnnnww", "M": "wnwnnnnwn", "N": "nnnnwnnww", "O": "wnnnwnnwn",
        "P": "nnwnwnnwn", "Q": "nnnnnnwww", "R": "wnnnnnwwn", "S": "nnwnnnwwn", "T": "nnnnwnwwn",
        "U": "wwnnnnnnw", "V": "nwwnnnnnw", "W": "wwwnnnnnn", "X": "nwnnwnnnw", "Y": "wwnnwnnnn",
        "Z": "nwwnwnnnn", "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn", "*": "nwnnwnwnn",
        "$": "nwnwnwnnn", "/": "nwnwnnnwn", "+": "nwnnnwnwn", "%": "nnnwnwnwn",
    ]
    static let wide = 3

    /// Element widths in modules, bars at even indexes, with a 1-module gap between characters.
    static func widths(for text: String) -> [Int]? {
        var out: [Int] = []
        for (i, ch) in ("*" + text + "*").enumerated() {
            guard let p = patterns[ch] else { return nil }
            if i > 0 { out.append(1) }
            out += p.map { $0 == "w" ? wide : 1 }
        }
        return out
    }
}

/// Black bars filling the frame; draw it on white with some quiet space around it.
struct Code39Shape: Shape {
    var text: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let widths = Code39.widths(for: text) else { return path }
        let module = rect.width / CGFloat(widths.reduce(0, +))
        var x = rect.minX
        for (i, w) in widths.enumerated() {
            let width = CGFloat(w) * module
            if i % 2 == 0 { path.addRect(CGRect(x: x, y: rect.minY, width: width, height: rect.height)) }
            x += width
        }
        return path
    }
}

/// The carrier barcode with its number underneath, always black on white so scanners can read it.
struct CarrierBarcode: View {
    var number: String
    var fontSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 4) {
            Code39Shape(text: number).fill(Color.black)
            Text(number)
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.black)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("載具條碼 \(number)")
    }
}

/// The barcode card on the widgets. iOS doesn't let widgets write to the clipboard, so tapping
/// opens the app, which copies the number (or asks for one if none is set).
struct CarrierWidgetCard: View {
    var number: String?
    var fontSize: CGFloat = 15

    var body: some View {
        Link(destination: Carrier.link) {
            if let number {
                CarrierBarcode(number: number, fontSize: fontSize)
            } else {
                Label("在 App 的 設定 → 載具 輸入號碼", systemImage: "barcode")
                    .font(.caption).foregroundStyle(Color.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
