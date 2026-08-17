import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @Environment(ReviewSettingsStore.self) private var reviewSettings
    @State private var selectedTab = 0
    /// Mount a tab the first time it is selected. Do not swap siblings in later —
    /// that rebuilds TabView and dismisses any half-sheet currently on screen.
    @State private var mountedTabs: Set<Int> = [0]
    @State private var sessionDueCount = ReviewStatusStore.dueCount
    @State private var dueCountRefreshToken = 0
    @State private var dueCountRefreshDelayMilliseconds = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(0) {
                ReviewView()
            }
            .tabItem {
                Label {
                    Text(L10n.tabReview)
                } icon: {
                    AppTabIcon(
                        systemName: selectedTab == 0 ? "rectangle.stack.fill" : "rectangle.stack",
                        isSelected: selectedTab == 0
                    )
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
                    AppTabIcon(
                        systemName: selectedTab == 1 ? "books.vertical.fill" : "books.vertical",
                        isSelected: selectedTab == 1
                    )
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
                    AppTabIcon(
                        systemName: selectedTab == 2 ? "plus.circle.fill" : "plus.circle",
                        isSelected: selectedTab == 2
                    )
                }
            }
            .tag(2)

            tabContent(3) {
                SettingsView(isPresentedAsSheet: false)
            }
            .tabItem {
                Label {
                    Text(L10n.tabSettings)
                } icon: {
                    AppTabIcon(
                        systemName: selectedTab == 3 ? "person.crop.circle.fill" : "person.crop.circle",
                        isSelected: selectedTab == 3
                    )
                }
            }
            .tag(3)
        }
        .toolbarBackground(AppColor.pageBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .appTint()
        .appToast()
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
            selectedTab = AppTab.settings.rawValue
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
                selectedTab = min(max(tab, 0), AppTab.settings.rawValue)
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
    }

    private func focusCreateTabForPendingShareWork() {
        guard shareImport.hasPendingImport else { return }
        selectedTab = 2
        mountedTabs.insert(2)
    }

    private func scheduleDueCountRefresh(delayMilliseconds: Int) {
        dueCountRefreshDelayMilliseconds = delayMilliseconds
        dueCountRefreshToken += 1
    }

    @MainActor
    private func refreshSessionDueCount() async {
        await Task.yield()
        let now = Date.now
        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.isSuspended == false && card.nextReviewDate <= now
            }
        )
        guard let cards = try? modelContext.fetch(descriptor) else { return }

        let scoped = ReviewQueueBuilder.cards(in: DeckSettings.lastSelectedDeckID, from: cards)

        let count = ReviewQueueBuilder.sessionDueCount(
            from: scoped,
            dailyNewLimit: reviewSettings.dailyNewLimit,
            dailyReviewLimit: reviewSettings.dailyReviewLimit
        )
        if sessionDueCount != count {
            sessionDueCount = count
        }
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
