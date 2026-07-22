import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [FlashCard]

    @State private var apiKey = APISettings.kimiAPIKey
    @State private var selectedModel = APISettings.kimiModel
    @State private var showKey = false
    @State private var saved = false

    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showImportOptions = false
    @State private var pendingImportData: Data?
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                modelSection
                saveSection
                statusSection
                importGuideSection
                backupSection
            }
            .navigationTitle(L10n.settingsTitle)
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
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
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: BackupService.defaultFilename
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

    private var apiSection: some View {
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
        } header: {
            Text(L10n.apiKeySection)
        } footer: {
            Text(L10n.apiKeyFooter)
        }
    }

    private var modelSection: some View {
        Section(L10n.modelSection) {
            Picker(L10n.modelSection, selection: $selectedModel) {
                ForEach(APISettings.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button(L10n.saveSettings) {
                APISettings.kimiAPIKey = apiKey
                APISettings.kimiModel = selectedModel
                saved = true
            }
        }
    }

    private var statusSection: some View {
        Section(L10n.statusSection) {
            Label {
                Text(APISettings.keySourceDescription)
            } icon: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }

            if APISettings.canUseKimi {
                Text(L10n.statusReady)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.statusMissingKey)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var importGuideSection: some View {
        Group {
            Section {
                Label(L10n.importShareStep1, systemImage: "square.and.arrow.up")
                Label(L10n.importShareStep2, systemImage: "checkmark.circle")
            } header: {
                Text(L10n.importShareSection)
            }

            Section {
                Label(L10n.importCopyStep1, systemImage: "book.closed")
                Label(L10n.importCopyStep2, systemImage: "doc.on.doc")
                Label(L10n.importCopyStep3, systemImage: "arrow.right.circle")
            } header: {
                Text(L10n.importCopySection)
            } footer: {
                Text(L10n.importCopyFooter)
            }
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label(L10n.exportBackup, systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label(L10n.importBackup, systemImage: "square.and.arrow.down")
            }
        } header: {
            Text(L10n.backupSection)
        } footer: {
            Text(L10n.backupFooter(allCards.count))
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

    private func exportBackup() {
        do {
            let data = try BackupService.export(cards: allCards)
            exportDocument = BackupDocument(data: data)
            showExporter = true
        } catch {
            showBackupResult(title: L10n.exportFailed, message: error.localizedDescription)
        }
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
        .modelContainer(for: FlashCard.self, inMemory: true)
}
