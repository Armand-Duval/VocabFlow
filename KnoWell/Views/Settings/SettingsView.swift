import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    var isPresentedAsSheet: Bool = false

    @State private var apiKey = APISettings.kimiAPIKey
    @State private var selectedProvider = APISettings.provider
    @State private var selectedModel = APISettings.kimiModel
    @State private var customBaseURL = APISettings.customBaseURL
    @State private var customModelID = APISettings.customModelID
    @State private var showKey = false
    @State private var hasAnyCards = false
    @State private var isTestingAPI = false

    @State private var showImportHelp = false
    @State private var showHelpCenter = false
    @State private var reminderEnabled = ReviewReminderService.isEnabled
    @State private var reminderTime = ReviewReminderService.reminderDate
    @State private var backupReminderEnabled = BackupReminderService.isEnabled
    @State private var dailyAutoBackupEnabled = DailyAutoBackupService.isEnabled
    @State private var showDeckStore = false

    @State private var showResetAllConfirm = false
    @State private var showMigrateCardsConfirm = false
    @State private var isMigratingCards = false
    @State private var maintenanceAlertTitle = ""
    @State private var maintenanceAlertMessage = ""
    @State private var showMaintenanceAlert = false

    var body: some View {
        @Bindable var reviewSettings = reviewSettings

        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    AccountSettingsCard()
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
            .toolbar {
                if isPresentedAsSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.close) { dismiss() }
                    }
                }
            }
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
                selectedProvider = APISettings.provider
                selectedModel = APISettings.kimiModel
                customBaseURL = APISettings.customBaseURL
                customModelID = APISettings.customModelID
                apiKey = APISettings.kimiAPIKey
                backupReminderEnabled = BackupReminderService.isEnabled
                dailyAutoBackupEnabled = DailyAutoBackupService.isEnabled
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
            .appConfirmSheet(
                isPresented: $showResetAllConfirm,
                title: L10n.settingsResetAllSRS,
                message: L10n.settingsResetAllSRSMessage,
                confirmTitle: L10n.settingsResetAllSRS,
                confirmRole: .destructive
            ) {
                resetAllProgress()
            }
            .appConfirmSheet(
                isPresented: $showMigrateCardsConfirm,
                title: L10n.settingsMigrateCards,
                message: L10n.settingsMigrateCardsMessage,
                confirmTitle: L10n.settingsMigrateCards,
                confirmRole: .accent
            ) {
                Task { await migrateCardContent() }
            }
            .loadingOverlay(isPresented: isMigratingCards, message: L10n.settingsMigrateCardsRunning)
        }
        // Sheet covers ContentView’s toast host — host toasts here so Save / API test are visible.
        .appToast(bottomPadding: 108)
    }

    private var saveFooter: some View {
        Button(L10n.saveSettings, action: saveSettings)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xs)
            .background(AppColor.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(AppColor.border).frame(height: 1)
            }
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
                    DailyLimitInputRow(
                        title: L10n.settingsReviewNewLimitLabel,
                        value: dailyNewLimit
                    )
                    SettingsDivider()
                    DailyLimitInputRow(
                        title: L10n.settingsReviewReviewLimitLabel,
                        value: dailyReviewLimit
                    )
                }

                SettingsDivider()
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L10n.settingsReviewRevealStyle)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textPrimary)
                    Picker("", selection: cardRevealStyleBinding) {
                        ForEach(ReviewCardRevealStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(reviewSettings.cardRevealStyle.footer)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
                SettingsDivider()
                Toggle(L10n.settingsDailyAutoBackupEnabled, isOn: $dailyAutoBackupEnabled)
                Text(L10n.settingsDailyAutoBackupFooter)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private var aiCard: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Picker(L10n.aiProviderSection, selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .font(AppFont.secondary())
                .onChange(of: selectedProvider) { _, provider in
                    if customModelID.isEmpty,
                       !provider.suggestedModels.contains(selectedModel) {
                        selectedModel = provider.defaultModel
                    }
                }

                if selectedProvider.supportsCustomBaseURL {
                    SettingsDivider()
                    TextField(L10n.aiCustomBaseURLPlaceholder, text: $customBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .font(AppFont.secondary())
                    Text(L10n.aiCustomBaseURLFooter)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary)
                }

                SettingsDivider()

                HStack(spacing: AppSpacing.sm) {
                    Group {
                        if showKey {
                            TextField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                        } else {
                            SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
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

                if !selectedProvider.suggestedModels.isEmpty {
                    SettingsDivider()
                    Picker(L10n.modelSection, selection: $selectedModel) {
                        ForEach(selectedProvider.suggestedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .font(AppFont.secondary())
                    .disabled(!customModelID.isEmpty)
                    .opacity(customModelID.isEmpty ? 1 : 0.45)
                }

                SettingsDivider()
                TextField(L10n.aiCustomModelPlaceholder, text: $customModelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.secondary())
                Text(L10n.aiCustomModelFooter)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textTertiary)

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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveProviderDescription)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textSecondary)
                        Text(liveKeySourceDescription)
                            .font(AppFont.caption())
                            .foregroundStyle(canTestCurrentAI ? .secondary : AppColor.warning)
                    }
                }
            }
        }
    }

    private var liveProviderDescription: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               selectedProvider == .deepseek || APISettings.defaultAPIKey(for: selectedProvider).isEmpty {
                return AIProvider.deepseek.displayName
            }
            if selectedProvider == .moonshot,
               !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AIProvider.moonshot.displayName
            }
            if !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AIProvider.deepseek.displayName
            }
            if !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AIProvider.moonshot.displayName
            }
        }
        return selectedProvider.displayName
    }

    private var liveKeySourceDescription: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return L10n.keySourceUser }
        if selectedProvider == .deepseek,
           !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.keySourceDefault
        }
        if selectedProvider == .moonshot,
           !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.keySourceDefault
        }
        if !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.keySourceDefault
        }
        if !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.keySourceDefault
        }
        return L10n.keySourceMissing
    }

    private var canTestCurrentAI: Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            if selectedProvider == .deepseek {
                return !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if selectedProvider == .moonshot {
                return !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            // Other providers with empty key → bundled DeepSeek, then Moonshot.
            return !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if selectedProvider == .custom {
            return !customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let model = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !model.isEmpty || !selectedModel.isEmpty
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
                    showMigrateCardsConfirm = true
                } label: {
                    SettingsNavigationRow(
                        title: L10n.settingsMigrateCards,
                        systemImage: "text.badge.checkmark"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasAnyCards || isMigratingCards)
                .opacity(hasAnyCards ? 1 : 0.45)

                SettingsDivider()

                Button {
                    showResetAllConfirm = true
                } label: {
                    SettingsNavigationRow(
                        title: L10n.settingsResetAllSRS,
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasAnyCards || isMigratingCards)
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

    private var cardRevealStyleBinding: Binding<ReviewCardRevealStyle> {
        Binding(
            get: { reviewSettings.cardRevealStyle },
            set: { reviewSettings.setCardRevealStyle($0) }
        )
    }

    private var statusIcon: String {
        if canTestCurrentAI { "checkmark.circle.fill" }
        else { "exclamationmark.circle" }
    }

    private var statusColor: Color {
        if canTestCurrentAI { AppColor.success }
        else { AppColor.warning }
    }

    private func saveSettings() {
        APISettings.provider = selectedProvider
        APISettings.customBaseURL = customBaseURL
        APISettings.customModelID = customModelID
        APISettings.kimiAPIKey = apiKey
        APISettings.kimiModel = selectedModel
        reviewSettings.persist()
        ReviewReminderService.isEnabled = reminderEnabled
        ReviewReminderService.applyReminderTime(reminderTime)
        BackupReminderService.isEnabled = backupReminderEnabled
        BackupReminderService.reschedule()
        DailyAutoBackupService.isEnabled = dailyAutoBackupEnabled
        if dailyAutoBackupEnabled {
            Task {
                await DailyAutoBackupService.runIfNeeded(in: modelContext)
            }
        }
        ReviewReminderService.reschedule(dueCount: ReviewStatusStore.dueCount)
        ToastCenter.shared.show(L10n.settingsSavedTitle)
    }

    @MainActor
    private func testAPIConnection() async {
        isTestingAPI = true
        defer { isTestingAPI = false }

        // Persist provider/base URL first so the probe hits the selected endpoint.
        APISettings.provider = selectedProvider
        APISettings.customBaseURL = customBaseURL
        APISettings.customModelID = customModelID
        APISettings.kimiModel = selectedModel

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let testKey = key.isEmpty ? APISettings.effectiveAPIKey : key
        guard !testKey.isEmpty else {
            ToastCenter.shared.show(L10n.settingsTestAPIFailed(L10n.missingAPIKeyError))
            return
        }
        if selectedProvider == .custom, APISettings.baseURL.isEmpty {
            ToastCenter.shared.show(L10n.settingsTestAPIFailed(L10n.aiCustomBaseURLMissing))
            return
        }

        do {
            try await KimiCardGenerator.testConnection(
                apiKey: testKey,
                model: APISettings.effectiveModel
            )
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

    @MainActor
    private func migrateCardContent() async {
        isMigratingCards = true
        defer { isMigratingCards = false }
        let report = await CardContentMigrationService.migrate(
            in: modelContext,
            useAI: APISettings.canUseAI
        )
        showMaintenanceResult(
            title: L10n.settingsMigrateCardsDone,
            message: report.summaryMessage
        )
    }

    private func showMaintenanceResult(title: String, message: String) {
        maintenanceAlertTitle = title
        maintenanceAlertMessage = message
        showMaintenanceAlert = true
    }
}

private struct DailyLimitInputRow: View {
    let title: String
    @Binding var value: Int

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private let range = 0...999

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textPrimary)

            Spacer(minLength: AppSpacing.sm)

            TextField("0", text: $draft)
                .font(AppFont.secondary().monospacedDigit())
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(width: 72)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onAppear { draft = String(value) }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else { return }
                    draft = String(newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        draft = String(value)
                    } else {
                        commit()
                    }
                }
                .onChange(of: draft) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue {
                        draft = digits
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }

    private func commit() {
        let parsed = Int(draft.filter(\.isNumber)) ?? 0
        let clamped = min(range.upperBound, max(range.lowerBound, parsed))
        value = clamped
        draft = String(clamped)
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
