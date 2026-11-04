# 記帳本

A personal budgeting app for iOS, in Traditional Chinese. Built with SwiftUI, SwiftData, App Intents and WidgetKit. All data stays on the phone; the app doesn't use the network.

## Build

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Put your Apple team ID in `Config/Local.xcconfig`, then generate the project:

```bash
xcodegen generate
```

To install on your own device, change the bundle ID and App Group (`com.hongping.budgetapp`) in `project.yml`, the entitlements files, `BudgetApp/Support/Formatting.swift` and `Shared/QuickAdd.swift`.

## Tools

`tools/moze-import` converts a decoded MOZE backup into a backup file this app can restore.
