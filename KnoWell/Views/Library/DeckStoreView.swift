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
    @State private var editingDeck: Deck?
    @State private var showUnifiedFileImporter = false
    @State private var fileImportMode: DeckFileImportMode?
    @State private var allowedImportTypes: [UTType] = [.json]
    @State private var pendingFileExport: PendingFileExport?
    @State private var showFileExporter = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var downloadingPackID: String?
    @State private var importProgress: ImportProgressState?
    @State private var isImportingJSON = false
    @State private var isImportingApkg = false
    @State private var isPreparingExport = false
    @State private var showApkgImportGuide = false
    @State private var deckPendingClear: Deck?
    @State private var deckPendingActions: Deck?
    @State private var deckPendingStats: Deck?
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
        fetchCards(in: checkedDeckIDs).count
    }

    private var allDecksSelected: Bool {
        !decks.isEmpty && checkedDeckIDs.count == decks.count
    }

    var body: some View {
        storeContent
            .appPageBackground()
            .navigationTitle(L10n.deckStoreTitle)
            .navigationBarTitleDisplayMode(.inline)
            .loadingOverlay(isPresented: isImportBusy, message: busyOverlayMessage)
            .toolbar { createDeckToolbar }
            .sheet(isPresented: $showCreateDeck) {
                DeckEditorSheet { deck in
                    selectedDeckID = deck.id
                    DeckSettings.lastSelectedDeckID = deck.id
                    checkedDeckIDs = [deck.id]
                    reloadDecks()
                    DeckCardCountService.notifyCatalogChanged()
                }
            }
            .sheet(item: $editingDeck) { deck in
                DeckEditorSheet(deck: deck) { _ in
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
                isPresented: $showFileExporter,
                document: pendingFileExport?.document,
                contentType: pendingFileExport?.contentType ?? .json,
                defaultFilename: pendingFileExport?.filename ?? BackupService.defaultFilename
            ) { result in
                let recordsBackupCompletion = pendingFileExport?.recordsBackupCompletion == true
                defer { pendingFileExport = nil }
                switch result {
                case .success:
                    if recordsBackupCompletion {
                        BackupReminderService.recordBackupCompleted()
                        ToastCenter.shared.show(L10n.exportBackupSuccess)
                    }
                case .failure(let error):
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
            .sheet(item: $deckPendingStats) { deck in
                NavigationStack {
                    DeckStatisticsView(deck: deck)
                }
            }
            .appActionSheet(
                isPresented: Binding(
                    get: { deckPendingActions != nil },
                    set: { if !$0 { deckPendingActions = nil } }
                ),
                actions: deckActionItems
            )
            .appConfirmSheet(
                isPresented: Binding(
                    get: { deckPendingClear != nil },
                    set: { if !$0 { deckPendingClear = nil } }
                ),
                title: L10n.deckClearTitle,
                message: deckPendingClear.map { L10n.deckClearMessage($0.name) },
                confirmTitle: L10n.deckClear,
                confirmRole: .destructive
            ) {
                guard let deck = deckPendingClear else { return }
                clearDeck(deck)
                deckPendingClear = nil
            }
            .onAppear {
                reloadDecks()
                seedCheckedDecksIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
                reloadDecks()
            }
    }

    private var storeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                catalogLinkCard
                if !checkedDeckIDs.isEmpty {
                    selectionHintBar
                }
                myDecksCard
                deckActionsCard
            }
            .padding(AppSpacing.md)
        }
    }

    @ToolbarContentBuilder
    private var createDeckToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(L10n.deckCreateTitle) {
                showCreateDeck = true
            }
            .font(AppFont.helper().weight(.semibold))
        }
    }

    private var deckActionItems: [AppSheetAction] {
        guard let deck = deckPendingActions else { return [] }
        var items: [AppSheetAction] = [
            AppSheetAction(title: L10n.deckEdit, systemImage: "pencil") {
                editingDeck = deck
            },
            AppSheetAction(title: L10n.deckStatisticsOverview, systemImage: "chart.bar.xaxis") {
                deckPendingStats = deck
            }
        ]
        if DeckService.canDelete(deck) {
            items.append(
                AppSheetAction(title: L10n.deckDelete, systemImage: "trash", role: .destructive) {
                    deleteDeck(deck)
                }
            )
        } else if deck.cardCount > 0 {
            items.append(
                AppSheetAction(title: L10n.deckClear, systemImage: "xmark.circle", role: .destructive) {
                    deckPendingClear = deck
                }
            )
        }
        return items
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

    /// Default: tap selects that deck only. Use Select All for batch export.
    private func selectDeck(_ deck: Deck) {
        checkedDeckIDs = [deck.id]
        syncPrimaryDeckSelection()
    }

    private func toggleSelectAllDecks() {
        if allDecksSelected {
            if let selectedDeckID, decks.contains(where: { $0.id == selectedDeckID }) {
                checkedDeckIDs = [selectedDeckID]
            } else if let first = decks.first {
                checkedDeckIDs = [first.id]
            } else {
                checkedDeckIDs.removeAll()
            }
        } else {
            checkedDeckIDs = Set(decks.map(\.id))
        }
        syncPrimaryDeckSelection()
    }

    private func reloadDecks() {
        DeckCardCountService.recountAll(in: modelContext)
        cachedDecks = DeckService.refreshDecks(in: modelContext)
    }

    private var selectionHintBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColor.accent)
            Text(L10n.deckSelectedExportHint(checkedDeckIDs.count))
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if checkedCardCount > 0 {
                Menu {
                    Button(L10n.deckQuickExportDeckApkg) {
                        exportCheckedDecksApkg()
                    }
                    Button(L10n.deckQuickExportDeckJSON) {
                        exportCheckedDecksJSON()
                    }
                } label: {
                    Text(L10n.deckQuickExportAction)
                        .font(AppFont.caption().weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .background(AppColor.accentBackground(0.12), in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
    }

    private var myDecksCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text(L10n.deckMyDecks)
                        .font(AppFont.sectionTitle())
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !decks.isEmpty {
                        Button(allDecksSelected ? L10n.deckDeselectAll : L10n.deckSelectAll) {
                            toggleSelectAllDecks()
                        }
                        .font(AppFont.caption().weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                    }
                }

                if decks.isEmpty {
                    Text(L10n.deckEmpty)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(decks) { deck in
                        deckRow(deck)
                        if deck.id != decks.last?.id {
                            Divider().overlay(AppColor.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        let due = deck.dueCount
        let total = max(deck.cardCount, 0)
        let isChecked = checkedDeckIDs.contains(deck.id)
        let isDefault = DeckService.isDefaultDeck(deck)
        let nameColor = isDefault ? AppColor.textSecondary : AppColor.textPrimary

        return HStack(alignment: .center, spacing: AppSpacing.sm) {
            Button {
                selectDeck(deck)
            } label: {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChecked ? AppColor.accent : AppColor.textTertiary)
                        .font(.title3)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                            Text(deck.name)
                                .font(AppFont.body().weight(isDefault ? .medium : .semibold))
                                .foregroundStyle(nameColor)
                                .lineLimit(1)
                            if isDefault {
                                Text(L10n.deckDefaultBadge)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppColor.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColor.surfaceMuted, in: Capsule())
                            }
                            Spacer(minLength: 4)
                            Text("\(total)")
                                .font(AppFont.caption().weight(.medium))
                                .foregroundStyle(AppColor.textSecondary)
                                .monospacedDigit()
                            Text("/")
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textTertiary)
                            Text("\(due)")
                                .font(AppFont.caption().weight(.semibold))
                                .foregroundStyle(due > 0 ? AppColor.accent : AppColor.textTertiary)
                                .monospacedDigit()
                                .accessibilityLabel(L10n.deckDueShort(due))
                        }

                        if let detail = deck.detailText, !detail.isEmpty {
                            Text(detail)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textTertiary)
                                .lineLimit(1)
                        }
                        if total > 0 {
                            DeckDueMeter(dueCount: due, totalCount: total)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isDefault ? 0.82 : 1)
            }
            .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.9))

            Button {
                deckPendingActions = deck
            } label: {
                Text(L10n.deckManageShort)
                    .font(AppFont.caption().weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColor.accentBackground(0.12), in: Capsule())
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel(L10n.deckManageShort)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var deckActionsCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L10n.deckActionsSection)
                    .font(AppFont.caption().weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)

                // Compact tool strip — Anki first, JSON muted underneath.
                VStack(spacing: AppSpacing.xs) {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: AppSpacing.xs
                    ) {
                        QuickActionChip(
                            systemImage: "square.and.arrow.down.fill",
                            title: L10n.deckQuickImportApkg,
                            isLoading: isImportingApkg,
                            isDisabled: isImportingJSON,
                            prominence: .compactPrimary
                        ) {
                            beginFileImport(.apkg)
                        }

                        QuickActionChip(
                            systemImage: "square.and.arrow.up.fill",
                            title: L10n.deckQuickExportDeckApkg,
                            isLoading: isPreparingExport,
                            isDisabled: checkedDeckIDs.isEmpty || checkedCardCount == 0,
                            prominence: .compactPrimary
                        ) {
                            exportCheckedDecksApkg()
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: AppSpacing.xs
                    ) {
                        QuickActionChip(
                            systemImage: "square.and.arrow.down",
                            title: L10n.deckQuickImportJSON,
                            isLoading: isImportingJSON,
                            isDisabled: isImportingApkg,
                            prominence: .compactSecondary
                        ) {
                            beginFileImport(.deckJSON)
                        }

                        QuickActionChip(
                            systemImage: "square.and.arrow.up",
                            title: L10n.deckQuickExportDeckJSON,
                            isLoading: isPreparingExport,
                            isDisabled: checkedDeckIDs.isEmpty || checkedCardCount == 0,
                            prominence: .compactSecondary
                        ) {
                            exportCheckedDecksJSON()
                        }
                    }
                }
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var catalogLinkCard: some View {
        NavigationLink {
            DeckCatalogView(selectedDeckID: $selectedDeckID)
        } label: {
            AppSurfaceCard {
                HStack(alignment: .center, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(L10n.deckCatalogTitle)
                            .font(AppFont.sectionTitle())
                            .foregroundStyle(AppColor.textPrimary)
                        Text(L10n.deckCatalogHeroLead)
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.deckCatalogSubtitle)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 36, height: 36)
                        .background(AppColor.accentBackground(0.14), in: Circle())
                }
                .padding(.vertical, AppSpacing.sm)
            }
        }
        .buttonStyle(SoftPressButtonStyle())
    }

    private var openSourceCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L10n.deckOpenSourceSection)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)

                ForEach(DeckRemoteCatalog.packs) { pack in
                    remotePackRow(pack)
                    if pack.id != DeckRemoteCatalog.packs.last?.id {
                        Spacer().frame(height: AppSpacing.sm)
                    }
                }
            }
        }
    }

    private var communityCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L10n.deckCommunitySection)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)

                ForEach(DeckCommunityCatalog.entries) { entry in
                    communityRow(entry)
                    if entry.id != DeckCommunityCatalog.entries.last?.id {
                        Spacer().frame(height: AppSpacing.sm)
                    }
                }

                Button {
                    showApkgImportGuide = true
                } label: {
                    Label(L10n.deckCommunityImportGuide, systemImage: "questionmark.circle")
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
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

    private func clearDeck(_ deck: Deck) {
        do {
            let count = try DeckService.clearDeck(deck, in: modelContext)
            reloadDecks()
            showResult(
                title: L10n.deckClearComplete,
                message: L10n.deckClearResult(deck.name, count: count)
            )
        } catch {
            showResult(title: L10n.deckClearFailed, message: error.localizedDescription)
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
                    let imported = try await ApkgImportService.importApkgAsync(
                        data: data,
                        context: modelContext
                    ) { current, total in
                        importProgress = ImportProgressState(key: "apkg", current: current, total: total)
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
            ToastCenter.shared.show(L10n.deckExportNeedSelection)
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
            ToastCenter.shared.show(L10n.deckExportNeedSelection)
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

    private func presentFileExport(
        data: Data,
        contentType: UTType,
        filename: String,
        recordsBackupCompletion: Bool
    ) {
        showFileExporter = false
        pendingFileExport = PendingFileExport(
            document: ExportFileDocument(data: data),
            contentType: contentType,
            filename: filename,
            recordsBackupCompletion: recordsBackupCompletion
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard pendingFileExport != nil else { return }
            showFileExporter = true
        }
    }

    private func presentJSONExport(data: Data, filename: String) {
        presentFileExport(
            data: data,
            contentType: .json,
            filename: filename,
            recordsBackupCompletion: true
        )
    }

    private func presentApkgExport(data: Data, filename: String) {
        presentFileExport(
            data: data,
            contentType: .apkg,
            filename: filename,
            recordsBackupCompletion: false
        )
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

private struct PendingFileExport {
    let document: ExportFileDocument
    let contentType: UTType
    let filename: String
    let recordsBackupCompletion: Bool
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

private struct DeckEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let deck: Deck?
    let onSaved: (Deck) -> Void

    @State private var name = ""
    @State private var detailText = ""
    @State private var errorMessage = ""

    init(deck: Deck? = nil, onSaved: @escaping (Deck) -> Void) {
        self.deck = deck
        self.onSaved = onSaved
    }

    private var isEditing: Bool { deck != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.deckNamePlaceholder, text: $name)
                TextField(L10n.deckDetailPlaceholder, text: $detailText, axis: .vertical)
                    .lineLimit(2...5)
            }
            .navigationTitle(isEditing ? L10n.deckEditTitle : L10n.deckCreateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? L10n.deckSave : L10n.add) {
                        saveDeck()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(L10n.deckEditFailed, isPresented: Binding(
                get: { !errorMessage.isEmpty },
                set: { if !$0 { errorMessage = "" } }
            )) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                name = deck?.name ?? ""
                detailText = deck?.detailText ?? ""
            }
        }
        .presentationDetents([.medium])
    }

    private func saveDeck() {
        do {
            if let deck {
                try DeckService.updateDeck(deck, name: name, detailText: detailText, in: modelContext)
                onSaved(deck)
            } else {
                let created = DeckService.createCustomDeck(
                    name: name,
                    detailText: detailText,
                    in: modelContext
                )
                onSaved(created)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DeckCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Binding var selectedDeckID: UUID?

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @State private var downloadingPackID: String?
    @State private var importProgress: CatalogImportProgress?
    @State private var showApkgImportGuide = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                openSourceCard
                communityCard
            }
            .padding(AppSpacing.md)
        }
        .appPageBackground()
        .navigationTitle(L10n.deckCatalogTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertTitle, isPresented: $showAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert(L10n.deckCommunityImportGuideTitle, isPresented: $showApkgImportGuide) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.deckCommunityImportGuideBody)
        }
    }

    private var openSourceCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L10n.deckOpenSourceSection)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)

                ForEach(DeckRemoteCatalog.packs) { pack in
                    remotePackRow(pack)
                    if pack.id != DeckRemoteCatalog.packs.last?.id {
                        Spacer().frame(height: AppSpacing.sm)
                    }
                }
            }
        }
    }

    private var communityCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L10n.deckCommunitySection)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)

                ForEach(DeckCommunityCatalog.entries) { entry in
                    communityRow(entry)
                    if entry.id != DeckCommunityCatalog.entries.last?.id {
                        Spacer().frame(height: AppSpacing.sm)
                    }
                }

                Button {
                    showApkgImportGuide = true
                } label: {
                    Label(L10n.deckCommunityImportGuide, systemImage: "questionmark.circle")
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
    }

    private struct CatalogImportProgress {
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
                    catalogIconButton(systemImage: "arrow.down.circle", label: L10n.deckDownload) {
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

                catalogIconButton(systemImage: "safari", label: L10n.deckCommunityOpenAnkiWeb) {
                    openURL(entry.ankiWebURL)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func catalogIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
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
        importProgress = CatalogImportProgress(key: pack.id, current: 0, total: pack.cardCount)
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
                    importProgress = CatalogImportProgress(key: pack.id, current: current, total: total)
                }
                selectedDeckID = result.deck.id
                DeckSettings.lastSelectedDeckID = result.deck.id
                showResult(
                    title: L10n.deckInstallComplete,
                    message: result.importedCards > 0
                        ? L10n.deckInstallWithCards(result.deck.name, count: result.importedCards)
                        : L10n.deckInstallEmpty(result.deck.name)
                )
            } catch {
                showResult(title: L10n.deckDownloadFailed, message: error.localizedDescription)
            }
        }
    }

    private func showResult(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

#Preview {
    NavigationStack {
        DeckStoreView(selectedDeckID: .constant(nil))
    }
    .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}
