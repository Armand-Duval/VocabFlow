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
                    Task {
                        await processShareWorkItems()
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
                }
                clipboardImport.checkClipboardIfNeeded(shareImport: shareImport)
            }
        }
    }

    @MainActor
    private func processShareWorkItems() async {
        SharedDedupeSync.rebuild(in: AppModelContainer.shared.mainContext)
        if ShareImportStore.hasPendingGenerationJob {
            await ShareCardGenerationRunner.processPendingJobIfNeeded(resetStale: true)
        }
        shareImport.refreshAll()
    }
}
