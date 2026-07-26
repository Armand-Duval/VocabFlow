import SwiftUI

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(AppFont.secondary())
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

struct ToastBannerModifier: ViewModifier {
    let message: String?
    var bottomPadding: CGFloat = 96

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                ToastBanner(message: message)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: message)
    }
}

extension View {
    func toastBanner(message: String?, bottomPadding: CGFloat = 96) -> some View {
        modifier(ToastBannerModifier(message: message, bottomPadding: bottomPadding))
    }
}

struct ImportBannerView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(AppFont.caption())
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SelectionActionBar: View {
    let selectedText: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(selectedText)
                .font(AppFont.secondary().weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 4)
                .background(AppColor.accentBackground(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.add, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(AppSpacing.sm)
        .background(AppColor.accentBackground(0.10), in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
    }
}

struct DraftPreviewCard: View {
    @Binding var draft: GeneratedCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.word)
                        .font(AppFont.sectionTitle())
                    if let phonetic = draft.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(AppFont.secondary())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CardTypeChip(title: draft.cardType.displayName)
            }

            Toggle(L10n.includeInLibrary, isOn: $draft.isSelected)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.phoneticLabel)
                    .font(AppFont.caption())
                    .foregroundStyle(.tertiary)
                TextField(L10n.phoneticPlaceholder, text: Binding(
                    get: { draft.phonetic ?? "" },
                    set: { draft.phonetic = $0.nilIfEmpty }
                ))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.frontLabel)
                    .font(AppFont.caption())
                    .foregroundStyle(.tertiary)
                TextField(L10n.frontLabel, text: $draft.front, axis: .vertical)
                    .lineLimit(3...12)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.backLabel)
                    .font(AppFont.caption())
                    .foregroundStyle(.tertiary)
                TextField(L10n.backPlaceholder, text: $draft.back, axis: .vertical)
                    .lineLimit(3...12)
            }

            Picker(L10n.typeLabel, selection: $draft.cardType) {
                ForEach(CardType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(AppSpacing.md)
        .background(.background, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
