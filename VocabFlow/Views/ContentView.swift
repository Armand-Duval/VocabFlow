import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

struct ContentView: View {
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @State private var selectedTab = 0
    @State private var sharePreviewDrafts: [GeneratedCardDraft]?

    var body: some View {
        TabView(selection: $selectedTab) {
            CreateCardsView()
                .tabItem {
                    Label("制卡", systemImage: "plus.rectangle.on.rectangle")
                }
                .tag(0)

            ReviewView()
                .tabItem {
                    Label("复习", systemImage: "brain.head.profile")
                }
                .tag(1)

            LibraryView()
                .tabItem {
                    Label("词库", systemImage: "books.vertical")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
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
            shareImport.refreshAll()
            presentSharePreviewIfNeeded()
        }
        .fullScreenCover(isPresented: Binding(
            get: { sharePreviewDrafts != nil },
            set: { if !$0 { sharePreviewDrafts = nil } }
        )) {
            NavigationStack {
                CardPreviewView(
                    drafts: Binding(
                        get: { sharePreviewDrafts ?? [] },
                        set: { sharePreviewDrafts = $0 }
                    ),
                    onComplete: {
                        sharePreviewDrafts = nil
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
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
        shareImport.acknowledgeDrafts()
        selectedTab = 0
    }
}

#Preview {
    ContentView()
        .environmentObject(ShareImportCoordinator())
        .modelContainer(for: FlashCard.self, inMemory: true)
}
