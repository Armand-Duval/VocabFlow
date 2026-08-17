import Foundation
import SwiftData

enum DeckDownloadError: LocalizedError {
    case invalidResponse
    case emptyPack
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            L10n.deckDownloadInvalidResponse
        case .emptyPack:
            L10n.deckDownloadEmptyPack
        case .network(let error):
            L10n.deckDownloadNetworkFailed(error.localizedDescription)
        }
    }
}

enum DeckDownloadService {
    @MainActor
    static func downloadAndInstall(
        pack: DeckRemotePack,
        in context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> (deck: Deck, importedCards: Int, original: OriginalPackRecord?) {
        let data: Data
        do {
            var request = URLRequest(url: pack.url)
            request.timeoutInterval = 120
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw DeckDownloadError.invalidResponse
            }
            data = responseData
        } catch let error as DeckDownloadError {
            throw error
        } catch {
            throw DeckDownloadError.network(error)
        }

        var original: OriginalPackRecord?
        do {
            original = try OriginalPackArchive.save(
                data: data,
                suggestedName: pack.slug,
                fileExtension: pack.url.pathExtension.isEmpty ? "json" : pack.url.pathExtension,
                sourceURL: pack.url
            )
        } catch {
            AppLog.error("Original pack archive failed: \(error.localizedDescription)", category: "Library")
        }

        let deckPack = try await Task.detached(priority: .userInitiated) {
            try DeckPackConverter.deckPack(from: data, format: pack.format, remote: pack)
        }.value
        guard !deckPack.cards.isEmpty else {
            throw DeckDownloadError.emptyPack
        }

        if let existing = DeckService.fetchDeck(slug: pack.slug, in: context) {
            if existing.cardCount == 0 {
                let imported = try await DeckService.importStarterCardsPublicAsync(
                    from: deckPack,
                    into: existing,
                    context: context,
                    progress: progress
                )
                return (imported.deck, imported.importedCards, original)
            }
            return (existing, 0, original)
        }

        let imported = try await DeckService.importPackAsync(deckPack, in: context, markBuiltIn: true, progress: progress)
        return (imported.deck, imported.importedCards, original)
    }
}
