import Foundation
import SwiftData
import UserNotifications

/// Monthly notification on each credit card's closing day; tapping it opens that card's statement.
@MainActor
enum StatementReminder {
    private static let prefix = "statement-"
    static let accountKey = "accountID"

    static func reschedule(context: ModelContext) {
        // UI tests can't answer the permission prompt.
        if ProcessInfo.processInfo.arguments.contains("-uitest") { return }
        let cards = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { $0.type == .creditCard && !$0.isArchived && $0.statementDay != nil }
            .map { (id: $0.id, name: $0.name, day: $0.statementDay!) }
        let center = UNUserNotificationCenter.current()
        Task {
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard !cards.isEmpty,
                  (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for card in cards {
                let content = UNMutableNotificationContent()
                content.title = "\(card.name) 今天出帳"
                content.body = "點這裡核對這期帳單明細，還沒出帳的項目可以移到下期。"
                content.sound = .default
                content.userInfo = [accountKey: card.id.uuidString]
                // Days past 28 would skip short months, so those remind on the 28th.
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(day: min(card.day, 28), hour: 20),
                                                            repeats: true)
                try? await center.add(UNNotificationRequest(identifier: prefix + card.id.uuidString,
                                                            content: content, trigger: trigger))
            }
        }
    }
}
