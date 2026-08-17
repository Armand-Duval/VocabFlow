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
                .onAppear {
                    migratePrivacyAcceptanceIfNeeded()
                    APISettings.migrateToAppGroupIfNeeded()
                    WeChatSignInService.registerIfNeeded()
                    AppTabBarChrome.apply()
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
