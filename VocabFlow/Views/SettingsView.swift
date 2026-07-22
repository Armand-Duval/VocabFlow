import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [FlashCard]
    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var allDecks: [Deck]

    @State private var apiKey = APISettings.kimiAPIKey
    @State private var selectedModel = APISettings.kimiModel
    @State private var showKey = false
    @State private var saved = false

    @State private var exportDocument: BackupDocument?
    @State private var apkgDocument: ApkgDocument?
    @State private var showJSONExporter = false
    @State private var showApkgExporter = false
    @State private var showImporter = false
    @State private var showImportOptions = false
    @State private var pendingImportData: Data?
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false

    @State private var showImportHelp = false
    @State private var dailyNewLimit = ReviewSettings.dailyNewLimit
    @State private var dailyReviewLimit = ReviewSettings.dailyReviewLimit
    @State private var reminderEnabled = ReviewReminderService.isEnabled
    @State private var reminderTime = ReviewReminderService.reminderDate

    @State private var showResetAllConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var settingsDeckID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                reviewLimitsSection
                aiSection
                importHelpSection
                dataSection
                aboutSection
                saveSection
            }
            .navigationTitle(L10n.settingsTitle)
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
            .onAppear {
                if settingsDeckID == nil {
                    settingsDeckID = DeckSettings.lastSelectedDeckID
                }
            }
            .alert(L10n.settingsSavedTitle, isPresented: $saved) {
                Button(L10n.ok, role: .cancel) {}
            }
            .alert(backupAlertTitle, isPresented: $showBackupAlert) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(backupAlertMessage)
            }
            .confirmationDialog(L10n.importModeTitle, isPresented: $showImportOptions, titleVisibility: .visible) {
                Button(L10n.importModeMerge) {
                    performMergeImport()
                }
                Button(L10n.importModeReplace, role: .destructive) {
                    performReplaceImport()
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.importModeMessage)
            }
            .confirmationDialog(L10n.settingsResetAllSRS, isPresented: $showResetAllConfirm, titleVisibility: .visible) {
                Button(L10n.settingsResetAllSRS) {
                    resetAllProgress()
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.settingsResetAllSRSMessage)
            }
            .confirmationDialog(L10n.settingsDeleteAllCards, isPresented: $showDeleteAllConfirm, titleVisibility: .visible) {
                Button(L10n.settingsDeleteAllCards, role: .destructive) {
                    deleteAllCards()
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.settingsDeleteAllCardsMessage)
            }
            .fileExporter(
                isPresented: $showJSONExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: BackupService.defaultFilename
            ) { result in
                if case .failure(let error) = result {
                    showBackupResult(title: L10n.exportFailed, message: error.localizedDescription)
                }
            }
            .fileExporter(
                isPresented: $showApkgExporter,
                document: apkgDocument,
                contentType: .apkg,
                defaultFilename: ApkgExportService.defaultFilename
            ) { result in
                if case .failure(let error) = result {
                    showBackupResult(title: L10n.exportFailed, message: error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleImportSelection(result)
            }
        }
    }

    private var reviewLimitsSection: some View {
        Section {
            Stepper(value: $dailyNewLimit, in: 0...999) {
                Text(L10n.settingsReviewNewLimit(dailyNewLimit))
            }
            Stepper(value: $dailyReviewLimit, in: 0...999) {
                Text(L10n.settingsReviewReviewLimit(dailyReviewLimit))
            }

            Toggle(L10n.settingsReviewReminderEnabled, isOn: $reminderEnabled)
                .onChange(of: reminderEnabled) { _, enabled in
                    guard enabled else { return }
                    Task {
                        _ = await ShareExtensionNotifier.requestAuthorizationIfNeeded()
                    }
                }

            if reminderEnabled {
                DatePicker(
                    L10n.settingsReviewReminderTime,
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text(L10n.settingsReviewSection)
        } footer: {
            Text(L10n.settingsReviewFooter)
        }
    }

    private var aiSection: some View {
        Section {
            HStack {
                if showKey {
                    TextField(L10n.apiKeyPlaceholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } else {
                    SecureField(L10n.apiKeyPlaceholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Picker(L10n.modelSection, selection: $selectedModel) {
                ForEach(APISettings.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Label {
                Text(APISettings.keySourceDescription)
                    .foregroundStyle(APISettings.canUseKimi ? Color.primary : Color.orange)
            } icon: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }
        } header: {
            Text(L10n.settingsAISection)
        } footer: {
            Text(L10n.apiKeyFooter)
        }
    }

    private var importHelpSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showImportHelp) {
                Label(L10n.importShareStep1, systemImage: "square.and.arrow.up")
                Label(L10n.importShareStep2, systemImage: "checkmark.circle")

                Label(L10n.importCopyStep1, systemImage: "book.closed")
                Label(L10n.importCopyStep2, systemImage: "doc.on.doc")
                Label(L10n.importCopyStep3, systemImage: "arrow.right.circle")
            } label: {
                Label(L10n.importHelpTitle, systemImage: "arrow.down.doc")
            }
        } header: {
            Text(L10n.settingsImportSection)
        } footer: {
            Text(L10n.importCopyFooter)
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                DeckStoreView(selectedDeckID: $settingsDeckID)
            } label: {
                Label(L10n.deckManage, systemImage: "books.vertical")
            }

            Button {
                exportJSONBackup()
            } label: {
                Label(L10n.exportBackup, systemImage: "doc.text")
            }

            Button {
                exportApkg()
            } label: {
                Label(L10n.exportApkg, systemImage: "square.and.arrow.up")
            }
            .disabled(allCards.isEmpty)

            Button {
                showImporter = true
            } label: {
                Label(L10n.importBackup, systemImage: "square.and.arrow.down")
            }

            Button {
                showResetAllConfirm = true
            } label: {
                Label(L10n.settingsResetAllSRS, systemImage: "arrow.counterclockwise")
            }
            .disabled(allCards.isEmpty)

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label(L10n.settingsDeleteAllCards, systemImage: "trash")
            }
            .disabled(allCards.isEmpty)
        } header: {
            Text(L10n.settingsDataSection)
        } footer: {
            Text(L10n.settingsDataFooter(allCards.count))
        }
    }

    private var aboutSection: some View {
        Section(L10n.settingsAboutSection) {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label(L10n.privacyTitle, systemImage: "hand.raised")
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button(L10n.saveSettings) {
                saveSettings()
            }
        }
    }

    private var statusIcon: String {
        if APISettings.canUseKimi { "checkmark.circle.fill" }
        else { "exclamationmark.circle" }
    }

    private var statusColor: Color {
        if APISettings.canUseKimi { .green }
        else { .orange }
    }

    private func saveSettings() {
        APISettings.kimiAPIKey = apiKey
        APISettings.kimiModel = selectedModel
        ReviewSettings.dailyNewLimit = dailyNewLimit
        ReviewSettings.dailyReviewLimit = dailyReviewLimit
        ReviewReminderService.isEnabled = reminderEnabled
        ReviewReminderService.applyReminderTime(reminderTime)
        ReviewReminderService.reschedule(dueCount: allCards.filter { ReviewScheduler.isDue($0) }.count)
        saved = true
    }

    private func exportJSONBackup() {
        do {
            let data = try BackupService.export(cards: allCards, decks: allDecks)
            exportDocument = BackupDocument(data: data)
            showJSONExporter = true
        } catch {
            showBackupResult(title: L10n.exportFailed, message: error.localizedDescription)
        }
    }

    private func exportApkg() {
        do {
            let data = try ApkgExportService.export(cards: allCards)
            apkgDocument = ApkgDocument(data: data)
            showApkgExporter = true
        } catch {
            showBackupResult(title: L10n.exportFailed, message: error.localizedDescription)
        }
    }

    private func resetAllProgress() {
        allCards.forEach { ReviewScheduler.resetProgress(for: $0) }
        showBackupResult(title: L10n.settingsResetAllSRSDone, message: L10n.settingsResetAllSRSDoneMessage)
    }

    private func deleteAllCards() {
        allCards.forEach { modelContext.delete($0) }
        showBackupResult(title: L10n.settingsDeleteAllDone, message: L10n.settingsDeleteAllDoneMessage)
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                pendingImportData = try BackupDocumentSupport.readData(from: url)
                showImportOptions = true
            } catch {
                showBackupResult(title: L10n.readFailed, message: error.localizedDescription)
            }
        case .failure(let error):
            showBackupResult(title: L10n.importFailed, message: error.localizedDescription)
        }
    }

    private func performMergeImport() {
        guard let data = pendingImportData else { return }
        do {
            let result = try BackupService.importMerge(data: data, into: modelContext)
            showBackupResult(
                title: L10n.importComplete,
                message: L10n.importMergeResult(added: result.added, updated: result.updated)
            )
        } catch {
            showBackupResult(title: L10n.importFailed, message: error.localizedDescription)
        }
        pendingImportData = nil
    }

    private func performReplaceImport() {
        guard let data = pendingImportData else { return }
        do {
            let count = try BackupService.importReplace(data: data, into: modelContext)
            showBackupResult(title: L10n.importComplete, message: L10n.importReplaceResult(count))
        } catch {
            showBackupResult(title: L10n.importFailed, message: error.localizedDescription)
        }
        pendingImportData = nil
    }

    private func showBackupResult(title: String, message: String) {
        backupAlertTitle = title
        backupAlertMessage = message
        showBackupAlert = true
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [FlashCard.self, Deck.self], inMemory: true)
}
