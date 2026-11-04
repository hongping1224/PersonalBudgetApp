import SwiftUI

/// Arithmetic expression typed on the keypad, e.g. "120+35×2".
struct Calculator {
    static let operators: Set<Character> = ["+", "−", "×", "÷"]

    var expression = ""

    var value: Double? { Self.evaluate(expression) }
    var hasOperator: Bool { expression.dropFirst().contains { Self.operators.contains($0) } }

    mutating func press(_ key: String) {
        switch key {
        case "C":
            expression = ""
        case "⌫":
            if !expression.isEmpty { expression.removeLast() }
        case "=":
            if let v = value { expression = Money.plain(v) }
        case "+", "−", "×", "÷":
            guard let last = expression.last else { return }
            if Self.operators.contains(last) { expression.removeLast() }
            if last == "." { expression.removeLast() }
            expression.append(key)
        case ".":
            let current = currentNumber
            if current.contains(".") { return }
            expression += current.isEmpty ? "0." : "."
        default: // digits and "00"
            if currentNumber == "0" { expression.removeLast() }
            if key == "00" && currentNumber.isEmpty { expression += "0"; return }
            guard currentNumber.count < 12 else { return }
            expression += key
        }
    }

    private var currentNumber: String {
        String(expression.reversed().prefix { !Self.operators.contains($0) }.reversed())
    }

    static func evaluate(_ expression: String) -> Double? {
        var numbers: [Double] = []
        var ops: [Character] = []
        var current = ""
        for ch in expression {
            if operators.contains(ch) {
                guard let n = Double(current) else { return nil }
                numbers.append(n)
                ops.append(ch)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if let n = Double(current) {
            numbers.append(n)
        } else if !ops.isEmpty {
            ops.removeLast() // trailing operator, e.g. "120+"
        }
        guard !numbers.isEmpty else { return nil }

        // × and ÷ first, then + and −.
        var terms = [numbers[0]]
        var addOps: [Character] = []
        for (i, op) in ops.enumerated() {
            let n = numbers[i + 1]
            switch op {
            case "×": terms[terms.count - 1] *= n
            case "÷": terms[terms.count - 1] = n == 0 ? 0 : terms[terms.count - 1] / n
            default: terms.append(n); addOps.append(op)
            }
        }
        var result = terms[0]
        for (i, op) in addOps.enumerated() {
            result += op == "+" ? terms[i + 1] : -terms[i + 1]
        }
        return (result * 100).rounded() / 100
    }
}

struct Keypad: View {
    var onKey: (String) -> Void
    var onDone: () -> Void

    private let rows: [[String]] = [
        ["÷", "×", "−", "+"],
        ["7", "8", "9", "⌫"],
        ["4", "5", "6", "C"],
        ["1", "2", "3", "="],
        [".", "0", "00", "✓"],
    ]

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            if key == "✓" { onDone() } else { onKey(key) }
                        } label: {
                            label(for: key)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyStyle(isDone: key == "✓"))
                        .accessibilityIdentifier("key-\(key)")
                    }
                }
            }
        }
        .background(Color(.separator))
    }

    @ViewBuilder
    private func label(for key: String) -> some View {
        switch key {
        case "⌫": Image(systemName: "delete.left").font(.title2)
        case "✓": Image(systemName: "checkmark").font(.title2.weight(.semibold))
        case "÷", "×", "−", "+", "=": Text(key).font(.title.weight(.medium))
        default: Text(key).font(.title.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct KeyStyle: ButtonStyle {
    var isDone: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDone ? Color.white : Color.primary)
            .background(isDone ? Color.accent : Color.themeFill)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
