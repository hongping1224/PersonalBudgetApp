import SwiftUI
import SwiftData

/// One credit card bill: what's in it, with items the bank hasn't posted yet movable to the next bill.
struct StatementView: View {
    let account: Account
    @Environment(\.modelContext) private var context
    @State private var interval: DateInterval?
    @State private var editingEntry: Entry?

    var body: some View {
        ThemedList {
            if let interval {
                content(interval)
            } else {
                Text("請先在帳戶設定裡填寫出帳日。").foregroundStyle(.secondary)
            }
        }
        .themedBackground()
        .navigationTitle("\(account.name) 帳單")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if interval == nil { interval = account.defaultStatement() } }
        .sheet(item: $editingEntry) { EntryEditor(entry: $0) }
    }

    @ViewBuilder
    private func content(_ interval: DateInterval) -> some View {
        let items = account.statementEntries(in: interval)
        let payments = account.statementPayments(in: interval)
        let total = account.statementTotal(in: interval)
        let closed = interval.end <= Calendar.current.startOfDay(for: .now)

        Section {
            VStack(spacing: 6) {
                Text(closed ? "已出帳" : "未出帳（\(interval.closingDate.formatted(.dateTime.month(.defaultDigits).day())) 出帳）")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(Money.string(total))
                    .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.expense)
                Text(interval.shortLabel).font(.caption).foregroundStyle(.secondary)
                if let due = account.dueDate(for: interval) {
                    Text("繳款截止 \(due.formatted(.dateTime.month(.defaultDigits).day()))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.teal, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            HStack {
                Button { self.interval = account.statementInterval(offset: -1, from: interval) } label: {
                    Label("上一期", systemImage: "chevron.left")
                }
                Spacer()
                Button { self.interval = account.statementInterval(offset: 1, from: interval) } label: {
                    Text("下一期")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }

        Section {
            if items.isEmpty { Text("這期沒有消費").foregroundStyle(.secondary) }
            ForEach(items) { entry in
                HStack {
                    Button { editingEntry = entry } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            EntryRow(entry: entry, showDate: true)
                            if entry.statementOffset > 0, let base = account.statementInterval(containing: entry.date),
                               base != interval {
                                Text("從上期移入").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .tint(.primary)
                    VStack(spacing: 4) {
                        Button("移到下期") { move(entry, by: 1) }
                        if entry.statementOffset > 0 {
                            Button("移回上期") { move(entry, by: -1) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        } header: {
            Text("消費 (\(items.count))")
        } footer: {
            Text("銀行帳單上還沒出現的消費，按「移到下期」會改算到下一期帳單；日期和帳戶餘額不變。")
        }

        if !payments.isEmpty {
            Section("這期間的繳款") {
                ForEach(payments) { entry in
                    Button { editingEntry = entry } label: { EntryRow(entry: entry, showDate: true) }
                        .tint(.primary)
                }
            }
        }
    }

    private func move(_ entry: Entry, by step: Int) {
        entry.statementOffset = max(0, entry.statementOffset + step)
        try? context.save()
    }
}
