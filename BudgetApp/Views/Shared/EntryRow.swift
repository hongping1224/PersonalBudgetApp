import SwiftUI

struct EntryRow: View {
    let entry: Entry
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            if entry.kind == .transfer {
                SymbolBadge(symbol: "arrow.left.arrow.right", color: Color(hex: "#5C6F82"))
            } else {
                SymbolBadge(symbol: entry.category?.symbol ?? "questionmark",
                            color: Color(hex: entry.category?.colorHex ?? "#8A9099"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).lineLimit(1)
                if showDate {
                    Text(entry.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary)
                } else if !entry.name.isEmpty, entry.kind != .transfer, let c = entry.category {
                    Text(c.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.string(entry.amount, currency: entry.currency))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                if let foreign = entry.foreignAmount, let code = entry.foreignCurrency {
                    Text(Money.string(foreign, currency: code)).font(.caption).foregroundStyle(.secondary)
                } else if let arrived = entry.toAmount, let to = entry.toAccount {
                    Text("→ " + Money.string(arrived, currency: to.currency)).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if let budget = entry.budget {
                        TagCapsule(text: budget.name, color: Color(hex: "#E9C98F"))
                    }
                    if entry.kind == .transfer {
                        TagCapsule(text: "\(entry.account?.fullName ?? "?") → \(entry.toAccount?.fullName ?? "?")", color: .teal)
                    } else if let account = entry.account {
                        TagCapsule(text: account.fullName, color: .teal)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var amountColor: Color {
        switch entry.kind {
        case .expense: .expense
        case .income: .income
        case .transfer: .primary
        }
    }
}
