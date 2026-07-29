import Foundation

extension Notification.Name {
    static let shareImportReceived = Notification.Name("shareImportReceived")
    static let shareDraftsReceived = Notification.Name("shareDraftsReceived")
}

enum ShareImportService {
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == "knowell", url.host == "create" else { return false }
        NotificationCenter.default.post(name: .shareImportReceived, object: nil)
        return true
    }
}

@MainActor
final class ShareImportCoordinator: ObservableObject {
    @Published private(set) var pendingPayload: ShareImportPayload?
    @Published private(set) var pendingDrafts: [GeneratedCardDraft]?

    func refreshFromSharedStorage() {
        if let payload = ShareImportStore.consumePendingImport() {
            pendingPayload = payload
        }
    }

    func refreshPendingDrafts() {
        if let drafts = ShareImportStore.consumePendingDrafts(), !drafts.isEmpty {
            pendingDrafts = drafts
            NotificationCenter.default.post(name: .shareDraftsReceived, object: nil)
        }
    }

    func refreshAll() {
        refreshPendingDrafts()
        if pendingDrafts == nil {
            refreshFromSharedStorage()
        }
    }

    func acknowledgeImport() {
        pendingPayload = nil
    }

    func acknowledgeDrafts() {
        pendingDrafts = nil
    }

    func importPayload(_ payload: ShareImportPayload) {
        pendingPayload = payload
    }

    var hasPendingImport: Bool {
        pendingPayload != nil || pendingDrafts != nil
    }
}
