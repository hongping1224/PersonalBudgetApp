import Foundation
import SwiftData
import SwiftUI

/// 對帳打卡: a personal note that the cash counted matched the recorded balance at `date`.
/// Not an entry — balances and totals ignore it; it only marks how far back is already checked.
@Model
final class BalanceCheck {
    var id: UUID = UUID()
    var date: Date = Date()
    var accountID: UUID = UUID()
    /// The recorded balance that matched.
    var balance: Double = 0

    init(account: Account, date: Date = .now) {
        self.accountID = account.id
        self.date = date
        self.balance = account.balance(upTo: date.addingTimeInterval(1))
    }

    init(accountID: UUID, date: Date, balance: Double) {
        self.accountID = accountID
        self.date = date
        self.balance = balance
    }

    /// Checks in `account` at `date`, keeping only its latest check-in: an older one is replaced,
    /// and a check-in dated before the latest one is ignored.
    @discardableResult
    static func record(_ account: Account, date: Date = .now, in context: ModelContext) -> BalanceCheck? {
        let id = account.id
        let existing = (try? context.fetch(FetchDescriptor<BalanceCheck>(predicate: #Predicate { $0.accountID == id }))) ?? []
        if let latest = existing.map(\.date).max(), latest > date { return nil }
        existing.forEach(context.delete)
        let check = BalanceCheck(account: account, date: date)
        context.insert(check)
        try? context.save()
        return check
    }

    /// Drops all but each account's latest check-in (from before only the latest was kept).
    static func pruneToLatest(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BalanceCheck>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var seen = Set<UUID>()
        var changed = false
        for check in all where !seen.insert(check.accountID).inserted {
            context.delete(check)
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Color for check-ins on the calendar and in lists.
    static let color = Color(hex: "#E8A33D")
}

extension Account {
    /// Accounts whose balance can be checked by counting it.
    var canCheckBalance: Bool { type == .cash }
}
