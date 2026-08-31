import SwiftUI
import SwiftData
import UIKit
import UserNotifications

final class KnoWellAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let identifier = response.notification.request.identifier
        let opensCreate =
            (userInfo["open"] as? String) == "create"
            || (userInfo["knowell"] as? String) == "share-inbox"
            || identifier.hasPrefix("knowell-share")
        guard opensCreate else { return }
        AppLog.info("tapped share notification id=\(identifier)", category: "Share")
        await MainActor.run {
            NotificationCenter.default.post(name: .shareInboxNotificationTapped, object: nil)
            AppTab.request(.create)
        }
    }
}

@main
struct KnoWellApp: App {
    @UIApplicationDelegateAdaptor(KnoWellAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shareImport = ShareImportCoordinator()
    private let clipboardImport = ClipboardImportCoordinator()
    @AppStorage("privacy.hasAccepted") private var hasAcceptedPrivacy = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasAcceptedPrivacy {
                    ContentView()
                        .environmentObject(shareImport)
                        .environment(ReviewSettingsStore.shared)
                        .environment(AppAccentThemeStore.shared)
                        .environment(CloudAIQuotaStore.shared)
                } else {
                    FirstLaunchGateView {
                        hasAcceptedPrivacy = true
                    }
                }
            }
                .onOpenURL { url in
                    if WeChatSignInService.handleOpenURL(url) {
                        return
                    }
                    if ShareImportService.handleIncomingURL(url) {
                        Task {
                            await processShareWorkItems()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .shareInboxNotificationTapped)) { _ in
                    Task {
                        await processShareWorkItems()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: AppAccentThemeStore.didChangeNotification)) { _ in
                    AppTabBarLiveChrome.apply()
                }
                .onAppear {
                    migratePrivacyAcceptanceIfNeeded()
                    APISettings.migrateToAppGroupIfNeeded()
                    WeChatSignInService.registerIfNeeded()
                    AppTabBarLiveChrome.apply()
                    AppLog.bootstrap()
                    Task {
                        await processShareWorkItems()
                        await DailyAutoBackupService.runIfNeeded(in: AppModelContainer.shared.mainContext)
                    }
                }
                .task {
                    guard hasAcceptedPrivacy else { return }
                    _ = await ShareExtensionNotifier.requestAuthorizationIfNeeded()
                }
                .onChange(of: hasAcceptedPrivacy) { _, accepted in
                    guard accepted else { return }
                    Task {
                        _ = await ShareExtensionNotifier.requestAuthorizationIfNeeded()
                    }
                }
        }
        .modelContainer(AppModelContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await processShareWorkItems()
                    await DailyAutoBackupService.runIfNeeded(in: AppModelContainer.shared.mainContext)
                    await CloudAIQuotaStore.shared.refresh()
                }
                clipboardImport.checkClipboardIfNeeded(shareImport: shareImport)
                AppLog.info("Scene became active", category: "Lifecycle")
            }
        }
    }

    @MainActor
    private func processShareWorkItems() async {
        SharedDedupeSync.rebuild(in: AppModelContainer.shared.mainContext)
        await CloudAIQuotaStore.shared.refresh()
        let hadPendingJob = ShareImportStore.hasPendingGenerationJob
        CardGenerationQueue.shared.ingestPendingShareJobsIfNeeded()
        shareImport.refreshAll()
        if hadPendingJob || shareImport.hasPendingImport {
            AppLog.info(
                "processShareWorkItems job=\(hadPendingJob) import=\(shareImport.hasPendingImport) inbox=\(shareImport.pendingInbox != nil)",
                category: "Share"
            )
            AppTab.request(.create)
        }
    }

    /// Returning installs skip the first-launch gate.
    private func migratePrivacyAcceptanceIfNeeded() {
        guard !hasAcceptedPrivacy else { return }
        let defaults = UserDefaults.standard
        let returningUser =
            defaults.object(forKey: "review.hasSeenScrollHint") != nil
            || defaults.object(forKey: "com.knowell.study.streak") != nil
            || defaults.object(forKey: "com.knowell.study.activity.v1") != nil
            || defaults.object(forKey: "review.hasSeenSwipeCoach") != nil
        if returningUser {
            hasAcceptedPrivacy = true
        }
    }
}

#if canImport(UIKit)
/// UIAppearance only affects future bars; poke the live TabView bar so selected tint updates.
enum AppTabBarLiveChrome {
    static func apply() {
        AppTabBarChrome.apply()
        let snapshot = AppTabBarChrome.makeSnapshot()
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = snapshot.accent
                apply(snapshot, to: window.rootViewController)
                apply(snapshot, toViewsIn: window)
            }
        }
    }

    private static func apply(_ snapshot: AppTabBarChrome.Snapshot, to viewController: UIViewController?) {
        guard let viewController else { return }
        if let tab = viewController as? UITabBarController {
            apply(snapshot, toTabBar: tab.tabBar)
        }
        viewController.children.forEach { apply(snapshot, to: $0) }
        apply(snapshot, to: viewController.presentedViewController)
    }

    private static func apply(_ snapshot: AppTabBarChrome.Snapshot, toViewsIn root: UIView) {
        if let bar = root as? UITabBar {
            apply(snapshot, toTabBar: bar)
        }
        root.subviews.forEach { apply(snapshot, toViewsIn: $0) }
    }

    private static func apply(_ snapshot: AppTabBarChrome.Snapshot, toTabBar bar: UITabBar) {
        bar.standardAppearance = snapshot.appearance
        bar.scrollEdgeAppearance = snapshot.appearance
        bar.tintColor = snapshot.accent
        bar.unselectedItemTintColor = snapshot.muted
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
    }
}
#endif
