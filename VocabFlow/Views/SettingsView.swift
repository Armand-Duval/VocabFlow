import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    @State private var apiKey = APISettings.kimiAPIKey
    @State private var selectedModel = APISettings.kimiModel
    @State private var showKey = false
    @State private var saved = false
    @State private var hasAnyCards = false

    @State private var showImportHelp = false
    @State private var reminderEnabled = ReviewReminderService.isEnabled
    @State private var reminderTime = ReviewReminderService.reminderDate

    @State private var showResetAllConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var maintenanceAlertTitle = ""
    @State private var maintenanceAlertMessage = ""
    @State private var showMaintenanceAlert = false

    var body: some View {
        @Bindable var reviewSettings = reviewSettings

        NavigationStack {
            Form {
                Section {
                    Stepper(value: $reviewSettings.dailyNewLimit, in: 0...999) {
                        Text(L10n.settingsReviewNewLimit(reviewSettings.dailyNewLimit))
                    }
                    Stepper(value: $reviewSettings.dailyReviewLimit, in: 0...999) {
                        Text(L10n.settingsReviewReviewLimit(reviewSettings.dailyReviewLimit))
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

                aiSection
                importHelpSection
                maintenanceSection
                aboutSection
                saveSection
            }
            .navigationTitle(L10n.settingsTitle)
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
            .onAppear {
                reviewSettings.reloadFromPersistence()
            }
            .task {
                await refreshHasAnyCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviewQueueDidChange)) { _ in
                Task { await refreshHasAnyCards() }
            }
            .alert(L10n.settingsSavedTitle, isPresented: $saved) {
                Button(L10n.ok, role: .cancel) {}
            }
            .alert(maintenanceAlertTitle, isPresented: $showMaintenanceAlert) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(maintenanceAlertMessage)
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

    private var maintenanceSection: some View {
        Section {
            Button {
                showResetAllConfirm = true
            } label: {
                Label(L10n.settingsResetAllSRS, systemImage: "arrow.counterclockwise")
            }
            .disabled(!hasAnyCards)

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label(L10n.settingsDeleteAllCards, systemImage: "trash")
            }
            .disabled(!hasAnyCards)
        } header: {
            Text(L10n.settingsMaintenanceSection)
        } footer: {
            Text(L10n.settingsMaintenanceFooter)
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
        reviewSettings.persist()
        ReviewReminderService.isEnabled = reminderEnabled
        ReviewReminderService.applyReminderTime(reminderTime)
        ReviewReminderService.reschedule(dueCount: ReviewStatusStore.dueCount)
        saved = true
    }

    @MainActor
    private func refreshHasAnyCards() async {
        await Task.yield()
        var descriptor = FetchDescriptor<FlashCard>()
        descriptor.fetchLimit = 1
        hasAnyCards = !((try? modelContext.fetch(descriptor)) ?? []).isEmpty
    }

    private func fetchAllCards() -> [FlashCard] {
        (try? modelContext.fetch(FetchDescriptor<FlashCard>())) ?? []
    }

    private func resetAllProgress() {
        fetchAllCards().forEach { ReviewScheduler.resetProgress(for: $0) }
        showMaintenanceResult(title: L10n.settingsResetAllSRSDone, message: L10n.settingsResetAllSRSDoneMessage)
    }

    private func deleteAllCards() {
        fetchAllCards().forEach { modelContext.delete($0) }
        hasAnyCards = false
        showMaintenanceResult(title: L10n.settingsDeleteAllDone, message: L10n.settingsDeleteAllDoneMessage)
    }

    private func showMaintenanceResult(title: String, message: String) {
        maintenanceAlertTitle = title
        maintenanceAlertMessage = message
        showMaintenanceAlert = true
    }
}

#Preview {
    SettingsView()
        .environment(ReviewSettingsStore.shared)
        .modelContainer(for: [FlashCard.self, Deck.self], inMemory: true)
}
