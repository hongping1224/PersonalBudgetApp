import SwiftUI
import WidgetKit

/// Widget layouts; also compiled into the app so tests can render them.
struct QuickAddWidgetView: View {
    var snapshot: WidgetSnapshot
    var date: Date
    var family: WidgetFamily
    /// Shown at the top of the large widget.
    var carrier: String? = Carrier.number
    /// Colors to draw with; nil uses the app's theme colors.
    var theme: AppTheme? = nil

    private var expenseColor: Color { theme.map { Color(hex: $0.expense) } ?? .expense }
    private var accentColor: Color { theme.map { Color(hex: $0.accent) } ?? .accent }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus").font(.title2.weight(.semibold))
            }
            .widgetURL(QuickAddLink().url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("記一筆", systemImage: "plus.circle.fill").font(.headline)
                Text("今日支出 \(Money.string(snapshot.todaySpent(on: date)))").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(QuickAddLink().url)
        case .systemSmall:
            small
        case .systemLarge:
            large
        default:
            medium
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今日支出").font(.caption).foregroundStyle(.secondary)
            Text(Money.string(snapshot.todaySpent(on: date)))
                .font(.title3.weight(.bold)).monospacedDigit()
                .foregroundStyle(expenseColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("本月 \(Money.string(snapshot.monthSpent(on: date)))")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var addButton: some View {
        Link(destination: QuickAddLink().url) {
            Label("記一筆", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private var small: some View {
        VStack(alignment: .leading) {
            totals
            Spacer(minLength: 4)
            addButton
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                totals
                Spacer(minLength: 4)
                addButton
            }
            .frame(width: 112)
            let shown = Array(snapshot.categories.prefix(6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 6) {
                ForEach(shown) { c in
                    Link(destination: QuickAddLink(category: c.id.uuidString).url) {
                        VStack(spacing: 3) {
                            SymbolBadge(symbol: c.symbol, color: Color(hex: c.colorHex), size: 34)
                            Text(c.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Carrier barcode on top (tap: open the app, which copies the number), quick add below.
    private var large: some View {
        VStack(spacing: 12) {
            CarrierWidgetCard(number: carrier)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(height: 110)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .bottom) {
                totals
                Spacer()
                addButton.frame(width: 120)
            }
            let shown = Array(snapshot.categories.prefix(8))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 8) {
                ForEach(shown) { c in
                    Link(destination: QuickAddLink(category: c.id.uuidString).url) {
                        VStack(spacing: 3) {
                            SymbolBadge(symbol: c.symbol, color: Color(hex: c.colorHex), size: 38)
                            Text(c.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
