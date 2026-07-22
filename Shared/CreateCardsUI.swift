import SwiftUI

struct ImportBannerView: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct CreateCardsTipView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "hand.tap")
                    .font(.title3)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.createTipTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.createTipBody)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Button(L10n.createTipDismiss, action: onDismiss)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

struct AddSelectionButton: View {
    let selectedText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.addSelectionWord(selectedText), systemImage: "plus.circle.fill")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}
