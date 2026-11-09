import XCTest

/// Walks through the main flows and attaches a screenshot of each screen.
final class BudgetAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func press(_ keys: String...) {
        for k in keys { app.buttons["key-\(k)"].tap() }
    }

    /// Choosing a category opens the keyboard on the name; close it to reach the keypad.
    private func closeKeyboard() {
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) { app.textFields["名稱"].typeText("\n") }
    }

    /// Picks moze-restore.json from the app's Documents folder in the real file picker
    /// (copy it there with simctl first); skipped if the picker doesn't list it.
    func testRestoreThroughFilePicker() throws {
        app.buttons["帳戶"].firstMatch.tap()
        app.buttons["設定、分類與備份"].firstMatch.tap()
        app.buttons["從備份還原"].tap()

        let any = app.descendants(matching: .any)
        let file = any.matching(NSPredicate(format: "label CONTAINS 'moze-restore'")).firstMatch
        if !file.waitForExistence(timeout: 4) {
            let onPhone = any.matching(NSPredicate(format: "label == '我的 iPhone' OR label == 'On My iPhone'")).firstMatch
            if !onPhone.waitForExistence(timeout: 2) {
                any.matching(NSPredicate(format: "label == '瀏覽' OR label == 'Browse'")).firstMatch.tap()
            }
            if onPhone.waitForExistence(timeout: 4) { onPhone.tap() }
            let folder = any.matching(NSPredicate(format: "label CONTAINS '記帳本'")).firstMatch
            if folder.waitForExistence(timeout: 4) { folder.tap() }
        }
        snapshot("picker-1")
        guard file.waitForExistence(timeout: 6) else { throw XCTSkip("moze-restore.json not listed in picker") }
        file.tap()

        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '還原 '")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "restore confirmation did not appear after picking")
        confirm.tap()
        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '已還原備份'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "restore did not finish")
        snapshot("picker-2-done")
    }

    /// Restores moze-restore.json listed from the app's Documents folder (copy it there with
    /// simctl first); skipped if it isn't there.
    func testRestoreFromAppFolder() throws {
        app.buttons["帳戶"].firstMatch.tap()
        app.buttons["設定、分類與備份"].firstMatch.tap()
        let row = app.buttons["還原「moze-restore」"]
        guard row.waitForExistence(timeout: 5) else { throw XCTSkip("moze-restore.json not in Documents") }
        snapshot("folder-1-settings")
        row.tap()

        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '還原 '")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "restore confirmation did not appear")
        confirm.tap()
        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '已還原備份'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "restore did not finish")
        snapshot("folder-2-done")
        app.buttons["好"].tap()
        app.buttons["明細"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["$152,216"].waitForExistence(timeout: 5), "October income missing after restore")
    }

    /// Restores the backup at RESTORE_BACKUP_JSON (pass TEST_RUNNER_RESTORE_BACKUP_JSON=<path>)
    /// through the same path as picking it in Files; skipped otherwise.
    func testRestoreBackup() throws {
        guard let path = ProcessInfo.processInfo.environment["RESTORE_BACKUP_JSON"] else {
            throw XCTSkip("RESTORE_BACKUP_JSON not set")
        }
        app.terminate()
        app.launchArguments += ["-uitestRestorePath", path]
        app.launch()
        app.buttons["帳戶"].firstMatch.tap()
        app.buttons["設定、分類與備份"].firstMatch.tap()

        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '還原 '")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "restore confirmation did not appear")
        snapshot("restore-2-confirm")
        confirm.tap()

        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '已還原備份'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "restore did not finish")
        snapshot("restore-3-done")
        app.buttons["好"].tap()
        snapshot("restore-4-accounts")
        app.buttons["明細"].firstMatch.tap()
        snapshot("restore-5-home")
    }

    private func addBudget(_ name: String, amount: String) {
        app.buttons["新增預算"].tap()
        let field = app.textFields["名稱，例如 午餐"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name)
        let amountField = app.textFields["金額"]
        amountField.tap(); amountField.typeText(amount)
        app.buttons["每週"].tap()
        app.buttons["儲存"].tap()
    }

    func testNameSuggestionAndBudgetTransfer() {
        // First entry with a name.
        app.buttons["記一筆"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
        app.buttons["category-食物"].tap()
        let name = app.textFields["名稱"]
        name.tap(); name.typeText("便當\n")
        press("1", "2", "0", "✓")

        // Second entry: choosing the category alone shows its recent names; tapping one fills it in.
        app.buttons["記一筆"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
        app.buttons["category-食物"].tap()
        let suggestion = app.buttons.matching(identifier: "name-suggestion").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "no name suggestion")
        snapshot("n1-suggestion")
        suggestion.tap()
        XCTAssertEqual(name.value as? String, "便當")
        press("9", "0", "✓")
        snapshot("n2-home")
        XCTAssertFalse(app.staticTexts["可用預算"].exists)

        // Two budgets, then move 200 from lunch to Dinner.
        app.buttons["預算"].firstMatch.tap()
        addBudget("lunch", amount: "750")
        addBudget("Dinner", amount: "1250")
        app.buttons["轉移預算"].tap()
        let amountField = app.textFields["金額"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap(); amountField.typeText("200")
        snapshot("n3-transfer")
        app.buttons["轉移"].tap()
        XCTAssertTrue(app.staticTexts["$550"].waitForExistence(timeout: 5), "lunch not reduced")
        XCTAssertTrue(app.staticTexts["$1,450"].exists, "Dinner not increased")
        snapshot("n4-budgets")
        // How the amount adds up shows on the detail page only.
        let breakdown = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '本期 '")).firstMatch
        XCTAssertFalse(breakdown.exists, "breakdown shown in the list")
        app.staticTexts["lunch"].firstMatch.tap()
        XCTAssertTrue(breakdown.waitForExistence(timeout: 5), "breakdown missing on the detail page")
        app.navigationBars.buttons.firstMatch.tap()

        // Delete it from the transfer history; both budgets go back.
        app.buttons["轉移紀錄"].tap()
        let delete = app.buttons["刪除轉移"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        snapshot("n5-history")
        delete.tap()
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["還沒有預算轉移"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["$750"].waitForExistence(timeout: 5), "lunch not restored")
        XCTAssertTrue(app.staticTexts["$1,250"].exists, "Dinner not restored")
    }

    func testSplitAndSettleClaim() {
        // A Claim budget without a limit.
        app.buttons["預算"].firstMatch.tap()
        app.buttons["新增預算"].tap()
        let budgetName = app.textFields["名稱，例如 午餐"]
        XCTAssertTrue(budgetName.waitForExistence(timeout: 5))
        budgetName.tap(); budgetName.typeText("Claim")
        app.buttons["儲存"].tap()

        // Pay 950 for dinner, then split 400 off for a friend.
        app.buttons["記一筆"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
        app.buttons["category-食物"].tap()
        closeKeyboard()
        press("9", "5", "0")
        let name = app.textFields["名稱"]
        name.tap(); name.typeText("燒肉\n")
        press("✓")
        app.buttons["明細"].firstMatch.tap()
        let row = app.staticTexts["燒肉"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["拆分"].firstMatch.tap()
        let part = app.textFields["拆出金額"]
        XCTAssertTrue(part.waitForExistence(timeout: 5))
        part.tap(); part.typeText("400")
        snapshot("s1-split")
        app.navigationBars["拆分支出"].buttons["拆分"].tap()
        XCTAssertTrue(app.staticTexts["$550"].waitForExistence(timeout: 5), "original not reduced")
        XCTAssertTrue(app.staticTexts["$400"].exists, "split part missing")
        snapshot("s2-home")

        // Friend pays back: settle it from the Claim budget.
        app.buttons["預算"].firstMatch.tap()
        app.staticTexts["Claim"].firstMatch.tap()
        let settle = app.buttons["已還款"].firstMatch
        XCTAssertTrue(settle.waitForExistence(timeout: 5))
        snapshot("s3-claim")
        settle.tap()
        let confirm = app.navigationBars["已還款"].buttons["確認"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snapshot("s4-settle")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["沒有待收的款項"].waitForExistence(timeout: 5))
        app.buttons["明細"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["還款"].waitForExistence(timeout: 5), "income not recorded")
        snapshot("s5-home")
    }

    func testCarrierBarcodeAndCopy() {
        app.buttons["帳戶"].firstMatch.tap()
        app.swipeUp()
        app.buttons["設定、分類與備份"].firstMatch.tap()
        app.buttons["載具"].tap()
        let field = app.textFields["載具號碼"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // An empty field reports its placeholder as the value, so always clear and retype.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "abc1234")
        XCTAssertTrue(app.otherElements["載具條碼 /ABC1234"].waitForExistence(timeout: 5)
                      || app.staticTexts["/ABC1234"].exists, "barcode not shown")
        snapshot("c1-settings")

        // What tapping the widget does: barcode full screen, number copied.
        app.open(URL(string: "budgetapp://carrier")!)
        XCTAssertTrue(app.buttons["已複製載具號碼"].waitForExistence(timeout: 5), "not copied")
        snapshot("c2-popup")
        // Tapping outside the window closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(app.buttons["已複製載具號碼"].waitForNonExistence(timeout: 5), "popup did not close")
    }

    func testWidgetLinkOpensEditorOnCategory() {
        // What tapping 交通 on the widget does.
        app.open(URL(string: "budgetapp://add?kind=expense&category=交通")!)
        XCTAssertTrue(app.buttons["key-✓"].waitForExistence(timeout: 5), "editor did not open")
        closeKeyboard()
        snapshot("w1-editor")
        press("8", "5", "✓")
        XCTAssertTrue(app.staticTexts["交通"].waitForExistence(timeout: 5), "entry not saved under 交通")
        XCTAssertTrue(app.staticTexts["$85"].exists)
    }

    private func addExpense(_ keys: [String], account: String? = nil) {
        app.buttons["記一筆"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
        app.buttons["category-食物"].tap()
        closeKeyboard()
        for k in keys { app.buttons["key-\(k)"].tap() }
        if let account {
            app.buttons["錢包"].firstMatch.tap()
            XCTAssertTrue(app.buttons[account].firstMatch.waitForExistence(timeout: 3))
            snapshot("e-account-list")
            app.buttons[account].firstMatch.tap()
        }
        press("✓")
    }

    func testStatementSortingAndCollapse() {
        // A credit card closing on the 1st.
        app.buttons["帳戶"].firstMatch.tap()
        app.buttons["新增帳戶"].tap()
        let name = app.textFields["名稱，例如 我的信用卡"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("甲銀行")
        app.buttons["類型"].firstMatch.tap()
        app.buttons["信用卡"].firstMatch.tap()
        app.switches["出帳日"].firstMatch.switches.firstMatch.tap()
        snapshot("c1-card-editor")
        app.buttons["儲存"].tap()

        addExpense(["3", "0", "0"], account: "甲銀行")
        addExpense(["2", "4", "0"])

        // Statement: move one item to the next bill.
        app.buttons["帳戶"].firstMatch.tap()
        app.staticTexts["甲銀行"].firstMatch.tap()
        let bill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '帳單明細'")).firstMatch
        XCTAssertTrue(bill.waitForExistence(timeout: 5))
        bill.tap()
        // Within a week after closing, the page opens on the bill that just closed.
        if !app.staticTexts["$540"].waitForExistence(timeout: 3) { app.buttons["下一期"].tap() }
        XCTAssertTrue(app.staticTexts["$540"].waitForExistence(timeout: 5), "statement total wrong")
        snapshot("c2-statement")
        app.buttons["移到下期"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["$540"].waitForExistence(timeout: 2))
        app.buttons["下一期"].tap()
        XCTAssertTrue(app.staticTexts["從上期移入"].waitForExistence(timeout: 5))
        snapshot("c3-next-statement")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        // Net worth card collapses to just the number.
        let collapse = app.buttons["收合淨資產"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()
        XCTAssertTrue(app.buttons["展開淨資產"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["收支"].exists, "chart still visible")
        snapshot("c4-collapsed")
        app.buttons["展開淨資產"].tap()
        XCTAssertTrue(app.buttons["收支"].waitForExistence(timeout: 5))

        // Sorting lives in settings.
        app.swipeUp()
        app.buttons["設定、分類與備份"].firstMatch.tap()
        app.swipeUp()
        app.buttons["帳戶排序"].tap()
        XCTAssertTrue(app.staticTexts["甲銀行"].waitForExistence(timeout: 5))
        snapshot("c5-account-order")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["預算排序"].tap()
        XCTAssertTrue(app.navigationBars["預算排序"].waitForExistence(timeout: 5))
    }

    /// Runs on the simulator's real store (a copy of phone data); pass TEST_RUNNER_REAL_STORE=1.
    func testAccountHistoryRange() throws {
        guard ProcessInfo.processInfo.environment["REAL_STORE"] == "1" else { throw XCTSkip("REAL_STORE not set") }
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        app.buttons["帳戶"].firstMatch.tap()
        app.staticTexts["Wallet"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["顯示範圍"].waitForExistence(timeout: 5))
        snapshot("h1-top")
        let more = app.buttons["再載入一個月"]
        for _ in 0..<15 where !more.isHittable { app.swipeUp() }
        snapshot("h2-bottom")
        // Default is the last 2 months, so the month before those appears after loading one more.
        let cal = Calendar.current
        let older = cal.date(byAdding: .month, value: -2, to: .now)!
        let title = "\(cal.component(.year, from: older))年\(cal.component(.month, from: older))月"
        XCTAssertFalse(app.staticTexts[title].exists)
        more.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "\(title) not loaded")
        snapshot("h3-loaded")
    }

    func testColorTheme() {
        addExpense(["1", "2", "0"])
        func openThemes() {
            app.buttons["帳戶"].firstMatch.tap()
            app.swipeUp()
            app.buttons["設定、分類與備份"].firstMatch.tap()
            app.buttons["主題顏色"].tap()
        }
        func choose(_ label: String) {
            let swatch = app.buttons[label]
            XCTAssertTrue(swatch.waitForExistence(timeout: 5), "\(label) missing")
            swatch.tap()
        }
        func shoot(_ prefix: String) {
            app.buttons["明細"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["$120"].waitForExistence(timeout: 5), "data gone after theme change")
            snapshot("\(prefix)-home")
            app.buttons["帳戶"].firstMatch.tap()
            snapshot("\(prefix)-accounts")
            app.buttons["記一筆"].firstMatch.tap()
            XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
            app.buttons["錢包"].firstMatch.tap()
            snapshot("\(prefix)-editor")
            app.buttons["錢包"].firstMatch.tap()
            app.buttons["xmark"].firstMatch.tap()
        }

        // Light: 莓果.
        openThemes()
        app.buttons["淺色"].tap()
        choose("淺色主題 卡其")
        // Applies in place: still on this page.
        XCTAssertTrue(app.navigationBars["主題顏色"].waitForExistence(timeout: 3), "left the theme page")
        snapshot("t1-light-picker")
        app.navigationBars.buttons.firstMatch.tap()
        shoot("t2-light")

        // Dark: 酒紅.
        openThemes()
        app.buttons["深色"].tap()
        choose("深色主題 卡其")
        XCTAssertTrue(app.navigationBars["主題顏色"].waitForExistence(timeout: 3), "left the theme page")
        snapshot("t3-dark-picker")
        app.navigationBars.buttons.firstMatch.tap()
        shoot("t4-dark")

        // Back to the defaults so other tests see the usual colors.
        openThemes()
        app.buttons["跟隨系統"].tap()
        choose("淺色主題 天空")
        choose("深色主題 夜空")
        app.navigationBars.buttons.firstMatch.tap()
    }

    func testCalendarSlidesBetweenMonths() {
        app.buttons["明細"].firstMatch.tap()
        let cal = Calendar.current
        // The title is the selected day; it moves a month with each swipe, keeping the day number.
        func title(_ offset: Int) -> String {
            let today = cal.startOfDay(for: .now)
            let first = cal.date(from: cal.dateComponents([.year, .month], from: today))!
            let month = cal.date(byAdding: .month, value: offset, to: first)!
            let length = cal.range(of: .day, in: .month, for: month)!.count
            let d = cal.date(byAdding: .day, value: min(cal.component(.day, from: today), length) - 1, to: month)!
            return String(format: "%04d/%02d/%02d", cal.component(.year, from: d), cal.component(.month, from: d),
                          cal.component(.day, from: d))
        }
        // Swipe across the middle of the calendar (neighbouring months' cards sit off screen).
        func swipe(left: Bool) {
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.32))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.32))
            a.press(forDuration: 0.05, thenDragTo: b)
        }
        XCTAssertTrue(app.staticTexts[title(0)].waitForExistence(timeout: 5))

        swipe(left: true)
        XCTAssertTrue(app.staticTexts[title(1)].waitForExistence(timeout: 3), "swipe left did not go to next month")
        snapshot("s2-next")

        swipe(left: false)
        XCTAssertTrue(app.staticTexts[title(0)].waitForExistence(timeout: 3))
        swipe(left: false)
        XCTAssertTrue(app.staticTexts[title(-1)].waitForExistence(timeout: 3), "swipe right did not go back")

        // The arrow buttons page too.
        app.buttons["chevron.right"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[title(0)].waitForExistence(timeout: 3), "arrow did not page")
    }

    func testLongPressDeletesRecord() {
        addExpense(["1", "2", "0"])
        app.buttons["明細"].firstMatch.tap()
        let row = app.buttons["day-entry"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)
        let delete = app.buttons["刪除"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "no delete in the long-press menu")
        snapshot("l1-menu")
        delete.tap()
        XCTAssertTrue(app.staticTexts["這天沒有紀錄"].waitForExistence(timeout: 5), "record not deleted")
    }

    func testAccountGroupTotal() {
        func addAccount(_ name: String, group: String, balance: String) {
            app.buttons["新增帳戶"].tap()
            let field = app.textFields["名稱，例如 我的信用卡"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            let groupField = app.textFields["銀行或群組"]
            groupField.tap(); groupField.typeText(group)
            let balanceField = app.textFields["0"]
            balanceField.tap(); balanceField.typeText(balance)
            app.buttons["儲存"].firstMatch.tap()
        }
        app.buttons["帳戶"].firstMatch.tap()
        addAccount("薪資", group: "甲銀行", balance: "1000")
        addAccount("旅遊", group: "甲銀行", balance: "2000")

        let group = app.buttons["group-甲銀行"]
        XCTAssertTrue(group.waitForExistence(timeout: 5), "group not listed")
        XCTAssertTrue(app.staticTexts["$3,000"].exists, "group total missing")
        app.swipeUp() // The list loads rows as they come on screen.
        XCTAssertTrue(app.staticTexts["旅遊"].waitForExistence(timeout: 5), "account not under its group")
        snapshot("g1-group")

        // Folding hides its accounts and keeps the total.
        group.tap()
        XCTAssertTrue(app.staticTexts["旅遊"].waitForNonExistence(timeout: 5), "still expanded")
        XCTAssertTrue(app.staticTexts["$3,000"].exists)
        group.tap()
        XCTAssertTrue(app.staticTexts["旅遊"].waitForExistence(timeout: 5), "did not expand")

        // A transfer between long account names keeps its tag on one line.
        addAccount("信用卡繳款專用", group: "很長的銀行名稱", balance: "500")
        app.buttons["記一筆"].firstMatch.tap()
        app.buttons["轉帳"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '從'")).firstMatch.tap()
        app.buttons["很長的銀行名稱・信用卡繳款專用"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '到'")).firstMatch.tap()
        app.buttons["甲銀行・旅遊"].firstMatch.tap()
        press("1", "0", "✓")
        app.buttons["明細"].firstMatch.tap()
        let tag = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '→'")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        XCTAssertLessThan(tag.frame.height, 22, "transfer tag wraps onto two lines")
        snapshot("g2-transfer-tag")
    }

    func testDailyBudgetOption() {
        app.buttons["預算"].firstMatch.tap()
        addBudget("Dinner", amount: "1250")

        // Only the budget with the option turned on shows it.
        app.buttons["新增預算"].tap()
        let field = app.textFields["名稱，例如 午餐"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("lunch")
        let amountField = app.textFields["金額"]
        amountField.tap(); amountField.typeText("700")
        app.buttons["每週"].tap()
        let toggle = app.switches["顯示每日可用"]
        if !toggle.isHittable { app.swipeUp() }
        toggle.switches.firstMatch.tap()
        app.buttons["儲存"].tap()

        let daily = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '今日 '"))
        XCTAssertTrue(daily.firstMatch.waitForExistence(timeout: 5), "daily amount not shown")
        XCTAssertEqual(daily.count, 1, "shown on a budget without the option")
        let before = daily.firstMatch.label
        XCTAssertTrue(before.hasPrefix("今日 0 / "), before)

        // Spending today fills today's bar without changing today's amount.
        app.buttons["記一筆"].firstMatch.tap()
        app.buttons["category-食物"].tap()
        closeKeyboard()
        let chips = app.buttons.matching(NSPredicate(format: "label ENDSWITH '預算' OR label == 'Dinner' OR label == 'lunch'"))
        chips.firstMatch.tap()
        app.buttons["lunch"].firstMatch.tap()
        press("3", "5", "✓")
        // Same day's amount, only what's used changes.
        let after = app.staticTexts[before.replacingOccurrences(of: "今日 0 /", with: "今日 35 /")]
        XCTAssertTrue(after.waitForExistence(timeout: 5), "today's usage not updated, or today's amount changed")
        snapshot("d1-daily")
    }

    func testCancelFromKeyboard() {
        app.buttons["記一筆"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
        app.buttons["category-食物"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let cancel = app.buttons["取消紀錄"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3), "no cancel above the keyboard")
        snapshot("k1-keyboard-cancel")
        cancel.tap()
        XCTAssertTrue(app.buttons["key-✓"].waitForNonExistence(timeout: 5), "editor still open")
    }

    func testCrossCurrencyTransferAndSwap() {
        // A yen cash account.
        app.buttons["帳戶"].firstMatch.tap()
        app.buttons["新增帳戶"].tap()
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText("日圓現金")
        // The picker's label includes its value ("幣別, 新台幣 TWD").
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '幣別'")).firstMatch.tap()
        app.buttons["日圓 JPY"].firstMatch.tap()
        app.buttons["儲存"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["¥0"].waitForExistence(timeout: 5), "yen balance not shown")

        // Transfer: swap from/to.
        app.buttons["記一筆"].firstMatch.tap()
        app.buttons["轉帳"].firstMatch.tap()
        let from = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '從'")).firstMatch
        XCTAssertTrue(from.waitForExistence(timeout: 3))
        let before = from.label
        app.buttons["交換轉出轉入"].tap()
        XCTAssertNotEqual(from.label, before, "swap did nothing")
        app.buttons["交換轉出轉入"].tap()
        XCTAssertEqual(from.label, before)

        // 錢包 (TWD) → 日圓現金: type both amounts.
        let to = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '到'")).firstMatch
        if !to.label.contains("日圓現金") {
            to.tap()
            app.buttons["日圓現金"].firstMatch.tap()
        }
        press("2", "1", "0", "0")
        let arrived = app.textFields["轉入金額"]
        XCTAssertTrue(arrived.waitForExistence(timeout: 3), "no field for the yen that arrived")
        arrived.tap()
        arrived.typeText("10000")
        snapshot("m1-cross-currency-transfer")
        app.buttons["儲存"].firstMatch.tap()
        app.buttons["帳戶"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["¥10,000"].waitForExistence(timeout: 5), "yen balance not updated")
        snapshot("m2-accounts")
    }

    func testIconQuickActions() {
        // Items are registered when the app appears; long-press the icon on the home screen.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["記帳本"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.press(forDuration: 1.5)
        let income = springboard.buttons["記一筆收入"]
        XCTAssertTrue(income.waitForExistence(timeout: 5), "quick actions missing")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "q1-menu"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(springboard.buttons["記一筆支出"].exists)
        XCTAssertTrue(springboard.buttons["轉帳"].exists)
        XCTAssertTrue(springboard.buttons["轉移預算"].exists)
        income.tap()
        // Editor opens on 收入 with income categories.
        XCTAssertTrue(app.buttons["category-薪水"].waitForExistence(timeout: 5), "editor did not open on income")
        snapshot("q2-income-editor")
    }

    func testAddEntryAndBrowseTabs() {
        snapshot("1-home")

        app.buttons["記一筆"].firstMatch.tap()
        XCTAssertTrue(app.buttons["category-食物"].waitForExistence(timeout: 5))
        app.buttons["category-食物"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "keyboard did not open on the name")
        closeKeyboard()
        press("1", "2", "0", "+", "3", "5")
        snapshot("2-editor")
        press("✓")

        XCTAssertTrue(app.staticTexts["$155"].waitForExistence(timeout: 5))
        snapshot("3-home-with-entry")

        app.buttons["預算"].firstMatch.tap()
        app.buttons["新增預算"].tap()
        let name = app.textFields["名稱，例如 午餐"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("午餐")
        let amount = app.textFields["金額"]
        amount.tap()
        amount.typeText("750")
        app.buttons["每週"].tap()
        snapshot("4-budget-editor")
        app.buttons["儲存"].tap()
        XCTAssertTrue(app.staticTexts["$750"].waitForExistence(timeout: 5))
        snapshot("5-budgets")

        app.buttons["帳戶"].firstMatch.tap()
        snapshot("6-accounts")

        app.buttons["統計"].firstMatch.tap()
        snapshot("7-stats")
    }
}
