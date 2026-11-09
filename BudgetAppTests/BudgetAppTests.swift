import XCTest
import SwiftData
import SwiftUI
import WidgetKit
@testable import BudgetApp

@MainActor
final class BudgetAppTests: XCTestCase {
    var context: ModelContext!

    override func setUp() async throws {
        let container = try ModelContainer(for: DataStore.schema,
                                           configurations: ModelConfiguration(schema: DataStore.schema, isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: Budget periods

    func testMonthlyPeriodStartingOn14th() {
        let b = Budget(name: "Living", amount: 894, period: .monthly, anchorDay: 14)
        let i = b.interval(containing: date(2026, 10, 27))
        XCTAssertEqual(i.start, date(2026, 10, 14, 0))
        XCTAssertEqual(i.end, date(2026, 11, 14, 0))
        XCTAssertEqual(i.shortLabel, "26/10/14 – 26/11/13")

        let before = b.interval(containing: date(2026, 10, 3))
        XCTAssertEqual(before.start, date(2026, 9, 14, 0))
    }

    func testMonthlyPeriodClampsToShortMonths() {
        let b = Budget(name: "x", amount: nil, period: .monthly, anchorDay: 31)
        let i = b.interval(containing: date(2026, 2, 15))
        XCTAssertEqual(i.start, date(2026, 1, 31, 0))
        XCTAssertEqual(i.end, date(2026, 2, 28, 0))
        let next = b.interval(offset: 1, from: date(2026, 2, 15))
        XCTAssertEqual(next.start, date(2026, 2, 28, 0))
        XCTAssertEqual(next.end, date(2026, 3, 31, 0))
    }

    func testWeeklyPeriodStartingMonday() {
        let b = Budget(name: "lunch", amount: 750, period: .weekly, anchorDay: 2)
        let i = b.interval(containing: date(2026, 10, 27)) // Tuesday
        XCTAssertEqual(i.start, date(2026, 10, 26, 0))
        XCTAssertEqual(i.end, date(2026, 11, 2, 0))
        XCTAssertEqual(b.interval(offset: -1, from: date(2026, 10, 27)).start, date(2026, 10, 19, 0))
    }

    func testDailyAvailable() {
        // Weekly from Monday: 2026/10/26 – 11/1.
        let b = Budget(name: "lunch", amount: 750, period: .weekly, anchorDay: 2)
        context.insert(b)
        context.insert(Entry(kind: .expense, amount: 125, date: date(2026, 10, 26), budget: b))
        try? context.save()
        let tuesday = date(2026, 10, 27)
        let week = b.interval(containing: tuesday)

        XCTAssertEqual(b.daysLeft(in: week, on: tuesday), 6)
        XCTAssertEqual(b.dailyAvailable(in: week, on: tuesday), 104)            // 625 / 6, rounded down
        XCTAssertEqual(b.spentToday(in: week, on: tuesday), 0)
        XCTAssertEqual(b.dailyAvailable(in: week, on: date(2026, 11, 1)), 625)  // last day
        XCTAssertNil(b.dailyAvailable(in: week, on: date(2026, 11, 2)))         // period is over

        // Spending today fills today's bar but doesn't change today's amount; tomorrow's does.
        context.insert(Entry(kind: .expense, amount: 300, date: tuesday.addingTimeInterval(3600), budget: b))
        try? context.save()
        XCTAssertEqual(b.dailyAvailable(in: week, on: tuesday), 104)
        XCTAssertEqual(b.spentToday(in: week, on: tuesday), 300)
        XCTAssertEqual(b.dailyAvailable(in: week, on: date(2026, 10, 28)), 65)  // 325 / 5

        // Overspent by yesterday.
        context.insert(Entry(kind: .expense, amount: 900, date: tuesday.addingTimeInterval(3600), budget: b))
        try? context.save()
        XCTAssertEqual(b.dailyAvailable(in: week, on: date(2026, 10, 28)), 0)

        let tracker = Budget(name: "work", amount: nil, period: .monthly)
        context.insert(tracker)
        XCTAssertNil(tracker.dailyAvailable(in: tracker.interval(containing: tuesday), on: tuesday))
    }

    func testBudgetSpentCountsRefunds() {
        let b = Budget(name: "lunch", amount: 750, period: .weekly, anchorDay: 2)
        context.insert(b)
        context.insert(Entry(kind: .expense, amount: 120, date: date(2026, 10, 27), budget: b))
        context.insert(Entry(kind: .expense, amount: 100, date: date(2026, 10, 26), budget: b))
        context.insert(Entry(kind: .income, amount: 20, date: date(2026, 10, 27), budget: b))
        context.insert(Entry(kind: .expense, amount: 999, date: date(2026, 10, 25), budget: b)) // previous week
        try? context.save()
        XCTAssertEqual(b.spent(in: b.interval(containing: date(2026, 10, 27))), 200)
    }

    func testCarryOverRollsLeftoverAndOverspend() {
        let b = Budget(name: "生活", amount: 1000, period: .monthly, anchorDay: 14)
        context.insert(b)
        b.carriesOver = true
        b.carryOverStart = date(2026, 8, 20) // period 8/14–9/13
        context.insert(Entry(kind: .expense, amount: 800, date: date(2026, 8, 20), budget: b))  // +200
        context.insert(Entry(kind: .expense, amount: 1300, date: date(2026, 9, 20), budget: b)) // -300
        context.insert(Entry(kind: .expense, amount: 50, date: date(2026, 10, 20), budget: b))
        try? context.save()

        let october = b.interval(containing: date(2026, 10, 27))
        XCTAssertEqual(b.carryIn(to: october), -100)
        XCTAssertEqual(b.available(in: october), 900)

        // Forgiving overspend: +200, then 200 - 300 clamps to 0.
        b.carryOverspend = false
        XCTAssertEqual(b.carryIn(to: october), 0)

        // Periods before the start date don't count.
        b.carryOverspend = true
        b.carryOverStart = date(2026, 9, 20)
        XCTAssertEqual(b.carryIn(to: october), -300)

        b.carriesOver = false
        XCTAssertEqual(b.available(in: october), 1000)
    }

    func testBudgetTransferMovesAvailableAmount() throws {
        let lunch = Budget(name: "lunch", amount: 750, period: .weekly, anchorDay: 2)
        let dinner = Budget(name: "Dinner", amount: 1250, period: .weekly, anchorDay: 2)
        [lunch, dinner].forEach(context.insert)
        let id = UUID()
        let when = date(2026, 10, 27)
        context.insert(BudgetAdjustment(transferID: id, amount: -200, date: when, budget: lunch, counterpartName: "Dinner"))
        context.insert(BudgetAdjustment(transferID: id, amount: 200, date: when, budget: dinner, counterpartName: "lunch"))
        try context.save()

        let week = lunch.interval(containing: when)
        XCTAssertEqual(lunch.available(in: week), 550)
        XCTAssertEqual(dinner.available(in: week), 1450)
        // Next week is back to normal.
        XCTAssertEqual(lunch.available(in: lunch.interval(offset: 1, from: when)), 750)

        // Survives backup and restore.
        let data = try BackupFile.encoder.encode(try BackupFile(context: context))
        try BackupFile.decoder.decode(BackupFile.self, from: data).restore(into: context)
        let restored = try context.fetch(FetchDescriptor<Budget>()).first { $0.name == "Dinner" }
        XCTAssertEqual(restored?.available(in: week), 1450)
    }

    // MARK: Accounts

    func testBalancesWithTransfers() {
        let wallet = Account(name: "錢包", type: .cash, initialBalance: 1000)
        let card = Account(name: "甲銀行 卡", type: .creditCard)
        [wallet, card].forEach(context.insert)
        context.insert(Entry(kind: .expense, amount: 120, date: .now, account: wallet))
        context.insert(Entry(kind: .expense, amount: 500, date: .now, account: card))
        context.insert(Entry(kind: .income, amount: 50, date: .now, account: wallet))
        context.insert(Entry(kind: .transfer, amount: 300, date: .now, account: wallet, toAccount: card))
        try? context.save()
        XCTAssertEqual(wallet.balance, 1000 - 120 + 50 - 300)
        XCTAssertEqual(card.balance, -500 + 300)
    }

    // MARK: MOZE import

    func testMozeImportEnglishHeaders() throws {
        let csv = """
        Account,Currency,Type,Main Category,Subcategory,Price,Fee,Bonus,Name,Store,Date,Time,Project,Description,Tags,Target
        Wallet,TWD,Expense,Food,Lunch,-120,0,0,麵店,,2026/10/27,12:30,lunch,,,
        甲銀行,TWD,Income,Others,Repayment,20000,0,0,朋友,,2026/10/27,09:00,,,,
        甲銀行,TWD,Transfer Out,Transfer,,-5000,0,0,,,2026/10/20,10:00,,,,
        Wallet,TWD,Transfer In,Transfer,,5000,0,0,,,2026/10/20,10:00,,,,
        ,,,,,,,,,,not a date,,,,,
        """
        var importer = MozeImporter(context: context)
        let s = try importer.run(csv: csv)
        XCTAssertEqual(s.entries, 2)
        XCTAssertEqual(s.transfers, 1)
        XCTAssertEqual(s.newBudgets, 1)
        XCTAssertEqual(s.skipped, 1)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let wallet = try XCTUnwrap(accounts.first { $0.name == "Wallet" })
        let bank = try XCTUnwrap(accounts.first { $0.name == "甲銀行" })
        XCTAssertEqual(wallet.type, .cash)
        XCTAssertEqual(wallet.balance, -120 + 5000)
        XCTAssertEqual(bank.balance, 20000 - 5000)

        let lunch = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first { $0.name == "麵店" })
        XCTAssertEqual(lunch.category?.name, "Lunch")
        XCTAssertEqual(lunch.budget?.name, "lunch")
        XCTAssertEqual(lunch.kind, .expense)
        XCTAssertEqual(Calendar.current.component(.minute, from: lunch.date), 30)
    }

    func testMozeImportRejectsUnknownFile() {
        var importer = MozeImporter(context: context)
        XCTAssertThrowsError(try importer.run(csv: "foo,bar\n1,2"))
    }

    // MARK: Categories

    func testMergeCategory() throws {
        let wallet = Account(name: "錢包", type: .cash)
        let lunch = EntryCategory(name: "午餐", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let food = EntryCategory(name: "食物", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        context.insert(wallet); context.insert(lunch); context.insert(food)
        EntryService.add(kind: .expense, amount: 120, name: "便當", category: lunch, account: wallet, budget: nil, in: context)
        EntryService.add(kind: .expense, amount: 60, name: "麵包", category: food, account: wallet, budget: nil, in: context)

        CategoryMerge.merge(lunch, into: food, context: context)

        let categories = try context.fetch(FetchDescriptor<EntryCategory>())
        XCTAssertEqual(categories.map(\.name), ["食物"])
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.category?.name == "食物" })
    }

    // MARK: Split and claim

    func testSplitThenSettleClaim() throws {
        let card = Account(name: "甲銀行", type: .creditCard)
        let bank = Account(name: "乙銀行", type: .bank)
        let food = EntryCategory(name: "食物", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let repaid = EntryCategory(name: "還款", symbol: "arrow.uturn.left.circle", colorHex: "#fff", kind: .income)
        let claim = Budget(name: "Claim", amount: nil, period: .monthly, anchorDay: 1)
        context.insert(card); context.insert(bank)
        context.insert(food); context.insert(repaid); context.insert(claim)
        let dinner = EntryService.add(kind: .expense, amount: 1000, date: date(2026, 10, 3), name: "燒肉",
                                      category: food, account: card, in: context)

        XCTAssertNil(EntryService.split(dinner, part: 1000, name: "x", budget: claim, in: context), "must leave something")
        let share = try XCTUnwrap(EntryService.split(dinner, part: 400, name: "燒肉 朋友", budget: claim, in: context))
        XCTAssertEqual(dinner.amount, 600)
        XCTAssertEqual(share.amount, 400)
        XCTAssertEqual(share.date, dinner.date)
        XCTAssertEqual(share.category?.name, "食物")
        XCTAssertEqual(share.account?.name, "甲銀行")
        XCTAssertTrue(claim.isClaim)
        XCTAssertEqual(claim.entries?.count, 1)
        XCTAssertEqual(card.balance(upTo: nil), -1000)

        let income = EntryService.settleClaim(share, into: bank, in: context)
        XCTAssertNil(share.budget)
        XCTAssertEqual(claim.entries?.count, 0)
        XCTAssertEqual(income.kind, .income)
        XCTAssertEqual(income.amount, 400)
        XCTAssertEqual(income.name, "燒肉 朋友")
        XCTAssertEqual(income.category?.name, "還款")
        XCTAssertEqual(bank.balance(upTo: nil), 400)
    }

    // MARK: Credit card statements

    func testStatementPeriods() throws {
        let card = Account(name: "甲銀行", type: .creditCard)
        card.statementDay = 5
        card.paymentDueDay = 20
        let oct = try XCTUnwrap(card.statementInterval(containing: date(2026, 10, 3)))
        XCTAssertEqual(oct.start, date(2026, 9, 6, 0))
        XCTAssertEqual(oct.closingDate, date(2026, 10, 5, 0))
        XCTAssertEqual(card.statementInterval(containing: date(2026, 10, 5, 23)), oct, "closing day belongs to its statement")
        XCTAssertEqual(card.statementInterval(containing: date(2026, 10, 6))?.closingDate, date(2026, 11, 5, 0))
        XCTAssertEqual(card.statementInterval(offset: 1, from: oct)?.closingDate, date(2026, 11, 5, 0))
        XCTAssertEqual(card.dueDate(for: oct), date(2026, 10, 20, 0))

        card.statementDay = 31
        let feb = try XCTUnwrap(card.statementInterval(containing: date(2027, 2, 10)))
        XCTAssertEqual(feb.start, date(2027, 2, 1, 0))
        XCTAssertEqual(feb.closingDate, date(2027, 2, 28, 0))
        XCTAssertEqual(card.statementInterval(offset: 1, from: feb)?.closingDate, date(2027, 3, 31, 0))

        card.statementDay = nil
        XCTAssertNil(card.statementInterval(containing: .now))
    }

    func testMoveEntryToNextStatement() throws {
        let card = Account(name: "甲銀行", type: .creditCard)
        card.statementDay = 5
        let food = EntryCategory(name: "食物", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        context.insert(card); context.insert(food)
        let lunch = EntryService.add(kind: .expense, amount: 300, date: date(2026, 10, 1), category: food, account: card, in: context)
        EntryService.add(kind: .expense, amount: 500, date: date(2026, 10, 4), category: food, account: card, in: context)
        EntryService.add(kind: .income, amount: 100, date: date(2026, 9, 20), name: "退款", category: nil, account: card, in: context)
        EntryService.add(kind: .expense, amount: 70, date: date(2026, 10, 8), category: food, account: card, in: context)

        let oct = try XCTUnwrap(card.statementInterval(containing: date(2026, 10, 1)))
        let nov = try XCTUnwrap(card.statementInterval(offset: 1, from: oct))
        XCTAssertEqual(card.statementTotal(in: oct), 700, "300 + 500 - 100 refund")
        XCTAssertEqual(card.statementTotal(in: nov), 70)

        lunch.statementOffset = 1
        XCTAssertEqual(card.statementTotal(in: oct), 400)
        XCTAssertEqual(card.statementTotal(in: nov), 370)
        XCTAssertTrue(card.statementEntries(in: nov).contains { $0.id == lunch.id })
        XCTAssertEqual(card.balance(upTo: nil), -770, "moving between bills doesn't change the balance")

        // Survives a backup round trip.
        let data = try BackupFile.encoder.encode(try BackupFile(context: context))
        try BackupFile.decoder.decode(BackupFile.self, from: data).restore(into: context)
        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Account>()).first)
        XCTAssertEqual(restored.statementDay, 5)
        XCTAssertEqual(restored.statementTotal(in: nov), 370)
    }

    func testAccountHistoryDefaultRange() {
        XCTAssertEqual(AccountHistory.start(months: 2, now: date(2026, 10, 30)), date(2026, 9, 1, 0))
        XCTAssertEqual(AccountHistory.start(months: 1, now: date(2026, 10, 30)), date(2026, 10, 1, 0))
        XCTAssertEqual(AccountHistory.start(months: 3, now: date(2026, 1, 15)), date(2025, 11, 1, 0))
    }

    // MARK: Widget

    func testQuickAddLinkRoundTrip() throws {
        let link = QuickAddLink(kind: "expense", category: "交通")
        XCTAssertEqual(QuickAddLink(url: link.url), link)
        XCTAssertEqual(QuickAddLink(url: URL(string: "budgetapp://add")!), QuickAddLink())
        XCTAssertNil(QuickAddLink(url: URL(string: "https://example.com/add")!))
    }

    func testWidgetSnapshotTotals() throws {
        let wallet = Account(name: "錢包", type: .cash)
        let food = EntryCategory(name: "食物", symbol: "fork.knife", colorHex: "#fff", kind: .expense, sortOrder: 1)
        let ride = EntryCategory(name: "交通", symbol: "scooter", colorHex: "#fff", kind: .expense, sortOrder: 0)
        let pay = EntryCategory(name: "薪水", symbol: "banknote", colorHex: "#fff", kind: .income)
        context.insert(wallet); context.insert(food); context.insert(ride); context.insert(pay)
        let now = date(2026, 10, 29, 15)
        EntryService.add(kind: .expense, amount: 120, date: date(2026, 10, 29, 9), category: food, account: wallet, in: context)
        EntryService.add(kind: .expense, amount: 50, date: date(2026, 10, 29, 13), category: ride, account: wallet, in: context)
        EntryService.add(kind: .expense, amount: 300, date: date(2026, 10, 2), category: food, account: wallet, in: context)
        EntryService.add(kind: .expense, amount: 999, date: date(2026, 9, 30), category: food, account: wallet, in: context)
        EntryService.add(kind: .income, amount: 5000, date: date(2026, 10, 29, 10), category: pay, account: wallet, in: context)

        let s = WidgetSync.snapshot(context, now: now)
        XCTAssertEqual(s.todaySpent(on: now), 170)
        XCTAssertEqual(s.monthSpent(on: now), 470)
        XCTAssertEqual(s.categories.map(\.name), ["交通", "食物"])
        XCTAssertEqual(s.todaySpent(on: date(2026, 10, 30)), 0, "yesterday's total must not show")
    }

    /// Renders the widget layouts so they can be checked by eye (attachments in the test result).
    func testRenderWidgetLayouts() throws {
        let snapshot = WidgetSnapshot(categories: [
            .init(id: UUID(), name: "食物", symbol: "fork.knife", colorHex: "#E9C98F"),
            .init(id: UUID(), name: "玩樂", symbol: "gamecontroller", colorHex: "#8E7CC3"),
            .init(id: UUID(), name: "家庭", symbol: "house", colorHex: "#D9706F"),
            .init(id: UUID(), name: "個人", symbol: "person", colorHex: "#4A90E2"),
            .init(id: UUID(), name: "交通", symbol: "scooter", colorHex: "#5BA4A4"),
            .init(id: UUID(), name: "保險", symbol: "shield.checkered", colorHex: "#7A8B5C"),
            .init(id: UUID(), name: "其他", symbol: "ellipsis", colorHex: "#6C5FA7"),
        ], todaySpent: 385, monthSpent: 23_456, day: .now)
        let sizes: [(WidgetFamily, CGSize)] = [(.systemSmall, CGSize(width: 170, height: 170)),
                                               (.systemMedium, CGSize(width: 364, height: 170)),
                                               (.systemLarge, CGSize(width: 338, height: 354))]
        for (family, size) in sizes {
            let view = QuickAddWidgetView(snapshot: snapshot, date: .now, family: family, carrier: "/ABC1234")
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "widget-\(family)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        // 載具條碼 widget, medium: barcode only (same layout as the widget extension).
        let carrier = CarrierWidgetCard(number: "/ABC1234", fontSize: 16)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(width: 364, height: 170)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        let renderer = ImageRenderer(content: carrier)
        renderer.scale = 3
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "widget-carrier-medium"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Backup

    func testBackupRoundTrip() throws {
        Seed.insertDefaultsIfNeeded(context)
        let wallet = try XCTUnwrap(try context.fetch(FetchDescriptor<Account>()).first)
        let lunch = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryCategory>()).first { $0.name == "食物" })
        let budget = Budget(name: "lunch", amount: 750, period: .weekly, anchorDay: 2)
        context.insert(budget)
        budget.carriesOver = true
        budget.carryOverspend = false
        budget.carryOverStart = date(2026, 10, 1)
        budget.showsDaily = true
        EntryService.add(kind: .expense, amount: 120, name: "便當", category: lunch, account: wallet, budget: budget, in: context)

        let data = try BackupFile.encoder.encode(try BackupFile(context: context))
        let decoded = try BackupFile.decoder.decode(BackupFile.self, from: data)
        try decoded.restore(into: context)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.category?.name, "食物")
        XCTAssertEqual(entries.first?.budget?.amount, 750)
        XCTAssertEqual(entries.first?.budget?.carriesOver, true)
        XCTAssertEqual(entries.first?.budget?.carryOverspend, false)
        XCTAssertEqual(entries.first?.budget?.carryOverStart, date(2026, 10, 1))
        XCTAssertEqual(entries.first?.budget?.showsDaily, true)
        XCTAssertEqual(entries.first?.account?.name, "錢包")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryCategory>()), Seed.expenseCategories.count + Seed.incomeCategories.count)
    }

    func testAccountGroups() throws {
        let salary = Account(name: "薪資", type: .bank, initialBalance: 1000, sortOrder: 0)
        let wallet = Account(name: "另一間", type: .bank, initialBalance: 50, sortOrder: 1)
        let travel = Account(name: "旅遊", type: .bank, initialBalance: 2000, sortOrder: 2)
        salary.groupName = "甲銀行"
        travel.groupName = "甲銀行"
        [salary, wallet, travel].forEach(context.insert)

        let items = AccountListItem.items(for: [salary, wallet, travel])
        XCTAssertEqual(items.map(\.id), ["group-甲銀行", wallet.id.uuidString])
        guard case .group(_, let members) = items[0] else { return XCTFail("not a group") }
        XCTAssertEqual(members.map(\.name), ["薪資", "旅遊"])
        XCTAssertEqual(salary.fullName, "甲銀行・薪資")
        XCTAssertEqual(wallet.fullName, "另一間")

        // Same currency: totals in it. Mixed: in TWD at the saved rate.
        XCTAssertEqual(AccountListItem.total(of: members).amount, 3000)
        XCTAssertEqual(AccountListItem.total(of: members).currency, "TWD")
        let yen = Account(name: "日圓", type: .bank, initialBalance: 1000)
        yen.currency = "JPY"
        Currency.setRate(0.2, for: "JPY")
        XCTAssertEqual(AccountListItem.total(of: [yen]).amount, 1000)
        XCTAssertEqual(AccountListItem.total(of: [yen]).currency, "JPY")
        XCTAssertEqual(AccountListItem.total(of: [salary, yen]).amount, 1200, accuracy: 0.001)
        XCTAssertEqual(AccountListItem.total(of: [salary, yen]).currency, "TWD")

        // Survives a backup round trip.
        let data = try BackupFile.encoder.encode(try BackupFile(context: context))
        try BackupFile.decoder.decode(BackupFile.self, from: data).restore(into: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Account>()).first { $0.name == "旅遊" }?.groupName, "甲銀行")
    }

    func testMultiCurrency() throws {
        Seed.insertDefaultsIfNeeded(context)
        let food = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryCategory>()).first { $0.name == "食物" })
        let card = Account(name: "甲銀行", type: .creditCard)
        let yen = Account(name: "日圓現金", type: .cash)
        yen.currency = "JPY"
        context.insert(card)
        context.insert(yen)

        // TWD 2,100 → ¥10,000 as typed: no conversion, and the yen rate becomes 0.21.
        let exchange = EntryService.add(kind: .transfer, amount: 2100, category: nil, account: card, toAccount: yen, in: context)
        exchange.setAmount(2100, toAmount: 10_000)
        XCTAssertEqual(exchange.toAmount, 10_000)
        XCTAssertEqual(yen.balance, 10_000)
        XCTAssertEqual(card.balance, -2100)
        XCTAssertEqual(Currency.rate("JPY"), 0.21, accuracy: 0.000001)

        // Spending from the yen account is in yen; totals use the rate recorded then.
        let cash = EntryService.add(kind: .expense, amount: 500, category: food, account: yen, in: context)
        XCTAssertEqual(cash.currency, "JPY")
        XCTAssertEqual(cash.rate, 0.21, accuracy: 0.000001)
        XCTAssertEqual(cash.baseAmount, 105, accuracy: 0.001)
        XCTAssertEqual(yen.balance, 9_500)
        XCTAssertEqual(Money.string(1200, currency: "JPY"), "¥1,200")

        // Survives a backup round trip.
        let data = try BackupFile.encoder.encode(try BackupFile(context: context))
        try BackupFile.decoder.decode(BackupFile.self, from: data).restore(into: context)
        let restored = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(try context.fetch(FetchDescriptor<Account>()).first { $0.name == "日圓現金" }?.currency, "JPY")
        XCTAssertEqual(restored.first { $0.kind == .transfer }?.toAmount, 10_000)
        XCTAssertEqual(restored.first { $0.currency == "JPY" }?.rate ?? 0, 0.21, accuracy: 0.000001)
    }

    /// Restores a real converted MOZE backup when MOZE_BACKUP_JSON points at one
    /// (run with TEST_RUNNER_MOZE_BACKUP_JSON=<path>); skipped otherwise.
    func testRestoreConvertedMozeBackup() throws {
        guard let path = ProcessInfo.processInfo.environment["MOZE_BACKUP_JSON"] else {
            throw XCTSkip("MOZE_BACKUP_JSON not set")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        try BackupFile.decoder.decode(BackupFile.self, from: data).restore(into: context)

        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
        for a in accounts where !a.isArchived {
            print("BALANCE \(a.name) \(a.type.rawValue) \(Money.plain(a.balance))")
        }
        for b in try context.fetch(FetchDescriptor<Budget>()) where !b.isArchived {
            print("BUDGET \(b.name) \(b.currentInterval.shortLabel) \(Money.plain(b.currentSpent)) / \(b.amount.map(Money.plain) ?? "-")")
        }
        print("ENTRIES \(try context.fetchCount(FetchDescriptor<Entry>()))")
    }

    // MARK: Entry helpers

    func testSuggestedBudgetFollowsCategory() throws {
        let lunch = EntryCategory(name: "午餐", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let budget = Budget(name: "lunch", amount: 750, period: .weekly)
        context.insert(lunch)
        context.insert(budget)
        EntryService.add(kind: .expense, amount: 120, category: lunch, account: nil, budget: budget, in: context)
        XCTAssertEqual(EntryService.suggestedBudget(for: lunch)?.name, "lunch")
        budget.isArchived = true
        XCTAssertNil(EntryService.suggestedBudget(for: lunch))
        XCTAssertEqual(lunch.useCount, 1)
    }

    func testSuggestedBudgetByTimeOfDay() throws {
        let food = EntryCategory(name: "食物", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let ride = EntryCategory(name: "交通", symbol: "scooter", colorHex: "#fff", kind: .expense)
        let lunch = Budget(name: "lunch", amount: 750, period: .weekly)
        let dinner = Budget(name: "Dinner", amount: 1250, period: .weekly)
        let holiday = Budget(name: "holiday", amount: 2000, period: .weekly)
        for m in [food, ride] { context.insert(m) }
        for b in [lunch, dinner, holiday] { context.insert(b) }
        // Weekdays (Mon 10/19 – Fri 10/23): lunch at noon, dinner at 19:00, rides at noon without a budget.
        for d in 19...23 {
            EntryService.add(kind: .expense, amount: 100, date: date(2026, 10, d, 12), category: food, account: nil, budget: lunch, in: context)
            EntryService.add(kind: .expense, amount: 200, date: date(2026, 10, d, 19), category: food, account: nil, budget: dinner, in: context)
            EntryService.add(kind: .expense, amount: 50, date: date(2026, 10, d, 12), category: ride, account: nil, in: context)
        }
        // Weekend (Sat 10/24, Sun 10/25): everything on holiday.
        for d in 24...25 {
            EntryService.add(kind: .expense, amount: 300, date: date(2026, 10, d, 12), category: food, account: nil, budget: holiday, in: context)
        }
        let recent = try context.fetch(FetchDescriptor<Entry>())
        func suggest(_ c: EntryCategory?, _ day: Int, _ hour: Int) -> String? {
            EntryService.suggestedBudget(for: c, at: date(2026, 10, day, hour), recent: recent)?.name
        }
        XCTAssertEqual(suggest(food, 26, 12), "lunch", "Monday noon")
        XCTAssertEqual(suggest(food, 26, 19), "Dinner", "Monday evening")
        XCTAssertEqual(suggest(food, 31, 12), "holiday", "Saturday noon")
        XCTAssertNil(suggest(ride, 26, 12), "rides at noon have no budget")
        XCTAssertEqual(suggest(nil, 26, 19), "Dinner", "no category yet: time alone")
        dinner.isArchived = true
        XCTAssertNotEqual(suggest(food, 26, 19), "Dinner", "archived budgets are never suggested")
    }

    func testBudgetRulesComeFirst() throws {
        UserDefaults.standard.removeObject(forKey: "budgetRulesSeeded")
        let food = EntryCategory(name: "食物", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let home = EntryCategory(name: "家庭", symbol: "house", colorHex: "#fff", kind: .expense)
        let me = EntryCategory(name: "個人", symbol: "person", colorHex: "#fff", kind: .expense)
        let play = EntryCategory(name: "玩樂", symbol: "gamecontroller", colorHex: "#fff", kind: .expense)
        for c in [food, home, me, play] { context.insert(c) }
        let names = ["lunch", "Dinner", "holiday", "Claim", "生活", "fun"]
        for n in names { context.insert(Budget(name: n, amount: nil, period: .monthly)) }
        // History says noon food is 生活; the rule should still win.
        let living = try XCTUnwrap(try context.fetch(FetchDescriptor<Budget>()).first { $0.name == "生活" })
        EntryService.add(kind: .expense, amount: 100, date: date(2026, 10, 26, 12), category: food, account: nil, budget: living, in: context)

        Seed.insertDefaultRulesIfNeeded(context)
        let rules = try context.fetch(FetchDescriptor<BudgetRule>())
        XCTAssertEqual(rules.count, 6)
        Seed.insertDefaultRulesIfNeeded(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetRule>()), 6, "seeds only once")

        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let recent = try context.fetch(FetchDescriptor<Entry>())
        func suggest(_ c: EntryCategory?, _ day: Int, _ h: Int, _ m: Int = 0) -> String? {
            let at = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
            return EntryService.suggestedBudget(for: c, at: at, recent: recent, rules: rules, budgets: budgets)?.name
        }
        XCTAssertEqual(suggest(food, 2, 7), "lunch", "Monday 07:00")
        XCTAssertEqual(suggest(food, 2, 12), "lunch")
        XCTAssertEqual(suggest(food, 2, 16, 30), "Dinner")
        XCTAssertEqual(suggest(food, 2, 23, 59), "Dinner")
        XCTAssertEqual(suggest(food, 7, 12), "holiday", "Saturday")
        XCTAssertEqual(suggest(home, 7, 3), "Claim")
        XCTAssertEqual(suggest(me, 2, 9), "生活")
        XCTAssertEqual(suggest(play, 2, 21), "fun")
        XCTAssertNotEqual(suggest(food, 2, 5), "lunch", "05:00 is outside every food rule")

        // Archived budget: rule is skipped.
        try XCTUnwrap(budgets.first { $0.name == "fun" }).isArchived = true
        XCTAssertNotEqual(suggest(play, 2, 21), "fun")

        // Rules survive a backup round trip.
        let data = try BackupFile.encoder.encode(try BackupFile(context: context))
        try BackupFile.decoder.decode(BackupFile.self, from: data).restore(into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BudgetRule>()), 6)
    }

    func testQuickParser() {
        let p = QuickEntryParser(categoryNames: ["午餐", "晚餐"], accountNames: ["甲銀行 卡", "甲銀行"])
        XCTAssertEqual(p.parse("午餐 120 用甲銀行 卡"), .init(amount: 120, categoryName: "午餐", accountName: "甲銀行 卡", name: ""))
        XCTAssertEqual(p.parse("晚餐花了一百二十元").amount, 120)
        XCTAssertEqual(p.parse("便當 85").name, "便當")

        let withBudgets = QuickEntryParser(categoryNames: ["午餐", "晚餐"], accountNames: [], budgetNames: ["lunch", "午餐"])
        let r = withBudgets.parse("lunch 便當 90")
        XCTAssertEqual(r.budgetName, "lunch")
        XCTAssertEqual(r.name, "便當")
        // Budget named like a category keeps the category match.
        let same = withBudgets.parse("午餐 120")
        XCTAssertEqual(same.categoryName, "午餐")
        XCTAssertEqual(same.budgetName, "午餐")
    }

    func testNameSuggestions() {
        let lunch = EntryCategory(name: "午餐", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let market = EntryCategory(name: "超市", symbol: "cart", colorHex: "#fff", kind: .expense)
        [lunch, market].forEach(context.insert)
        for (name, cat, day) in [("便當", lunch, 1), ("便當", lunch, 5), ("全聯福利中心", market, 3),
                                 ("全家", lunch, 4), ("麵店", lunch, 6)] {
            context.insert(Entry(kind: .expense, amount: 100, date: date(2026, 10, day), name: name, category: cat))
        }
        let items = NameSuggester.build(from: (try? context.fetch(FetchDescriptor<Entry>())) ?? [])
        XCTAssertEqual(items.first { $0.name == "便當" }?.count, 2)

        // Empty query with a category: only that category's names, most recent first.
        XCTAssertEqual(NameSuggester.suggest("", in: items, kind: .expense, categoryID: market.id).map(\.name),
                       ["全聯福利中心"])
        XCTAssertEqual(NameSuggester.suggest("", in: items, kind: .expense, categoryID: lunch.id).map(\.name),
                       ["麵店", "便當", "全家"])

        // Prefix beats contains beats in-order characters.
        XCTAssertEqual(NameSuggester.suggest("全", in: items, kind: .expense, categoryID: nil).map(\.name).sorted(),
                       ["全家", "全聯福利中心"])
        XCTAssertEqual(NameSuggester.suggest("全中", in: items, kind: .expense, categoryID: nil).map(\.name), ["全聯福利中心"])
        XCTAssertTrue(NameSuggester.suggest("便當", in: items, kind: .expense, categoryID: nil).isEmpty) // exact match hidden
        XCTAssertTrue(NameSuggester.suggest("便", in: items, kind: .income, categoryID: nil).isEmpty)
    }

    func testNameSuggestionsAroundTimeOfDay() {
        let wallet = Account(name: "錢包", type: .cash)
        let card = Account(name: "甲銀行卡", type: .creditCard)
        let food = EntryCategory(name: "午餐", symbol: "fork.knife", colorHex: "#fff", kind: .expense)
        let lunchBudget = Budget(name: "lunch", amount: 750, period: .weekly)
        [wallet, card].forEach(context.insert)
        context.insert(food)
        context.insert(lunchBudget)
        func add(_ name: String, _ day: Int, _ hour: Int, _ minute: Int, account: Account, budget: Budget? = nil) {
            let d = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
            context.insert(Entry(kind: .expense, amount: 100, date: d, name: name, category: food, account: account, budget: budget))
        }
        add("便當", 20, 12, 10, account: wallet)
        add("便當", 26, 12, 40, account: card, budget: lunchBudget) // latest use: card + lunch budget
        add("麵店", 25, 13, 50, account: wallet)
        add("早餐店", 26, 8, 0, account: wallet)                       // outside ±90 min
        add("今天的", 28, 12, 0, account: wallet)                      // today: excluded
        add("太久以前", 1, 12, 30, account: wallet)                    // older than 14 days
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let items = NameSuggester.build(from: entries)

        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12, minute: 30))!
        let around = NameSuggester.aroundTime(noon, entries: entries, items: items, kind: .expense)
        XCTAssertEqual(around.map(\.name), ["便當", "麵店"])

        // The suggestion carries the latest entry's account and budget.
        XCTAssertEqual(around.first?.accountID, card.id)
        XCTAssertEqual(around.first?.budgetID, lunchBudget.id)
        XCTAssertEqual(around.first?.categoryID, food.id)
    }

    func testCalculator() {
        XCTAssertEqual(Calculator.evaluate("120+35×2"), 190)
        XCTAssertEqual(Calculator.evaluate("50−20+"), 30)
    }

    func testCarrierCode39() {
        // Every Code 39 pattern has 9 elements, exactly 3 wide, and no two are the same.
        for (ch, p) in Code39.patterns {
            XCTAssertEqual(p.count, 9, "\(ch)")
            XCTAssertEqual(p.filter { $0 == "w" }.count, 3, "\(ch)")
        }
        XCTAssertEqual(Set(Code39.patterns.values).count, Code39.patterns.count)
        // "*" start: bar n, space w, bar n, bar n w... = 1 3 1 1 3 1 3 1 1.
        let widths = Code39.widths(for: "/ABC1234")!
        XCTAssertEqual(Array(widths.prefix(9)), [1, 3, 1, 1, 3, 1, 3, 1, 1])
        XCTAssertEqual(widths.count, 10 * 9 + 9)               // start + 8 chars + stop, gaps between
        XCTAssertEqual(widths.reduce(0, +), 10 * 15 + 9)
        XCTAssertNil(Code39.widths(for: "abc"))

        XCTAssertEqual(Carrier.normalized(" abc1234 "), "/ABC1234")
        XCTAssertTrue(Carrier.isValid("/AB.+-12"))
        XCTAssertFalse(Carrier.isValid("/ABC123"))
        XCTAssertFalse(Carrier.isValid("/ABC12#4"))
    }

    func testGetCarrierIntent() async throws {
        let saved = Carrier.number
        defer { Carrier.number = saved }
        Carrier.number = "/ABC1234"
        let result = try await GetCarrierIntent().perform()
        XCTAssertEqual(result.value, "/ABC1234")
        Carrier.number = nil
        do { _ = try await GetCarrierIntent().perform(); XCTFail("expected an error") } catch {}
    }
}
