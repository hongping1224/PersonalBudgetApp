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

    /// Color for check-ins on the calendar and in lists.
    static let color = Color(hex: "#E8A33D")
}

extension Account {
    /// Accounts whose balance can be checked by counting it.
    var canCheckBalance: Bool { type == .cash }
}
