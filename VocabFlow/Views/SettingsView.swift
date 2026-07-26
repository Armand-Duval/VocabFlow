import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    @State private var apiKey = APISettings.kimiAPIKey
    @State private var selectedModel = APISettings.kimiModel
    @State private var showKey = false
    @State private var hasAnyCards = false
    @State private var isTestingAPI = false

    @State private var showImportHelp = false
    @State private var showHelpCenter = false
    @State private var reminderEnabled = ReviewReminderService.isEnabled
    @State private var reminderTime = ReviewReminderService.reminderDate
    @State private var backupReminderEnabled = BackupReminderService.isEnabled
    @State private var showDeckStore = false

    @State private var showResetAllConfirm = false
    @State private var maintenanceAlertTitle = ""
    @State private var maintenanceAlertMessage = ""
    @State private var showMaintenanceAlert = false

    var body: some View {
        @Bindable var reviewSettings = reviewSettings

        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    reviewCard(
                        dailyNewLimit: $reviewSettings.dailyNewLimit,
                        dailyReviewLimit: $reviewSettings.dailyReviewLimit
                    )
                    aiCard
                    importExportCard
                    maintenanceCard
                    aboutCard
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)
            }
            .appPageBackground()
            .appNavTitle(L10n.settingsTitle)
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveFooter
            }
            .navigationDestination(isPresented: $showDeckStore) {
                DeckStoreView(selectedDeckID: .constant(DeckSettings.lastSelectedDeckID))
            }
            .onAppear {
                reviewSettings.reloadFromPersistence()
            }
            .task {
                await refreshHasAnyCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviewQueueDidChange)) { _ in
                Task { await refreshHasAnyCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataMaintenanceDidComplete)) { _ in
                Task { await refreshHasAnyCards() }
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
        }
    }

    private var saveFooter: some View {
        Button(L10n.saveSettings, action: saveSettings)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xs)
            .background(.bar)
    }

    private func reviewCard(
        dailyNewLimit: Binding<Int>,
        dailyReviewLimit: Binding<Int>
    ) -> some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Toggle(L10n.settingsReviewUnlimited, isOn: unlimitedReviewBinding)

                if !isUnlimitedReview {
                    SettingsDivider()
                    Stepper(value: dailyNewLimit, in: 0...999) {
                        Text(L10n.settingsReviewNewLimit(dailyNewLimit.wrappedValue))
                            .font(AppFont.secondary())
                    }
                    SettingsDivider()
                    Stepper(value: dailyReviewLimit, in: 0...999) {
                        Text(L10n.settingsReviewReviewLimit(dailyReviewLimit.wrappedValue))
                            .font(AppFont.secondary())
                    }
                }

                SettingsDivider()
                Toggle(L10n.settingsReviewReminderEnabled, isOn: $reminderEnabled)
                    .onChange(of: reminderEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = await ShareExtensionNotifier.requestAuthorizationIfNeeded()
                        }
                    }

                if reminderEnabled {
                    SettingsDivider()
                    DatePicker(
                        L10n.settingsReviewReminderTime,
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .font(AppFont.secondary())
                }

                SettingsDivider()
                Toggle(L10n.settingsBackupReminderEnabled, isOn: $backupReminderEnabled)
            }
        }
    }

    private var aiCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Group {
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
                    }
                    .font(AppFont.secondary())

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }

                SettingsDivider()

                Picker(L10n.modelSection, selection: $selectedModel) {
                    ForEach(APISettings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .font(AppFont.secondary())

                SettingsDivider()

                Button {
                    Task { await testAPIConnection() }
                } label: {
                    HStack {
                        if isTestingAPI {
                            ProgressView()
                        }
                        Text(isTestingAPI ? L10n.settingsTestingAPI : L10n.settingsTestAPI)
                            .font(AppFont.secondary())
                        Spacer()
                    }
                }
                .disabled(isTestingAPI)

                SettingsDivider()

                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(APISettings.keySourceDescription)
                        .font(AppFont.caption())
                        .foregroundStyle(APISettings.canUseKimi ? .secondary : AppColor.warning)
                }
            }
        }
    }

    private var importExportCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Button {
                    showDeckStore = true
                } label: {
                    SettingsNavigationRow(
                        title: L10n.settingsOpenDeckStore,
                        systemImage: "books.vertical"
                    )
                }
                .buttonStyle(.plain)

                SettingsDivider()

                DisclosureGroup(isExpanded: $showImportHelp) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Label(L10n.importShareStep1, systemImage: "square.and.arrow.up")
                        Label(L10n.importShareStep2, systemImage: "checkmark.circle")
                        Label(L10n.importCopyStep1, systemImage: "book.closed")
                        Label(L10n.importCopyStep2, systemImage: "doc.on.doc")
                        Label(L10n.importCopyStep3, systemImage: "arrow.right.circle")
                    }
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                    .padding(.top, AppSpacing.xs)
                } label: {
                    Label(L10n.importHelpTitle, systemImage: "arrow.down.doc")
                        .font(AppFont.secondary())
                }
            }
        }
    }

    private var maintenanceCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Button {
                    showResetAllConfirm = true
                } label: {
                    SettingsNavigationRow(
                        title: L10n.settingsResetAllSRS,
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasAnyCards)
                .opacity(hasAnyCards ? 1 : 0.45)
            }
        }
    }

    private var aboutCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    SettingsNavigationRow(
                        title: L10n.privacyTitle,
                        systemImage: "hand.raised"
                    )
                }
                .buttonStyle(.plain)

                SettingsDivider()

                DisclosureGroup(isExpanded: $showHelpCenter) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(L10n.settingsHelpBYOK)
                        Text(L10n.settingsHelpApkg)
                        Text(L10n.settingsHelpShare)
                    }
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                    .padding(.top, AppSpacing.xs)
                } label: {
                    Label(L10n.settingsHelpTitle, systemImage: "questionmark.circle")
                        .font(AppFont.secondary())
                }
            }
        }
    }

    private var isUnlimitedReview: Bool {
        reviewSettings.dailyNewLimit == 0 && reviewSettings.dailyReviewLimit == 0
    }

    private var unlimitedReviewBinding: Binding<Bool> {
        Binding(
            get: { isUnlimitedReview },
            set: { unlimited in
                if unlimited {
                    reviewSettings.dailyNewLimit = 0
                    reviewSettings.dailyReviewLimit = 0
                } else {
                    reviewSettings.dailyNewLimit = ReviewSettings.defaultDailyNewLimit
                    reviewSettings.dailyReviewLimit = ReviewSettings.defaultDailyReviewLimit
                }
            }
        )
    }

    private var statusIcon: String {
        if APISettings.canUseKimi { "checkmark.circle.fill" }
        else { "exclamationmark.circle" }
    }

    private var statusColor: Color {
        if APISettings.canUseKimi { AppColor.success }
        else { AppColor.warning }
    }

    private func saveSettings() {
        APISettings.kimiAPIKey = apiKey
        APISettings.kimiModel = selectedModel
        reviewSettings.persist()
        ReviewReminderService.isEnabled = reminderEnabled
        ReviewReminderService.applyReminderTime(reminderTime)
        BackupReminderService.isEnabled = backupReminderEnabled
        BackupReminderService.reschedule()
        ReviewReminderService.reschedule(dueCount: ReviewStatusStore.dueCount)
        ToastCenter.shared.show(L10n.settingsSavedTitle)
    }

    @MainActor
    private func testAPIConnection() async {
        isTestingAPI = true
        defer { isTestingAPI = false }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let testKey = key.isEmpty ? APISettings.effectiveAPIKey : key
        guard !testKey.isEmpty else {
            ToastCenter.shared.show(L10n.settingsTestAPIFailed(L10n.missingAPIKeyError))
            return
        }

        do {
            try await KimiCardGenerator.testConnection(apiKey: testKey, model: selectedModel)
            ToastCenter.shared.show(L10n.settingsTestAPISuccess)
        } catch {
            ToastCenter.shared.show(L10n.settingsTestAPIFailed(error.localizedDescription))
        }
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
        DeckCardCountService.notifyDataMaintenance()
        showMaintenanceResult(title: L10n.settingsResetAllSRSDone, message: L10n.settingsResetAllSRSDoneMessage)
    }

    private func showMaintenanceResult(title: String, message: String) {
        maintenanceAlertTitle = title
        maintenanceAlertMessage = message
        showMaintenanceAlert = true
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Label {
                Text(title)
                    .foregroundStyle(tint)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint == .primary ? AppColor.accent : tint)
            }
            .font(AppFont.secondary())

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(ReviewSettingsStore.shared)
        .modelContainer(for: [FlashCard.self, Deck.self], inMemory: true)
}
