import SwiftUI
import SwiftData

@main
struct KnoWellApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shareImport = ShareImportCoordinator()
    private let clipboardImport = ClipboardImportCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(shareImport)
                .environment(ReviewSettingsStore.shared)
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
                    _ = await ShareExtensionNotifier.requestAuthorizationIfNeeded()
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
}
