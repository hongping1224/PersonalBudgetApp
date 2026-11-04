import SwiftUI
import WidgetKit

@main
struct BudgetWidgets: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        CarrierWidget()
    }
}

struct QuickAddEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var carrier: String? = Carrier.number
}

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        let saved = WidgetSnapshot.load()
        completion(QuickAddEntry(date: .now, snapshot: context.isPreview && saved.categories.isEmpty ? .placeholder : saved,
                                 carrier: Carrier.number ?? (context.isPreview ? "/ABC1234" : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        // The app reloads the widget after changes; the midnight entry resets "today" to 0.
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let snapshot = WidgetSnapshot.load()
        completion(Timeline(entries: [QuickAddEntry(date: now, snapshot: snapshot),
                                      QuickAddEntry(date: midnight, snapshot: snapshot)],
                            policy: .never))
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickAdd", provider: QuickAddProvider()) { entry in
            QuickAddEntryView(entry: entry)
        }
        .configurationDisplayName("快速記帳")
        .description("顯示今日支出，點一下就能記一筆，或直接選分類。大尺寸上方有載具條碼，點條碼會打開 App 並複製號碼。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

private struct QuickAddEntryView: View {
    var entry: QuickAddEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = AppTheme.current(for: scheme)
        QuickAddWidgetView(snapshot: entry.snapshot, date: entry.date, family: family,
                           carrier: entry.carrier, theme: theme)
            .environment(\.colorScheme, theme.colorScheme)
            .containerBackground(Color(hex: theme.background), for: .widget)
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        categories: [
            .init(id: UUID(), name: "食物", symbol: "fork.knife", colorHex: "#E9C98F"),
            .init(id: UUID(), name: "交通", symbol: "scooter", colorHex: "#5BA4A4"),
            .init(id: UUID(), name: "玩樂", symbol: "gamecontroller", colorHex: "#8E7CC3"),
            .init(id: UUID(), name: "家庭", symbol: "house", colorHex: "#D9706F"),
            .init(id: UUID(), name: "個人", symbol: "person", colorHex: "#4A90E2"),
            .init(id: UUID(), name: "其他", symbol: "ellipsis", colorHex: "#6C5FA7"),
        ],
        todaySpent: 350, monthSpent: 12_480, day: .now)
}

struct CarrierEntry: TimelineEntry {
    var date: Date
    var number: String?
}

struct CarrierProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarrierEntry { CarrierEntry(date: .now, number: "/ABC1234") }

    func getSnapshot(in context: Context, completion: @escaping (CarrierEntry) -> Void) {
        completion(CarrierEntry(date: .now, number: Carrier.number ?? (context.isPreview ? "/ABC1234" : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarrierEntry>) -> Void) {
        // The app reloads the widget when the number changes.
        completion(Timeline(entries: [CarrierEntry(date: .now, number: Carrier.number)], policy: .never))
    }
}

/// 載具條碼: scannable at the counter; tapping opens the app, which copies the number.
struct CarrierWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Carrier", provider: CarrierProvider()) { entry in
            CarrierWidgetView(number: entry.number)
        }
        .configurationDisplayName("載具條碼")
        .description("結帳時給店員掃；點一下會打開 App 並複製載具號碼。")
        .supportedFamilies([.systemMedium, .systemSmall])
        .contentMarginsDisabled()
    }
}

private struct CarrierWidgetView: View {
    var number: String?
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = AppTheme.current(for: scheme)
        // Just the barcode on a white card (scanners need black on white), framed by the theme.
        CarrierWidgetCard(number: number, fontSize: family == .systemSmall ? 13 : 16)
            .padding(.horizontal, family == .systemSmall ? 4 : 12)
            .padding(.vertical, 8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .padding(family == .systemSmall ? 6 : 8)
            .containerBackground(Color(hex: theme.background), for: .widget)
    }
}
