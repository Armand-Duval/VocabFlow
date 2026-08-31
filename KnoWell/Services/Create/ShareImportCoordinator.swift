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
    @Published private(set) var pendingInbox: ShareInboxPayload?

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
        if pendingDrafts != nil { return }
        if pendingInbox != nil { return }
        if let inbox = ShareImportStore.consumeInbox() {
            pendingInbox = inbox
            return
        }
        refreshFromSharedStorage()
    }

    func acknowledgeImport() {
        pendingPayload = nil
    }

    func acknowledgeDrafts() {
        pendingDrafts = nil
    }

    func acknowledgeInbox() {
        pendingInbox = nil
    }

    func importPayload(_ payload: ShareImportPayload) {
        pendingPayload = payload
    }

    var hasPendingImport: Bool {
        pendingPayload != nil || pendingDrafts != nil || pendingInbox != nil
    }
}
