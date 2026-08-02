import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @Environment(ReviewSettingsStore.self) private var reviewSettings
    @State private var selectedTab = 0
    @State private var mountedTabs: Set<Int> = [0]
    @State private var sessionDueCount = ReviewStatusStore.dueCount
    @State private var dueCountRefreshToken = 0
    @State private var dueCountRefreshDelayMilliseconds = 0
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(0) {
                ReviewView()
            }
            .tabItem {
                Label {
                    Text(L10n.tabReview)
                } icon: {
                    AppTabIcon(systemName: "rectangle.stack", isSelected: selectedTab == 0)
                }
            }
            .badge(sessionDueCount > 0 ? sessionDueCount : 0)
            .tag(0)

            tabContent(1) {
                LibraryView()
            }
            .tabItem {
                Label {
                    Text(L10n.tabLibrary)
                } icon: {
                    AppTabIcon(systemName: "books.vertical", isSelected: selectedTab == 1)
                }
            }
            .tag(1)

            tabContent(2) {
                CreateCardsView()
            }
            .tabItem {
                Label {
                    Text(L10n.tabCreate)
                } icon: {
                    AppTabIcon(systemName: "plus.circle", isSelected: selectedTab == 2)
                }
            }
            .tag(2)
        }
        .toolbarBackground(AppColor.pageBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .appTint()
        .appToast()
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresentedAsSheet: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareImportReceived)) { _ in
            shareImport.refreshAll()
            focusCreateTabForPendingShareWork()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareDraftsReceived)) { _ in
            focusCreateTabForPendingShareWork()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            scheduleDueCountRefresh(delayMilliseconds: 200)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataMaintenanceDidComplete)) { _ in
            LibraryCatalogCache.shared.invalidateAll()
            scheduleDueCountRefresh(delayMilliseconds: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewQueueDidChange)) { _ in
            scheduleDueCountRefresh(delayMilliseconds: 300)
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeDeckDidChange)) { _ in
            scheduleDueCountRefresh(delayMilliseconds: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestSettings)) { _ in
            showSettings = true
        }
        .onChange(of: shareImport.pendingPayload) { _, payload in
            if payload != nil {
                selectedTab = 2
            }
        }
        .onChange(of: shareImport.pendingDrafts) { _, drafts in
            guard drafts != nil else { return }
            selectedTab = 2
        }
        .onChange(of: selectedTab) { _, tab in
            mountedTabs.insert(tab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestAppTab)) { notification in
            if let tab = notification.userInfo?["tab"] as? Int {
                selectedTab = min(tab, 2)
            }
        }
        .onChange(of: reviewSettings.revision) { _, _ in
            scheduleDueCountRefresh(delayMilliseconds: 0)
        }
        .onAppear {
            DeckService.bootstrap(in: modelContext)
            CardContentMigrationService.migrateLocallyIfNeeded(in: modelContext)
            shareImport.refreshAll()
            focusCreateTabForPendingShareWork()
            scheduleDueCountRefresh(delayMilliseconds: 800)
            BackupReminderService.reschedule()
            prewarmIdleTabs()
        }
        .task(id: dueCountRefreshToken) {
            guard dueCountRefreshDelayMilliseconds > 0 else {
                await refreshSessionDueCount()
                return
            }
            try? await Task.sleep(for: .milliseconds(dueCountRefreshDelayMilliseconds))
            await refreshSessionDueCount()
        }
    }

    @ViewBuilder
    private func tabContent<T: View>(_ tag: Int, @ViewBuilder content: () -> T) -> some View {
        Group {
            if mountedTabs.contains(tag) {
                content()
            } else {
                Color.clear
            }
        }
        .opacity(selectedTab == tag ? 1 : 0)
        .allowsHitTesting(selectedTab == tag)
    }

    private func prewarmIdleTabs() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            mountedTabs.formUnion([1, 2])
        }
    }

    private func focusCreateTabForPendingShareWork() {
        guard shareImport.hasPendingImport else { return }
        selectedTab = 2
    }

    private func scheduleDueCountRefresh(delayMilliseconds: Int) {
        dueCountRefreshDelayMilliseconds = delayMilliseconds
        dueCountRefreshToken += 1
    }

    @MainActor
    private func refreshSessionDueCount() async {
        await Task.yield()
        let descriptor = FetchDescriptor<FlashCard>()
        guard let cards = try? modelContext.fetch(descriptor) else { return }

        let scoped = ReviewQueueBuilder.cards(in: DeckSettings.lastSelectedDeckID, from: cards)

        let count = ReviewQueueBuilder.sessionDueCount(
            from: scoped,
            dailyNewLimit: reviewSettings.dailyNewLimit,
            dailyReviewLimit: reviewSettings.dailyReviewLimit
        )
        sessionDueCount = count
        ReviewReminderService.reschedule(dueCount: count)
        ReviewStatusStore.updateDueCount(count)
    }
}

#Preview {
    ContentView()
        .environmentObject(ShareImportCoordinator())
        .environment(ReviewSettingsStore.shared)
        .modelContainer(for: [FlashCard.self, Deck.self], inMemory: true)
}
