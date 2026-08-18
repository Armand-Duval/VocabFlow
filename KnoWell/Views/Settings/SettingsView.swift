import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ReviewSettingsStore.self) private var reviewSettings
    @Environment(AppAccentThemeStore.self) private var accentTheme
    @Environment(CloudAIQuotaStore.self) private var aiQuota
    @ObservedObject private var generationQueue = CardGenerationQueue.shared

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

    var body: some View {
        @Bindable var reviewSettings = reviewSettings

        NavigationStack {
            settingsScrollContent(reviewSettings: reviewSettings)
                .appPageBackground()
                .appNavTitle(
                    isPresentedAsSheet ? L10n.settingsTitle : L10n.tabSettings,
                    style: isPresentedAsSheet ? .primary : .hidden
                )
                .toolbar {
                    if isPresentedAsSheet {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.close) { dismiss() }
                        }
                    }
                }
                .dismissKeyboardOnScroll()
                .keyboardDoneButton()
                .navigationDestination(isPresented: $showDeckStore) {
                    DeckStoreView(selectedDeckID: .constant(DeckSettings.lastSelectedDeckID))
                }
                .modifier(SettingsLifecycleModifier(
                    reviewSettings: reviewSettings,
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel,
                    customBaseURL: $customBaseURL,
                    customModelID: $customModelID,
                    apiKey: $apiKey,
                    backupReminderEnabled: $backupReminderEnabled,
                    dailyAutoBackupEnabled: $dailyAutoBackupEnabled,
                    reminderEnabled: $reminderEnabled,
                    reminderTime: $reminderTime,
                    onRefreshCards: { await refreshHasAnyCards() },
                    onPersistAPI: { persistAPISettings(quiet: true) },
                    onDailyBackupEnabled: { enabled in
                        DailyAutoBackupService.isEnabled = enabled
                        if enabled {
                            Task {
                                await DailyAutoBackupService.runIfNeeded(in: modelContext)
                            }
                        }
                    }
                ))
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
                    migrateCardContent()
                }
        }
    }

    @ViewBuilder
    private func settingsScrollContent(reviewSettings: ReviewSettingsStore) -> some View {
        @Bindable var reviewSettings = reviewSettings
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                themeCard
                reviewCard(
                    dailyNewLimit: $reviewSettings.dailyNewLimit,
                    dailyReviewLimit: $reviewSettings.dailyReviewLimit
                )

                AccountSettingsCard(compact: true)
                aiCard
                dataManagementCard
                aboutSupportCard
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.lg)
        }
        .appVerticalBounce()
    }

    private var themeCard: some View {
        settingsSection(title: L10n.settingsThemeTitle) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.sm),
                    GridItem(.flexible(), spacing: AppSpacing.sm),
                    GridItem(.flexible(), spacing: AppSpacing.sm)
                ],
                spacing: AppSpacing.sm
            ) {
                ForEach(AppAccentTheme.allCases) { theme in
                    let selected = accentTheme.theme == theme
                    Button {
                        accentTheme.setTheme(theme)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(theme.swatch)
                                .frame(width: 18, height: 18)
                            Text(theme.title)
                                .font(AppFont.caption())
                                .fontWeight(selected ? .semibold : .regular)
                                .foregroundStyle(selected ? AppColor.textPrimary : AppColor.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selected ? AppColor.accentBackground(0.16) : AppColor.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                                .strokeBorder(
                                    selected ? AppColor.accent.opacity(0.35) : Color.clear,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Text(L10n.settingsThemeFooter)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reviewCard(
        dailyNewLimit: Binding<Int>,
        dailyReviewLimit: Binding<Int>
    ) -> some View {
        settingsSection(title: L10n.settingsReviewSection) {
            Toggle(L10n.settingsReviewUnlimited, isOn: unlimitedReviewBinding)

            if !isUnlimitedReview {
                DailyLimitInputRow(
                    title: L10n.settingsReviewNewLimitLabel,
                    value: dailyNewLimit
                )
                DailyLimitInputRow(
                    title: L10n.settingsReviewReviewLimitLabel,
                    value: dailyReviewLimit
                )
            }

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

            Toggle(L10n.settingsReviewReminderEnabled, isOn: $reminderEnabled)

            if reminderEnabled {
                DatePicker(
                    L10n.settingsReviewReminderTime,
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .font(AppFont.secondary())
            }

            Toggle(L10n.settingsDailyAutoBackupEnabled, isOn: $dailyAutoBackupEnabled)
            Text(L10n.settingsDailyAutoBackupFooter)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.settingsBackupReminderEnabled, isOn: $backupReminderEnabled)
                .disabled(!dailyAutoBackupEnabled)
                .opacity(dailyAutoBackupEnabled ? 1 : 0.45)
        }
    }

    private var aiCard: some View {
        settingsSection(title: L10n.settingsAISectionCompact) {
            AppSpinner(
                title: L10n.aiProviderSection,
                value: selectedProvider.displayName,
                options: AIProvider.allCases.map {
                    AppSelectionOption(id: $0.rawValue, title: $0.displayName)
                },
                selectedID: selectedProvider.rawValue
            ) { raw in
                if let provider = AIProvider(rawValue: raw) {
                    selectedProvider = provider
                }
            }

            if selectedProvider.supportsCustomBaseURL {
                TextField(L10n.aiCustomBaseURLPlaceholder, text: $customBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(AppFont.secondary())
            }

            if !selectedProvider.suggestedModels.isEmpty {
                AppSpinner(
                    title: L10n.modelSection,
                    value: selectedModel,
                    isEnabled: customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    options: selectedProvider.suggestedModels.map {
                        AppSelectionOption(
                            id: $0,
                            title: $0,
                            subtitle: APISettings.modelDescription(for: $0)
                        )
                    },
                    selectedID: selectedModel
                ) { model in
                    selectedModel = model
                }
            }

            TextField(L10n.aiCustomModelPlaceholder, text: $customModelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.secondary())
            Text(L10n.aiCustomModelFooter)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textMuted)

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
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }

            Text(liveKeySourceDescription)
                .font(AppFont.weak())
                .foregroundStyle(canTestCurrentAI ? AppColor.textMuted : AppColor.warning)

            if APISettings.usesCloudProxy, let snapshot = aiQuota.snapshot {
                Text(
                    snapshot.isExhausted
                        ? L10n.cloudQuotaExhausted
                        : L10n.cloudQuotaRemaining(snapshot.remaining, snapshot.limit)
                )
                .font(AppFont.weak())
                .foregroundStyle(snapshot.isExhausted ? AppColor.warning : AppColor.textMuted)
            }

            Button {
                Task { await testAPIConnection() }
            } label: {
                HStack(spacing: 8) {
                    if isTestingAPI {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isTestingAPI ? L10n.settingsTestingAPI : L10n.settingsTestAPI)
                        .font(AppFont.helper().weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppColor.accent)
            }
            .buttonStyle(.plain)
            .disabled(isTestingAPI)
        }
    }

    private var dataManagementCard: some View {
        settingsSection(title: L10n.settingsDataManagementSection) {
            Button {
                showDeckStore = true
            } label: {
                SettingsNavigationRow(
                    title: L10n.settingsOpenDeckStore,
                    systemImage: "books.vertical"
                )
            }
            .buttonStyle(.plain)

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

            Button {
                exportAllLogsTapped()
            } label: {
                SettingsNavigationRow(
                    title: L10n.settingsExportLogs,
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.plain)

            Button {
                showMigrateCardsConfirm = true
            } label: {
                SettingsNavigationRow(
                    title: L10n.settingsMigrateCards,
                    systemImage: "text.badge.checkmark"
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnyCards || generationQueue.hasActiveMigrationJob)
            .opacity(hasAnyCards ? 1 : 0.45)

            Button {
                showResetAllConfirm = true
            } label: {
                SettingsNavigationRow(
                    title: L10n.settingsResetAllSRS,
                    systemImage: "arrow.counterclockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnyCards || generationQueue.hasActiveMigrationJob)
            .opacity(hasAnyCards ? 1 : 0.45)
        }
    }

    private var aboutSupportCard: some View {
        settingsSection(title: L10n.settingsAboutSupportSection) {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                SettingsNavigationRow(
                    title: L10n.privacyTitle,
                    systemImage: "hand.raised"
                )
            }
            .buttonStyle(.plain)

            DisclosureGroup(isExpanded: $showHelpCenter) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(L10n.settingsHelpBYOK)
                    Text(L10n.settingsHelpApkg)
                    Text(L10n.settingsHelpShare)
                    Text(L10n.settingsAppLogFooter)
                    Button(L10n.settingsExportLogs) {
                        exportAllLogsTapped()
                    }
                    .foregroundStyle(AppColor.accent)
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

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let sectionBody = content()
        return AppSurfaceCard(padding: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(title)
                    .font(AppFont.helper().weight(.semibold))
                    .foregroundStyle(AppColor.textMuted)
                sectionBody
            }
        }
    }

    private var liveKeySourceDescription: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return L10n.keySourceUser }
        if KnoWellCloud.isEnabled { return L10n.keySourceCloud }
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
            return KnoWellCloud.isEnabled
                || !DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if selectedProvider == .custom {
            return !customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let model = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !model.isEmpty || !selectedModel.isEmpty
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
                reviewSettings.persist()
            }
        )
    }

    private var cardRevealStyleBinding: Binding<ReviewCardRevealStyle> {
        Binding(
            get: { reviewSettings.cardRevealStyle },
            set: { reviewSettings.setCardRevealStyle($0) }
        )
    }

    private func exportAllLogsTapped() {
        let urls = AppLog.exportAllLogs()
        guard !urls.isEmpty else {
            ToastCenter.shared.show(L10n.settingsExportLogsEmpty)
            return
        }
        AppLog.info(
            "Export all logs count=\(urls.count) files=\(urls.map(\.lastPathComponent).joined(separator: ","))",
            category: "Settings"
        )
        ShareSheetPresenter.present(urls: urls)
    }

    private func persistAPISettings(quiet: Bool) {
        APISettings.provider = selectedProvider
        APISettings.customBaseURL = customBaseURL
        APISettings.customModelID = customModelID
        APISettings.kimiAPIKey = apiKey
        APISettings.kimiModel = selectedModel
        if !quiet {
            ToastCenter.shared.show(L10n.settingsSavedTitle)
        }
        Task { await CloudAIQuotaStore.shared.refresh(force: true) }
    }

    @MainActor
    private func testAPIConnection() async {
        isTestingAPI = true
        defer { isTestingAPI = false }

        persistAPISettings(quiet: true)

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
            try await CardGenerator.testConnection(
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
    private func migrateCardContent() {
        let localReport = CardContentMigrationService.migrateLocally(in: modelContext)

        if APISettings.canUseAI,
           let plan = CardContentMigrationService.buildMigrationPlan(in: modelContext) {
            do {
                _ = try generationQueue.enqueueMigration(
                    in: modelContext,
                    initialReport: localReport,
                    plan: plan
                )
                ToastCenter.shared.show(L10n.settingsMigrateCardsQueued)
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
            return
        }

        let hasLocalChanges = localReport.frontsUpdated > 0 || localReport.backsSplit > 0
        if hasLocalChanges {
            showMaintenanceResult(
                title: L10n.settingsMigrateCardsDone,
                message: localReport.summaryMessage
            )
        } else {
            ToastCenter.shared.show(L10n.settingsMigrateCardsNothingToDo)
        }
    }

    private func showMaintenanceResult(title: String, message: String) {
        ToastCenter.shared.show("\(title)：\(message)")
    }
}

private struct SettingsLifecycleModifier: ViewModifier {
    let reviewSettings: ReviewSettingsStore
    @Binding var selectedProvider: AIProvider
    @Binding var selectedModel: String
    @Binding var customBaseURL: String
    @Binding var customModelID: String
    @Binding var apiKey: String
    @Binding var backupReminderEnabled: Bool
    @Binding var dailyAutoBackupEnabled: Bool
    @Binding var reminderEnabled: Bool
    @Binding var reminderTime: Date
    let onRefreshCards: () async -> Void
    let onPersistAPI: () -> Void
    let onDailyBackupEnabled: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                reviewSettings.reloadFromPersistence()
                selectedProvider = APISettings.provider
                selectedModel = APISettings.kimiModel
                customBaseURL = APISettings.customBaseURL
                customModelID = APISettings.customModelID
                apiKey = APISettings.kimiAPIKey
                backupReminderEnabled = BackupReminderService.isEnabled
                dailyAutoBackupEnabled = DailyAutoBackupService.isEnabled
                reminderEnabled = ReviewReminderService.isEnabled
                reminderTime = ReviewReminderService.reminderDate
            }
            .task {
                await onRefreshCards()
                await CloudAIQuotaStore.shared.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviewQueueDidChange)) { _ in
                Task { await onRefreshCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataMaintenanceDidComplete)) { _ in
                Task { await onRefreshCards() }
            }
            .onChange(of: reviewSettings.dailyNewLimit) { _, _ in
                reviewSettings.persist()
            }
            .onChange(of: reviewSettings.dailyReviewLimit) { _, _ in
                reviewSettings.persist()
            }
            .onChange(of: selectedProvider) { _, provider in
                if customModelID.isEmpty,
                   !provider.suggestedModels.contains(selectedModel) {
                    selectedModel = provider.defaultModel
                }
                onPersistAPI()
            }
            .onChange(of: selectedModel) { _, _ in
                onPersistAPI()
            }
            .onChange(of: customModelID) { _, _ in
                onPersistAPI()
            }
            .onChange(of: customBaseURL) { _, _ in
                onPersistAPI()
            }
            .onChange(of: apiKey) { _, _ in
                onPersistAPI()
            }
            .onChange(of: reminderEnabled) { _, enabled in
                ReviewReminderService.isEnabled = enabled
                if enabled {
                    Task { _ = await ShareExtensionNotifier.requestAuthorizationIfNeeded() }
                }
                ReviewReminderService.reschedule(dueCount: ReviewStatusStore.dueCount)
            }
            .onChange(of: reminderTime) { _, time in
                ReviewReminderService.applyReminderTime(time)
                ReviewReminderService.reschedule(dueCount: ReviewStatusStore.dueCount)
            }
            .onChange(of: backupReminderEnabled) { _, enabled in
                BackupReminderService.isEnabled = enabled
                BackupReminderService.reschedule()
            }
            .onChange(of: dailyAutoBackupEnabled) { _, enabled in
                onDailyBackupEnabled(enabled)
                if !enabled {
                    backupReminderEnabled = false
                    BackupReminderService.isEnabled = false
                    BackupReminderService.reschedule()
                }
            }
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

private enum ShareSheetPresenter {
    static func present(urls: [URL]) {
        guard let presenter = topViewController(), !urls.isEmpty else { return }
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
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
        .environment(AppAccentThemeStore.shared)
        .environment(CloudAIQuotaStore.shared)
        .modelContainer(for: FlashCard.self, inMemory: true)
}
