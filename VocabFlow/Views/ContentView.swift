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
    @State private var sharePreviewDrafts: [GeneratedCardDraft]?
    @State private var shareSelectedDeckID: UUID?
    @State private var sessionDueCount = ReviewStatusStore.dueCount
    @State private var dueCountRefreshToken = 0
    @State private var dueCountRefreshDelayMilliseconds = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CreateCardsView()
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)
                .tabItem {
                    Label(L10n.tabCreate, systemImage: "plus.rectangle.on.rectangle")
                }
                .tag(0)

            tabContent(1) {
                ReviewView()
            }
            .tabItem {
                Label(L10n.tabReview, systemImage: "brain.head.profile")
            }
            .badge(sessionDueCount > 0 ? sessionDueCount : 0)
            .tag(1)

            tabContent(2) {
                LibraryView()
            }
            .tabItem {
                Label(L10n.tabLibrary, systemImage: "books.vertical")
            }
            .tag(2)

            tabContent(3) {
                SettingsView()
            }
            .tabItem {
                Label(L10n.tabSettings, systemImage: "gearshape")
            }
            .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareImportReceived)) { _ in
            shareImport.refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareDraftsReceived)) { _ in
            presentSharePreviewIfNeeded()
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
        .onChange(of: shareImport.pendingPayload) { _, payload in
            if payload != nil {
                selectedTab = 0
            }
        }
        .onChange(of: shareImport.pendingDrafts) { _, drafts in
            guard drafts != nil else { return }
            presentSharePreviewIfNeeded()
        }
        .onChange(of: selectedTab) { _, tab in
            mountedTabs.insert(tab)
        }
        .onChange(of: reviewSettings.revision) { _, _ in
            scheduleDueCountRefresh(delayMilliseconds: 0)
        }
        .onAppear {
            DeckService.bootstrap(in: modelContext)
            shareImport.refreshAll()
            presentSharePreviewIfNeeded()
            if shareSelectedDeckID == nil {
                shareSelectedDeckID = DeckSettings.lastSelectedDeckID
            }
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
        .fullScreenCover(isPresented: Binding(
            get: { sharePreviewDrafts != nil },
            set: { if !$0 { sharePreviewDrafts = nil } }
        )) {
            NavigationStack {
                CardPreviewView(
                    drafts: sharePreviewDrafts ?? [],
                    selectedDeckID: $shareSelectedDeckID,
                    onComplete: {
                        sharePreviewDrafts = nil
                        scheduleDueCountRefresh(delayMilliseconds: 300)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.close) {
                            sharePreviewDrafts = nil
                        }
                    }
                }
            }
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
            mountedTabs.formUnion([1, 2, 3])
        }
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

        let count = ReviewQueueBuilder.sessionDueCount(
            from: cards,
            dailyNewLimit: reviewSettings.dailyNewLimit,
            dailyReviewLimit: reviewSettings.dailyReviewLimit
        )
        sessionDueCount = count
        ReviewReminderService.reschedule(dueCount: count)
        ReviewStatusStore.updateDueCount(count)
    }

    private func presentSharePreviewIfNeeded() {
        guard let drafts = shareImport.pendingDrafts, !drafts.isEmpty else { return }
        sharePreviewDrafts = drafts
        if let pendingDeckID = SharedDeckStore.consumePendingTargetDeckID() {
            shareSelectedDeckID = pendingDeckID
        } else {
            shareSelectedDeckID = SharedDeckStore.resolvedSelectedDeckID()
        }
        shareImport.acknowledgeDrafts()
        selectedTab = 0
    }
}

#Preview {
    ContentView()
        .environmentObject(ShareImportCoordinator())
        .environment(ReviewSettingsStore.shared)
        .modelContainer(for: [FlashCard.self, Deck.self], inMemory: true)
}
