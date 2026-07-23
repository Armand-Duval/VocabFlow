import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckStoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedDeckID: UUID?

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @Query private var allCards: [FlashCard]

    @State private var showCreateDeck = false
    @State private var showPackImporter = false
    @State private var showApkgImporter = false
    @State private var showBackupImporter = false
    @State private var showImportOptions = false
    @State private var pendingBackupData: Data?
    @State private var exportDocument: BackupDocument?
    @State private var apkgDocument: ApkgDocument?
    @State private var showJSONExporter = false
    @State private var showApkgExporter = false
    @State private var importTargetDeckID: UUID?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var downloadingPackID: String?
    @State private var isImportingJSON = false
    @State private var isImportingApkg = false
    @State private var isImportingBackup = false
    @State private var showApkgImportGuide = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            myDecksSection
            openSourceSection
            communitySection
            importDeckSection
            backupSection
        }
        .navigationTitle(L10n.deckStoreTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateDeck = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateDeck) {
            CreateDeckSheet { deck in
                selectedDeckID = deck.id
                DeckSettings.lastSelectedDeckID = deck.id
            }
        }
        .fileImporter(
            isPresented: $showPackImporter,
            allowedContentTypes: [.json]
        ) { result in
            handlePackImport(result)
        }
        .fileImporter(
            isPresented: $showApkgImporter,
            allowedContentTypes: [.apkg, .data]
        ) { result in
            handleApkgImport(result)
        }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [.json]
        ) { result in
            handleBackupImportSelection(result)
        }
        .confirmationDialog(L10n.importModeTitle, isPresented: $showImportOptions, titleVisibility: .visible) {
            Button(L10n.importModeMerge) {
                performMergeBackupImport()
            }
            Button(L10n.importModeReplace, role: .destructive) {
                performReplaceBackupImport()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.importModeMessage)
        }
        .fileExporter(
            isPresented: $showJSONExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupService.defaultFilename
        ) { result in
            if case .failure(let error) = result {
                showResult(title: L10n.exportFailed, message: error.localizedDescription)
            }
        }
        .fileExporter(
            isPresented: $showApkgExporter,
            document: apkgDocument,
            contentType: .apkg,
            defaultFilename: ApkgExportService.defaultFilename
        ) { result in
            if case .failure(let error) = result {
                showResult(title: L10n.exportFailed, message: error.localizedDescription)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert(L10n.deckCommunityImportGuideTitle, isPresented: $showApkgImportGuide) {
            Button(L10n.deckCommunityImportNow) {
                importTargetDeckID = selectedDeckID ?? DeckService.fetchOrCreateDefault(in: modelContext).id
                showApkgImporter = true
            }
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.deckCommunityImportGuideBody)
        }
        .onAppear {
            DeckService.bootstrap(in: modelContext)
        }
    }

    private var myDecksSection: some View {
        Section(L10n.deckMyDecks) {
            if decks.isEmpty {
                Text(L10n.deckEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(decks) { deck in
                    Button {
                        selectedDeckID = deck.id
                        DeckSettings.lastSelectedDeckID = deck.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deck.name)
                                    .foregroundStyle(.primary)
                                if let detail = deck.detailText, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if selectedDeckID == deck.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                            Text("\(deck.cardCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if deck.slug != DeckCatalog.defaultSlug {
                            Button(role: .destructive) {
                                deleteDeck(deck)
                            } label: {
                                Label(L10n.deckDelete, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var openSourceSection: some View {
        Section {
            ForEach(DeckRemoteCatalog.packs) { pack in
                remotePackRow(pack)
            }
        } header: {
            Text(L10n.deckOpenSourceSection)
        } footer: {
            Text(L10n.deckOpenSourceFooter)
        }
    }

    private var communitySection: some View {
        Section {
            ForEach(DeckCommunityCatalog.entries) { entry in
                communityRow(entry)
            }

            Button {
                showApkgImportGuide = true
            } label: {
                Label(L10n.deckCommunityImportGuide, systemImage: "questionmark.circle")
            }
        } header: {
            Text(L10n.deckCommunitySection)
        } footer: {
            Text(L10n.deckCommunityFooter)
        }
    }

    private var importDeckSection: some View {
        Section {
            Button {
                showPackImporter = true
            } label: {
                HStack {
                    Label(L10n.deckImportPack, systemImage: "doc.badge.plus")
                    Spacer()
                    if isImportingJSON {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isImportingJSON || isImportingApkg)

            Button {
                importTargetDeckID = selectedDeckID ?? DeckService.fetchOrCreateDefault(in: modelContext).id
                showApkgImporter = true
            } label: {
                HStack {
                    Label(L10n.deckImportApkg, systemImage: "square.and.arrow.down")
                    Spacer()
                    if isImportingApkg {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isImportingJSON || isImportingApkg)
        } header: {
            Text(L10n.deckImportDeckSection)
        } footer: {
            Text(L10n.deckImportDeckFooter)
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                exportJSONBackup()
            } label: {
                Label(L10n.exportBackup, systemImage: "doc.text")
            }

            Button {
                showBackupImporter = true
            } label: {
                HStack {
                    Label(L10n.importBackup, systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isImportingBackup {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isImportingBackup)

            Button {
                exportAllApkg()
            } label: {
                Label(L10n.exportApkg, systemImage: "square.and.arrow.up")
            }
            .disabled(allCards.isEmpty)
        } header: {
            Text(L10n.deckBackupSection)
        } footer: {
            Text(L10n.deckBackupFooter(allCards.count))
        }
    }

    @ViewBuilder
    private func remotePackRow(_ pack: DeckRemotePack) -> some View {
        let installedDeck = decks.first { $0.slug == pack.slug }
        let installed = installedDeck != nil
        let isEmptyInstalled = installedDeck?.cardCount == 0
        let isDownloading = downloadingPackID == pack.id

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pack.name)
                            .font(.headline)
                        Text(pack.cardCountLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(pack.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pack.licenseLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else if isEmptyInstalled || !installed {
                    deckIconButton(systemImage: "arrow.down.circle", label: L10n.deckDownload) {
                        downloadRemotePack(pack)
                    }
                } else {
                    Label(L10n.deckInstalled, systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Link(destination: pack.attributionURL) {
                Text(L10n.deckRemoteViewSource)
                    .font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func communityRow(_ entry: DeckCommunityEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.headline)
                        if let countLabel = entry.cardCountLabel {
                            Text(countLabel)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(entry.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                deckIconButton(systemImage: "safari", label: L10n.deckCommunityOpenAnkiWeb) {
                    openURL(entry.ankiWebURL)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func deckIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func downloadRemotePack(_ pack: DeckRemotePack) {
        downloadingPackID = pack.id
        Task { @MainActor in
            defer { downloadingPackID = nil }
            do {
                let result = try await DeckDownloadService.downloadAndInstall(pack: pack, in: modelContext)
                selectedDeckID = result.deck.id
                DeckSettings.lastSelectedDeckID = result.deck.id
                if result.importedCards > 0 {
                    showResult(
                        title: L10n.deckInstallComplete,
                        message: L10n.deckInstallWithCards(result.deck.name, count: result.importedCards)
                    )
                } else {
                    showResult(
                        title: L10n.deckInstallComplete,
                        message: L10n.deckInstallEmpty(result.deck.name)
                    )
                }
            } catch {
                showResult(title: L10n.deckDownloadFailed, message: error.localizedDescription)
            }
        }
    }

    private func deleteDeck(_ deck: Deck) {
        do {
            try DeckService.deleteDeck(deck, in: modelContext)
            if selectedDeckID == deck.id {
                let fallback = DeckService.fetchOrCreateDefault(in: modelContext)
                selectedDeckID = fallback.id
                DeckSettings.lastSelectedDeckID = fallback.id
            }
        } catch {
            showResult(title: L10n.deckDeleteFailed, message: error.localizedDescription)
        }
    }

    private func handlePackImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImportingJSON = true
            Task { @MainActor in
                defer { isImportingJSON = false }
                do {
                    let data = try BackupDocumentSupport.readData(from: url)
                    let imported = try await DeckService.importPackDataAsync(data, in: modelContext)
                    selectedDeckID = imported.deck.id
                    DeckSettings.lastSelectedDeckID = imported.deck.id
                    showResult(
                        title: L10n.deckImportComplete,
                        message: L10n.deckImportPackResult(imported.deck.name, count: imported.importedCards)
                    )
                } catch {
                    showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
                }
            }
        case .failure(let error):
            showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
        }
    }

    private func handleApkgImport(_ result: Result<URL, Error>) {
        let deckID = importTargetDeckID ?? selectedDeckID ?? DeckService.fetchOrCreateDefault(in: modelContext).id
        guard let deck = DeckService.fetchDeck(id: deckID, in: modelContext) else { return }

        switch result {
        case .success(let url):
            isImportingApkg = true
            Task { @MainActor in
                defer { isImportingApkg = false }
                do {
                    let data = try BackupDocumentSupport.readData(from: url)
                    let imported = try await ApkgImportService.importApkgAsync(data: data, into: deck, context: modelContext)
                    selectedDeckID = deck.id
                    DeckSettings.lastSelectedDeckID = deck.id
                    showResult(
                        title: L10n.deckImportComplete,
                        message: L10n.deckImportApkgResult(deck.name, count: imported.imported)
                    )
                } catch {
                    showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
                }
            }
        case .failure(let error):
            showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
        }
    }

    private func exportJSONBackup() {
        do {
            let data = try BackupService.export(cards: allCards, decks: decks)
            exportDocument = BackupDocument(data: data)
            showJSONExporter = true
        } catch {
            showResult(title: L10n.exportFailed, message: error.localizedDescription)
        }
    }

    private func exportAllApkg() {
        do {
            let data = try ApkgExportService.export(cards: allCards)
            apkgDocument = ApkgDocument(data: data)
            showApkgExporter = true
        } catch {
            showResult(title: L10n.exportFailed, message: error.localizedDescription)
        }
    }

    private func handleBackupImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                pendingBackupData = try BackupDocumentSupport.readData(from: url)
                showImportOptions = true
            } catch {
                showResult(title: L10n.readFailed, message: error.localizedDescription)
            }
        case .failure(let error):
            showResult(title: L10n.importFailed, message: error.localizedDescription)
        }
    }

    private func performMergeBackupImport() {
        guard let data = pendingBackupData else { return }
        isImportingBackup = true
        Task { @MainActor in
            defer {
                isImportingBackup = false
                pendingBackupData = nil
            }
            do {
                let result = try BackupService.importMerge(data: data, into: modelContext)
                showResult(
                    title: L10n.importComplete,
                    message: L10n.importMergeResult(added: result.added, updated: result.updated)
                )
            } catch {
                showResult(title: L10n.importFailed, message: error.localizedDescription)
            }
        }
    }

    private func performReplaceBackupImport() {
        guard let data = pendingBackupData else { return }
        isImportingBackup = true
        Task { @MainActor in
            defer {
                isImportingBackup = false
                pendingBackupData = nil
            }
            do {
                let count = try BackupService.importReplace(data: data, into: modelContext)
                showResult(title: L10n.importComplete, message: L10n.importReplaceResult(count))
            } catch {
                showResult(title: L10n.importFailed, message: error.localizedDescription)
            }
        }
    }

    private func showResult(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

private struct CreateDeckSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Deck) -> Void

    @State private var name = ""
    @State private var detailText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.deckNamePlaceholder, text: $name)
                TextField(L10n.deckDetailPlaceholder, text: $detailText, axis: .vertical)
                    .lineLimit(2...5)
            }
            .navigationTitle(L10n.deckCreateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.add) {
                        let deck = DeckService.createCustomDeck(
                            name: name,
                            detailText: detailText,
                            in: modelContext
                        )
                        onCreated(deck)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        DeckStoreView(selectedDeckID: .constant(nil))
    }
    .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}
