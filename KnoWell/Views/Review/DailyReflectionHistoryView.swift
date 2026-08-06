import SwiftUI

/// Browse archived「今日一句」lines — local search + optional create-card handoff.
struct DailyReflectionHistoryView: View {
    let onCollect: (DailyReflection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var items: [ArchivedDailyReflection] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            NavigationLink {
                                detail(item)
                            } label: {
                                row(item)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .appPageBackground()
            .navigationTitle(L10n.reviewDailyHistoryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: L10n.reviewDailyHistorySearch)
            .onChange(of: query) { _, _ in
                reload()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.close) { dismiss() }
                }
            }
            .onAppear { reload() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer(minLength: 48)
            Text(query.isEmpty ? L10n.reviewDailyHistoryEmpty : L10n.reviewDailyHistoryNoMatch)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: ArchivedDailyReflection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.displayDate)
                    .font(AppFont.weak().weight(.medium))
                    .foregroundStyle(AppColor.textTertiary)
                if let occasion = item.occasion?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !occasion.isEmpty {
                    Text("·")
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted.opacity(0.45))
                    Text(occasion)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(item.displaySentence)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = item.displayTranslation {
                Text(translation)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(AppColor.pageBackground)
    }

    private func detail(_ item: ArchivedDailyReflection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSurfaceCard(padding: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: 6) {
                            Text(item.dayKey)
                                .font(AppFont.weak())
                                .foregroundStyle(AppColor.textMuted)
                            if let occasion = item.occasion?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !occasion.isEmpty {
                                Text("·")
                                    .font(AppFont.weak())
                                    .foregroundStyle(AppColor.textMuted.opacity(0.45))
                                Text(occasion)
                                    .font(AppFont.weak())
                                    .foregroundStyle(AppColor.textMuted.opacity(0.8))
                            }
                        }

                        LiteraryQuoteLines(text: item.asReflection.displaySentence)

                        if let quoteSource = item.asReflection.quoteSourceAttribution {
                            Text("— \(quoteSource)")
                                .font(AppFont.weak())
                                .foregroundStyle(AppColor.textMuted.opacity(0.85))
                        }

                        if let translation = item.asReflection.displayTranslation {
                            LiteraryQuoteLines(
                                text: translation,
                                font: AppFont.secondary(),
                                foreground: AppColor.textSecondary,
                                lineSpacing: 3
                            )
                        }

                        if let translationSource = item.asReflection.translationSourceAttribution {
                            Text("—— \(translationSource)")
                                .font(AppFont.weak())
                                .foregroundStyle(AppColor.textMuted.opacity(0.85))
                        }
                    }
                }

                Button {
                    onCollect(item.asReflection)
                    dismiss()
                } label: {
                    Text(L10n.reviewDailyCollect)
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))
            }
            .padding(AppSpacing.md)
        }
        .appPageBackground()
        .navigationTitle(item.displayDate)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reload() {
        items = DailyReflectionService.history(matching: query)
    }
}
