import SwiftUI

struct DailyReflectionPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSaved: () -> Void

    @State private var draftKeywords: [String] = DailyReflectionPreferences.keywords
    @State private var customInput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    AppSurfaceCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(L10n.reviewDailyPreferencesPresets)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)

                            FlowLayout(spacing: 8) {
                                ForEach(DailyReflectionPreset.allCases) { preset in
                                    FilterChip(
                                        title: preset.rawValue,
                                        isSelected: draftKeywords.contains(preset.rawValue)
                                    ) {
                                        toggleDraft(preset.rawValue)
                                    }
                                }
                            }
                        }
                    }

                    AppSurfaceCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(L10n.reviewDailyPreferencesCustom)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)

                            HStack(spacing: AppSpacing.sm) {
                                TextField(L10n.reviewDailyPreferencesPlaceholder, text: $customInput)
                                    .textFieldStyle(.plain)
                                    .font(AppFont.body())
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, 10)
                                    .background(AppColor.surfaceMuted, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                                    .submitLabel(.done)
                                    .onSubmit(addCustomKeyword)

                                Button(L10n.add) {
                                    addCustomKeyword()
                                }
                                .buttonStyle(PrimaryButtonStyle(prominent: false))
                                .disabled(!canAddCustom)
                            }

                            Text(L10n.reviewDailyPreferencesLimit)
                                .font(AppFont.weak())
                                .foregroundStyle(AppColor.textMuted)
                        }
                    }

                    if !draftKeywords.isEmpty {
                        AppSurfaceCard {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Text(L10n.reviewDailyPreferencesActive)
                                    .font(AppFont.caption())
                                    .foregroundStyle(AppColor.textSecondary)

                                FlowLayout(spacing: 8) {
                                    ForEach(draftKeywords, id: \.self) { keyword in
                                        SelectedKeywordChip(title: keyword) {
                                            draftKeywords.removeAll { $0 == keyword }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text(L10n.reviewDailyPreferencesFooter)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.md)
            }
            .appPageBackground()
            .navigationTitle(L10n.reviewDailyPreferencesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.reviewDailyPreferencesSave) { save() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !draftKeywords.isEmpty {
                    Button(L10n.reviewDailyPreferencesClear) {
                        draftKeywords = []
                        customInput = ""
                    }
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColor.pageBackground)
                }
            }
        }
    }

    private var canAddCustom: Bool {
        guard let word = DailyReflectionPreferences.sanitize(customInput) else { return false }
        return !draftKeywords.contains(word) && draftKeywords.count < DailyReflectionPreferences.maxKeywords
    }

    private func toggleDraft(_ raw: String) {
        guard let word = DailyReflectionPreferences.sanitize(raw) else { return }
        if let index = draftKeywords.firstIndex(of: word) {
            draftKeywords.remove(at: index)
        } else if draftKeywords.count < DailyReflectionPreferences.maxKeywords {
            draftKeywords.append(word)
        }
    }

    private func addCustomKeyword() {
        guard let word = DailyReflectionPreferences.sanitize(customInput) else { return }
        guard !draftKeywords.contains(word) else {
            customInput = ""
            return
        }
        guard draftKeywords.count < DailyReflectionPreferences.maxKeywords else { return }
        draftKeywords.append(word)
        customInput = ""
    }

    private func save() {
        let cleaned = draftKeywords.compactMap { DailyReflectionPreferences.sanitize($0) }
        let changed = cleaned != DailyReflectionPreferences.keywords
        DailyReflectionPreferences.keywords = cleaned
        if changed {
            DailyReflectionService.invalidateTodayCache()
            onSaved()
        }
        dismiss()
    }
}

private struct SelectedKeywordChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(AppFont.caption())
                .foregroundStyle(AppColor.accentStrong)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColor.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 6)
        .background(AppColor.accentBackground(0.14), in: Capsule())
    }
}

/// Simple left-to-right chip flow for preset tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
