import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckStoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedDeckID: UUID?

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var queriedDecks: [Deck]

    @State private var cachedDecks: [Deck] = []
    @State private var checkedDeckIDs: Set<UUID> = []

    private var decks: [Deck] {
        queriedDecks.isEmpty ? cachedDecks : queriedDecks
    }

    @State private var showCreateDeck = false
    @State private var showUnifiedFileImporter = false
    @State private var fileImportMode: DeckFileImportMode?
    @State private var allowedImportTypes: [UTType] = [.json]
    @State private var exportDocument: BackupDocument?
    @State private var apkgDocument: ApkgDocument?
    @State private var showJSONExporter = false
    @State private var showApkgExporter = false
    @State private var apkgExportFilename = ApkgExportService.defaultFilename
    @State private var jsonExportFilename = BackupService.defaultFilename
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var downloadingPackID: String?
    @State private var importProgress: ImportProgressState?
    @State private var isImportingJSON = false
    @State private var isImportingApkg = false
    @State private var isPreparingExport = false
    @State private var showApkgImportGuide = false
    @Environment(\.openURL) private var openURL

    private var isImportBusy: Bool {
        isImportingJSON || isImportingApkg || downloadingPackID != nil || isPreparingExport
    }

    private var busyOverlayMessage: String {
        isPreparingExport ? L10n.deckPreparingExport : L10n.deckImporting
    }

    private var checkedDecks: [Deck] {
        decks.filter { checkedDeckIDs.contains($0.id) }
    }

    private var checkedCardCount: Int {
        checkedDecks.reduce(0) { $0 + $1.cardCount }
    }

    private var allDecksSelected: Bool {
        !decks.isEmpty && checkedDeckIDs.count == decks.count
    }

    var body: some View {
        List {
            myDecksSection
            deckActionsSection
            openSourceSection
            communitySection
        }
        .navigationTitle(L10n.deckStoreTitle)
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(isPresented: isImportBusy, message: busyOverlayMessage)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateDeck = true
                } label: {
                    AppIcon.symbol("plus")
                }
            }
        }
        .sheet(isPresented: $showCreateDeck) {
            CreateDeckSheet { deck in
                selectedDeckID = deck.id
                DeckSettings.lastSelectedDeckID = deck.id
                checkedDeckIDs = [deck.id]
                reloadDecks()
                DeckCardCountService.notifyCatalogChanged()
            }
        }
        .fileImporter(
            isPresented: $showUnifiedFileImporter,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: false
        ) { result in
            handleUnifiedFileImport(result)
        }
        .fileExporter(
            isPresented: $showJSONExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: jsonExportFilename
        ) { result in
            switch result {
            case .success:
                BackupReminderService.recordBackupCompleted()
                ToastCenter.shared.show(L10n.exportBackupSuccess)
            case .failure(let error):
                showResult(title: L10n.exportFailed, message: error.localizedDescription)
            }
        }
        .fileExporter(
            isPresented: $showApkgExporter,
            document: apkgDocument,
            contentType: .apkg,
            defaultFilename: apkgExportFilename
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
                beginFileImport(.apkg)
            }
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.deckCommunityImportGuideBody)
        }
        .onAppear {
            reloadDecks()
            seedCheckedDecksIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            reloadDecks()
        }
    }

    private func seedCheckedDecksIfNeeded() {
        guard checkedDeckIDs.isEmpty else { return }
        if let selectedDeckID, decks.contains(where: { $0.id == selectedDeckID }) {
            checkedDeckIDs = [selectedDeckID]
        }
    }

    private func syncPrimaryDeckSelection() {
        if checkedDeckIDs.count == 1, let deckID = checkedDeckIDs.first {
            selectedDeckID = deckID
            DeckSettings.lastSelectedDeckID = deckID
        }
    }

    private func toggleDeckCheck(_ deck: Deck) {
        if checkedDeckIDs.contains(deck.id) {
            checkedDeckIDs.remove(deck.id)
        } else {
            checkedDeckIDs.insert(deck.id)
        }
        syncPrimaryDeckSelection()
    }

    private func toggleSelectAllDecks() {
        if allDecksSelected {
            checkedDeckIDs.removeAll()
        } else {
            checkedDeckIDs = Set(decks.map(\.id))
        }
        syncPrimaryDeckSelection()
    }

    private func reloadDecks() {
        cachedDecks = DeckService.refreshDecks(in: modelContext)
    }

    private var myDecksSection: some View {
        Section {
            if decks.isEmpty {
                Text(L10n.deckEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(decks) { deck in
                    HStack {
                        Button {
                            toggleDeckCheck(deck)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: checkedDeckIDs.contains(deck.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checkedDeckIDs.contains(deck.id) ? AppColor.accent : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(deck.name)
                                        .foregroundStyle(.primary)
                                    if let detail = deck.detailText, !detail.isEmpty {
                                        Text(detail)
                                            .font(AppFont.caption())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Text("\(deck.cardCount)")
                                    .font(AppFont.caption())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            DeckStatisticsView(deck: deck)
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if deck.cardCount > 0 {
                            Button {
                                exportDeckApkg(deck)
                            } label: {
                                Label(L10n.deckExportApkg, systemImage: "square.and.arrow.up")
                            }
                            .tint(AppColor.accent)
                        }

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
        } header: {
            HStack {
                AppSectionHeader(title: L10n.deckMyDecks)
                Spacer()
                if !decks.isEmpty {
                    Button(allDecksSelected ? L10n.deckDeselectAll : L10n.deckSelectAll) {
                        toggleSelectAllDecks()
                    }
                    .font(AppFont.caption())
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
            AppSectionHeader(title: L10n.deckOpenSourceSection)
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
            AppSectionHeader(title: L10n.deckCommunitySection)
        }
    }

    private var deckActionsSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.sm
            ) {
                QuickActionChip(
                    systemImage: "square.and.arrow.down",
                    title: L10n.deckQuickImportJSON,
                    isLoading: isImportingJSON,
                    isDisabled: isImportingApkg
                ) {
                    beginFileImport(.deckJSON)
                }
                .accessibilityLabel(L10n.deckQuickImportJSON)

                QuickActionChip(
                    systemImage: "square.and.arrow.up",
                    title: L10n.deckQuickExportDeckJSON,
                    isLoading: isPreparingExport,
                    isDisabled: checkedDeckIDs.isEmpty || checkedCardCount == 0
                ) {
                    exportCheckedDecksJSON()
                }
                .accessibilityLabel(L10n.deckQuickExportDeckJSON)

                QuickActionChip(
                    systemImage: "square.and.arrow.down.fill",
                    title: L10n.deckQuickImportApkg,
                    isLoading: isImportingApkg,
                    isDisabled: isImportingJSON
                ) {
                    beginFileImport(.apkg)
                }
                .accessibilityLabel(L10n.deckImportApkg)

                QuickActionChip(
                    systemImage: "square.and.arrow.up.fill",
                    title: L10n.deckQuickExportDeckApkg,
                    isLoading: isPreparingExport,
                    isDisabled: checkedDeckIDs.isEmpty || checkedCardCount == 0
                ) {
                    exportCheckedDecksApkg()
                }
                .accessibilityLabel(L10n.deckQuickExportDeckApkg)
            }
            .padding(.vertical, AppSpacing.xs)
        } header: {
            AppSectionHeader(title: L10n.deckActionsSection)
        } footer: {
            Text(
                checkedDeckIDs.isEmpty
                    ? L10n.deckActionsImportFooter
                    : L10n.deckActionsFooter(checkedDeckIDs.count)
            )
            .font(AppFont.caption())
        }
        .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.md, bottom: AppSpacing.sm, trailing: AppSpacing.md))
        .listRowBackground(Color.clear)
    }

    private struct ImportProgressState {
        let key: String
        var current: Int
        var total: Int
    }

    @ViewBuilder
    private func importProgressView(for key: String) -> some View {
        if let progress = importProgress, progress.key == key, progress.total > 0 {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .frame(width: 72)
                Text(L10n.deckImportProgress(current: progress.current, total: progress.total))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func remotePackRow(_ pack: DeckRemotePack) -> some View {
        let installedDeck = decks.first { $0.slug == pack.slug }
        let installed = installedDeck != nil
        let isEmptyInstalled = installedDeck?.cardCount == 0
        let isDownloading = downloadingPackID == pack.id

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(pack.name)
                            .font(AppFont.sectionTitle())
                        Text(pack.cardCountLabel)
                            .font(AppFont.caption())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.successBackground(), in: Capsule())
                    }
                    Text(pack.detailText)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pack.licenseLabel)
                        .font(AppFont.caption())
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: AppSpacing.xs)

                if isDownloading {
                    importProgressView(for: pack.id)
                } else if isEmptyInstalled || !installed {
                    deckIconButton(systemImage: "arrow.down.circle", label: L10n.deckDownload) {
                        downloadRemotePack(pack)
                    }
                } else {
                    Label(L10n.deckInstalled, systemImage: "checkmark.seal.fill")
                        .font(AppFont.caption())
                        .foregroundStyle(.green)
                }
            }

            Link(destination: pack.attributionURL) {
                Text(L10n.deckRemoteViewSource)
                    .font(AppFont.caption())
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func communityRow(_ entry: DeckCommunityEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(entry.name)
                            .font(AppFont.sectionTitle())
                        if let countLabel = entry.cardCountLabel {
                            Text(countLabel)
                                .font(AppFont.caption())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColor.warningBackground(), in: Capsule())
                        }
                    }
                    Text(entry.detailText)
                        .font(AppFont.caption())
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
            AppIcon.symbol(systemImage)
                .frame(width: 32, height: 32)
                .foregroundStyle(AppColor.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func downloadRemotePack(_ pack: DeckRemotePack) {
        downloadingPackID = pack.id
        importProgress = ImportProgressState(key: pack.id, current: 0, total: pack.cardCount)
        Task { @MainActor in
            defer {
                downloadingPackID = nil
                importProgress = nil
            }
            do {
                let result = try await DeckDownloadService.downloadAndInstall(
                    pack: pack,
                    in: modelContext
                ) { current, total in
                    importProgress = ImportProgressState(key: pack.id, current: current, total: total)
                }
                selectedDeckID = result.deck.id
                DeckSettings.lastSelectedDeckID = result.deck.id
                checkedDeckIDs.insert(result.deck.id)
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
            checkedDeckIDs.remove(deck.id)
            if selectedDeckID == deck.id {
                let fallback = DeckService.fetchOrCreateDefault(in: modelContext)
                selectedDeckID = fallback.id
                DeckSettings.lastSelectedDeckID = fallback.id
            }
        } catch {
            showResult(title: L10n.deckDeleteFailed, message: error.localizedDescription)
        }
    }

    private func handleDeckJSONImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImportingJSON = true
            importProgress = ImportProgressState(key: "deck-json", current: 0, total: 1)
            Task { @MainActor in
                defer {
                    isImportingJSON = false
                    importProgress = nil
                }
                do {
                    let data = try JSONImportSupport.readImportData(from: url)
                    let imported: BackupService.JSONImportMergeResult
                    if JSONImportSupport.hasDeckInfo(data) {
                        imported = try await BackupService.importJSONMerge(data: data, into: modelContext)
                    } else {
                        let targets = checkedDecks
                        guard !targets.isEmpty else {
                            showResult(
                                title: L10n.deckImportFailed,
                                message: L10n.deckImportNeedSelectionForNoDeckInfo
                            )
                            return
                        }
                        imported = try await BackupService.importJSONMerge(
                            data: data,
                            into: modelContext,
                            targetDecks: targets
                        )
                    }
                    reloadDecks()
                    if let deckName = imported.deckName,
                       let deck = DeckService.fetchDeck(name: deckName, in: modelContext) {
                        selectedDeckID = deck.id
                        DeckSettings.lastSelectedDeckID = deck.id
                    }
                    showResult(
                        title: L10n.deckImportComplete,
                        message: imported.summaryMessage
                    )
                } catch {
                    showResult(
                        title: L10n.deckImportFailed,
                        message: JSONImportSupport.message(for: error, expecting: .backup)
                    )
                }
            }
        case .failure(let error):
            guard !error.isFileImporterCancellation else { return }
            showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
        }
    }

    private func handleApkgImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImportingApkg = true
            importProgress = ImportProgressState(key: "apkg", current: 0, total: 1)
            Task { @MainActor in
                defer {
                    isImportingApkg = false
                    importProgress = nil
                }
                do {
                    let data = try BackupDocumentSupport.readData(from: url)
                    let imported: ApkgImportService.ImportResult
                    if try ApkgImportService.hasDeckInfo(in: data) {
                        imported = try await ApkgImportService.importApkgAsync(
                            data: data,
                            context: modelContext
                        ) { current, total in
                            importProgress = ImportProgressState(key: "apkg", current: current, total: total)
                        }
                    } else {
                        let targets = checkedDecks
                        guard !targets.isEmpty else {
                            showResult(
                                title: L10n.deckImportFailed,
                                message: L10n.deckImportNeedSelectionForNoDeckInfo
                            )
                            return
                        }
                        imported = try await ApkgImportService.importApkgAsync(
                            data: data,
                            context: modelContext,
                            targetDecks: targets
                        ) { current, total in
                            importProgress = ImportProgressState(key: "apkg", current: current, total: total)
                        }
                    }
                    reloadDecks()
                    if let deckName = imported.primaryDeckName,
                       let deck = DeckService.fetchDeck(name: deckName, in: modelContext) {
                        selectedDeckID = deck.id
                        DeckSettings.lastSelectedDeckID = deck.id
                    }
                    showResult(
                        title: L10n.deckImportComplete,
                        message: imported.summaryMessage
                    )
                } catch {
                    showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
                }
            }
        case .failure(let error):
            guard !error.isFileImporterCancellation else { return }
            showResult(title: L10n.deckImportFailed, message: error.localizedDescription)
        }
    }

    private func beginFileImport(_ mode: DeckFileImportMode) {
        fileImportMode = mode
        allowedImportTypes = mode.contentTypes
        showUnifiedFileImporter = true
    }

    private func handleUnifiedFileImport(_ result: Result<[URL], Error>) {
        guard let mode = fileImportMode else { return }
        defer { fileImportMode = nil }

        switch mode {
        case .deckJSON:
            handleDeckJSONImport(singleURLResult(from: result))
        case .apkg:
            handleApkgImport(singleURLResult(from: result))
        }
    }

    private func singleURLResult(from result: Result<[URL], Error>) -> Result<URL, Error> {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return .failure(CocoaError(.fileNoSuchFile))
            }
            return .success(url)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func fetchAllCards() -> [FlashCard] {
        (try? modelContext.fetch(FetchDescriptor<FlashCard>())) ?? []
    }

    private func exportCheckedDecksJSON() {
        guard !checkedDeckIDs.isEmpty else {
            showResult(title: L10n.exportFailed, message: L10n.deckExportNeedSelection)
            return
        }
        guard checkedCardCount > 0 else {
            showResult(title: L10n.exportFailed, message: L10n.apkgExportEmpty)
            return
        }

        isPreparingExport = true
        Task { @MainActor in
            defer { isPreparingExport = false }
            do {
                let data = try BackupService.export(
                    checkedDeckIDs: checkedDeckIDs,
                    cards: fetchAllCards(),
                    decks: decks
                )
                let filename: String
                if checkedDeckIDs.count == 1, let deck = checkedDecks.first {
                    filename = ApkgExportService.sanitizedFilename(deck.name)
                } else {
                    filename = BackupService.defaultFilename
                }
                presentJSONExport(data: data, filename: filename)
            } catch {
                showResult(title: L10n.exportFailed, message: error.localizedDescription)
            }
        }
    }

    private func exportCheckedDecksApkg() {
        guard !checkedDeckIDs.isEmpty else {
            showResult(title: L10n.exportFailed, message: L10n.deckExportNeedSelection)
            return
        }

        let cards = fetchCards(in: checkedDeckIDs)
        guard !cards.isEmpty else {
            showResult(title: L10n.exportFailed, message: L10n.apkgExportEmpty)
            return
        }

        isPreparingExport = true
        Task { @MainActor in
            defer { isPreparingExport = false }
            do {
                let deckName = checkedDeckIDs.count == 1 ? checkedDecks.first?.name : nil
                let data = try ApkgExportService.export(cards: cards, deckName: deckName)
                let filename: String
                if checkedDeckIDs.count == 1, let deck = checkedDecks.first {
                    filename = ApkgExportService.sanitizedFilename(deck.name)
                } else {
                    filename = ApkgExportService.defaultFilename
                }
                presentApkgExport(data: data, filename: filename)
            } catch {
                showResult(title: L10n.exportFailed, message: error.localizedDescription)
            }
        }
    }

    private func fetchCards(in deckIDs: Set<UUID>) -> [FlashCard] {
        fetchAllCards().filter { card in
            guard let deckID = card.deck?.id else { return false }
            return deckIDs.contains(deckID)
        }
    }

    private func presentJSONExport(data: Data, filename: String) {
        exportDocument = BackupDocument(data: data)
        jsonExportFilename = filename
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            showJSONExporter = true
        }
    }

    private func presentApkgExport(data: Data, filename: String) {
        apkgDocument = ApkgDocument(data: data)
        apkgExportFilename = filename
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            showApkgExporter = true
        }
    }

    private func exportDeckApkg(_ deck: Deck) {
        checkedDeckIDs = [deck.id]
        exportCheckedDecksApkg()
    }

    private func fetchCards(for deck: Deck) -> [FlashCard] {
        let deckID = deck.id
        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.deck?.id == deckID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func showResult(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
        if title == L10n.importComplete || title == L10n.deckImportComplete {
            ToastCenter.shared.show(message)
        }
    }
}

private enum DeckFileImportMode {
    case deckJSON
    case apkg

    var contentTypes: [UTType] {
        switch self {
        case .deckJSON:
            return [.json]
        case .apkg:
            return [.apkg, .zip, .data]
        }
    }
}

private extension Error {
    var isFileImporterCancellation: Bool {
        let nsError = self as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
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
