import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import WidgetKit

@main
struct BudgetAppApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { UIApplication.shared.shortcutItems = QuickAction.items }
        }
        .modelContainer(DataStore.container)
    }
}

/// Lets intents (Action Button, Shortcuts) and icon quick actions open screens.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var showAddEntry = false
    /// Kind the editor starts on when opened from outside (quick actions).
    var newEntryKind: EntryKind = .expense
    /// Category (ID or name) the editor starts on when opened from the widget.
    var newEntryCategory: String?
    var showBudgetTransfer = false
    /// Floating carrier barcode; `copyCarrier` when opened from the widget.
    var showCarrier = false
    var copyCarrier = false
    /// Credit card whose statement to show (from the closing-day notification).
    var statementAccountID: UUID?
    /// Day selected on the home calendar; new entries default to it.
    var preferredDate: Date?

    func openEditor(kind: EntryKind, category: String? = nil) {
        newEntryKind = kind
        newEntryCategory = category
        preferredDate = nil
        showAddEntry = true
    }
}

/// Items in the menu shown when long-pressing the app icon.
enum QuickAction: String {
    case expense, income, transfer, budgetTransfer

    static var items: [UIApplicationShortcutItem] {
        [
            item(.expense, "記一筆支出", "minus.circle"),
            item(.income, "記一筆收入", "plus.circle"),
            item(.transfer, "轉帳", "arrow.left.arrow.right"),
            item(.budgetTransfer, "轉移預算", "arrow.triangle.swap"),
        ]
    }

    private static func item(_ action: QuickAction, _ title: String, _ symbol: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: action.rawValue, localizedTitle: title, localizedSubtitle: nil,
                                  icon: UIApplicationShortcutIcon(systemImageName: symbol))
    }

    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) {
        let router = AppRouter.shared
        switch QuickAction(rawValue: item.type) {
        case .expense: router.openEditor(kind: .expense)
        case .income: router.openEditor(kind: .income)
        case .transfer: router.openEditor(kind: .transfer)
        case .budgetTransfer: router.showBudgetTransfer = true
        case nil: break
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Closing-day reminder tapped: open that card's statement.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = (response.notification.request.content.userInfo[StatementReminder.accountKey] as? String).flatMap(UUID.init)
        await MainActor.run { AppRouter.shared.statementAccountID = id }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Cold launch from a quick action.
        if let item = options.shortcutItem {
            Task { @MainActor in QuickAction.handle(item) }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // Quick action while the app is already running.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in QuickAction.handle(shortcutItem) }
        completionHandler(true)
    }
}

struct RootView: View {
    enum Tab: Hashable { case home, accounts, add, budgets, stats }

    @State private var tab: Tab = .home
    @State private var router = AppRouter.shared
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [Account]
    @AppStorage(AppTheme.lightKey, store: AppTheme.store) private var lightThemeID = AppTheme.light.id
    @AppStorage(AppTheme.darkKey, store: AppTheme.store) private var darkThemeID = AppTheme.dark.id
    @AppStorage(AppTheme.appearanceKey, store: AppTheme.store) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        tabs
            .tint(Color.accent)
            .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
            .onChange(of: lightThemeID + "|" + darkThemeID) { _, _ in
                ThemeChanges.shared.revision += 1
                WidgetCenter.shared.reloadAllTimelines()
            }
    }

    private var tabs: some View {
        TabView(selection: Binding(
            get: { tab },
            set: { newValue in
                // The middle tab is a button: open the editor and stay on the current tab.
                if newValue == .add {
                    router.newEntryKind = .expense
                    router.newEntryCategory = nil
                    router.showAddEntry = true
                } else {
                    tab = newValue
                }
            }
        )) {
            AccountsView()
                .tabItem { Label("帳戶", systemImage: "wallet.pass") }
                .tag(Tab.accounts)
            HomeView()
                .tabItem { Label("明細", systemImage: "calendar") }
                .tag(Tab.home)
            Color.clear
                .tabItem { Label("記一筆", systemImage: "plus.circle.fill") }
                .tag(Tab.add)
            BudgetsView()
                .tabItem { Label("預算", systemImage: "target") }
                .tag(Tab.budgets)
            StatsView()
                .tabItem { Label("統計", systemImage: "chart.pie") }
                .tag(Tab.stats)
        }
        .sheet(isPresented: $router.showAddEntry) {
            EntryEditor(entry: nil, initialDate: router.preferredDate, initialKind: router.newEntryKind,
                        initialCategory: router.newEntryCategory)
        }
        // Widget buttons open budgetapp://add?kind=…&category=….
        .onOpenURL { url in
            if url == Carrier.link {
                // Over any open sheet the popup would sit underneath, so close those first.
                router.showAddEntry = false
                router.showBudgetTransfer = false
                router.statementAccountID = nil
                router.copyCarrier = true
                router.showCarrier = true
                return
            }
            guard let link = QuickAddLink(url: url) else { return }
            router.openEditor(kind: EntryKind(rawValue: link.kind) ?? .expense, category: link.category)
        }
        .background {
            Color.clear.sheet(isPresented: Binding(get: { router.statementAccountID != nil },
                                                   set: { if !$0 { router.statementAccountID = nil } })) {
                if let account = accounts.first(where: { $0.id == router.statementAccountID }) {
                    NavigationStack {
                        StatementView(account: account)
                            .toolbar { Button("完成") { router.statementAccountID = nil } }
                    }
                }
            }
        }
        .onAppear {
            WidgetSync.publish(context)
            StatementReminder.reschedule(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { WidgetSync.publish(context) }
        }
        .onChange(of: router.showAddEntry) { _, showing in
            if !showing { WidgetSync.publish(context) }
        }
        // A second sheet needs its own host view, or SwiftUI only presents one of them.
        .background {
            Color.clear.sheet(isPresented: $router.showBudgetTransfer) { BudgetTransferSheet(from: nil) }
        }
        .overlay {
            if router.showCarrier {
                CarrierPopup(copyOnAppear: router.copyCarrier) {
                    router.showCarrier = false
                    router.copyCarrier = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: router.showCarrier)
    }
}
