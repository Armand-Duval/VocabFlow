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
        in context: ModelContext
    ) async throws -> (deck: Deck, importedCards: Int) {
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

        let deckPack = try await Task.detached(priority: .userInitiated) {
            try DeckPackConverter.deckPack(from: data, format: pack.format, remote: pack)
        }.value
        guard !deckPack.cards.isEmpty else {
            throw DeckDownloadError.emptyPack
        }

        if let existing = DeckService.fetchDeck(slug: pack.slug, in: context) {
            if existing.cards.isEmpty {
                return try await DeckService.importStarterCardsPublicAsync(from: deckPack, into: existing, context: context)
            }
            return (existing, 0)
        }

        return try await DeckService.importPackAsync(deckPack, in: context, markBuiltIn: true)
    }
}
