import SwiftUI
import SwiftData

@main
struct KnoWellApp: App {
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
                }
                clipboardImport.checkClipboardIfNeeded(shareImport: shareImport)
                AppLog.info("Scene became active", category: "Lifecycle")
            }
        }
    }

    @MainActor
    private func processShareWorkItems() async {
        SharedDedupeSync.rebuild(in: AppModelContainer.shared.mainContext)
        let hadPendingJob = ShareImportStore.hasPendingGenerationJob
        CardGenerationQueue.shared.ingestPendingShareJobsIfNeeded()
        shareImport.refreshAll()
        if hadPendingJob || shareImport.hasPendingImport {
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
