import SwiftUI

struct ImportBannerView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SelectionActionBar: View {
    let selectedText: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(selectedText)
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.add, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DraftPreviewCard: View {
    @Binding var draft: GeneratedCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.word)
                        .font(.headline)
                    if let phonetic = draft.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(draft.cardType.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            Toggle(L10n.includeInLibrary, isOn: $draft.isSelected)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.phoneticLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField(L10n.phoneticPlaceholder, text: Binding(
                    get: { draft.phonetic ?? "" },
                    set: { draft.phonetic = $0.nilIfEmpty }
                ))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.frontLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField(L10n.frontLabel, text: $draft.front, axis: .vertical)
                    .lineLimit(3...12)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.backLabel)
                    .font(.caption)
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
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
