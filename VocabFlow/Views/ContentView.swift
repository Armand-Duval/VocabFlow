import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @State private var selectedTab = 0
    @State private var showShareSavedAlert = false
    @State private var shareSavedCount = 0

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
            autoSaveShareDraftsIfNeeded()
        }
        .onChange(of: shareImport.pendingPayload) { _, payload in
            if payload != nil {
                selectedTab = 0
            }
        }
        .onChange(of: shareImport.pendingDrafts) { _, drafts in
            guard drafts != nil else { return }
            autoSaveShareDraftsIfNeeded()
        }
        .onAppear {
            autoSaveShareDraftsIfNeeded()
        }
        .alert("已保存到词库", isPresented: $showShareSavedAlert) {
            Button("去复习") {
                selectedTab = 1
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("分享生成的 \(shareSavedCount) 张卡片已加入词库。")
        }
    }

    private func autoSaveShareDraftsIfNeeded() {
        guard let drafts = shareImport.pendingDrafts, !drafts.isEmpty else { return }

        let count = FlashCardSaver.save(drafts: drafts, to: modelContext)
        shareImport.acknowledgeDrafts()

        guard count > 0 else { return }

        shareSavedCount = count
        showShareSavedAlert = true
        ShareExtensionNotifier.scheduleCardsSavedNotification(cardCount: count)
    }
}

#Preview {
    ContentView()
        .environmentObject(ShareImportCoordinator())
        .modelContainer(for: FlashCard.self, inMemory: true)
}
