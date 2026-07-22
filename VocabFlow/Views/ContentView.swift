import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @Query(sort: \FlashCard.nextReviewDate) private var allCards: [FlashCard]
    @State private var selectedTab = 0
    @State private var sharePreviewDrafts: [GeneratedCardDraft]?
    @State private var shareSelectedDeckID: UUID?

    private var dueCount: Int {
        allCards.filter { ReviewScheduler.isDue($0) }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CreateCardsView()
                .tabItem {
                    Label(L10n.tabCreate, systemImage: "plus.rectangle.on.rectangle")
                }
                .tag(0)

            ReviewView()
                .tabItem {
                    Label(L10n.tabReview, systemImage: "brain.head.profile")
                }
                .badge(dueCount > 0 ? dueCount : 0)
                .tag(1)

            LibraryView()
                .tabItem {
                    Label(L10n.tabLibrary, systemImage: "books.vertical")
                }
                .tag(2)

            SettingsView()
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
        .onChange(of: shareImport.pendingPayload) { _, payload in
            if payload != nil {
                selectedTab = 0
            }
        }
        .onChange(of: shareImport.pendingDrafts) { _, drafts in
            guard drafts != nil else { return }
            presentSharePreviewIfNeeded()
        }
        .onAppear {
            DeckService.bootstrap(in: modelContext)
            shareImport.refreshAll()
            presentSharePreviewIfNeeded()
            ReviewReminderService.reschedule(dueCount: dueCount)
            ReviewStatusStore.updateDueCount(dueCount)
            if shareSelectedDeckID == nil {
                shareSelectedDeckID = DeckSettings.lastSelectedDeckID
            }
        }
        .onChange(of: dueCount) { _, count in
            ReviewReminderService.reschedule(dueCount: count)
            ReviewStatusStore.updateDueCount(count)
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
        .modelContainer(for: [FlashCard.self, Deck.self], inMemory: true)
}
