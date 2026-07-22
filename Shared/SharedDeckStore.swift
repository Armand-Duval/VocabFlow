import Foundation

struct SharedDeckEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let slug: String?
    let sortOrder: Int
}

enum SharedDeckStore {
    static let appGroupID = ShareImportStore.appGroupID
    private static let catalogFileName = "deck-catalog.json"
    private static let prefsFileName = "deck-prefs.json"
    private static let pendingTargetDeckKey = "pendingTargetDeckID"

    private struct Prefs: Codable {
        var lastSelectedDeckID: UUID?
        var pendingTargetDeckID: UUID?
    }

    static var lastSelectedDeckID: UUID? {
        get { loadPrefs().lastSelectedDeckID }
        set {
            var prefs = loadPrefs()
            prefs.lastSelectedDeckID = newValue
            savePrefs(prefs)
        }
    }

    static var pendingTargetDeckID: UUID? {
        get { loadPrefs().pendingTargetDeckID }
        set {
            var prefs = loadPrefs()
            prefs.pendingTargetDeckID = newValue
            savePrefs(prefs)
        }
    }

    static func consumePendingTargetDeckID() -> UUID? {
        var prefs = loadPrefs()
        defer { savePrefs(prefs) }
        guard let id = prefs.pendingTargetDeckID else { return nil }
        prefs.pendingTargetDeckID = nil
        prefs.lastSelectedDeckID = id
        return id
    }

    static func loadCatalog() -> [SharedDeckEntry] {
        guard let url = catalogURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SharedDeckEntry].self, from: data) else {
            return []
        }
        return entries.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func saveCatalog(_ entries: [SharedDeckEntry]) {
        guard let url = catalogURL else { return }
        let sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func resolvedSelectedDeckID() -> UUID? {
        let catalog = loadCatalog()
        guard !catalog.isEmpty else { return lastSelectedDeckID }

        if let lastSelectedDeckID,
           catalog.contains(where: { $0.id == lastSelectedDeckID }) {
            return lastSelectedDeckID
        }
        if let defaultDeck = catalog.first(where: { $0.slug == "default" }) {
            return defaultDeck.id
        }
        return catalog.first?.id
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var catalogURL: URL? {
        containerURL?.appendingPathComponent(catalogFileName)
    }

    private static var prefsURL: URL? {
        containerURL?.appendingPathComponent(prefsFileName)
    }

    private static func loadPrefs() -> Prefs {
        guard let url = prefsURL,
              let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(Prefs.self, from: data) else {
            return Prefs()
        }
        return prefs
    }

    private static func savePrefs(_ prefs: Prefs) {
        guard let url = prefsURL,
              let data = try? JSONEncoder().encode(prefs) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

enum DeckSettings {
    static var lastSelectedDeckID: UUID? {
        get { SharedDeckStore.lastSelectedDeckID }
        set { SharedDeckStore.lastSelectedDeckID = newValue }
    }
}
