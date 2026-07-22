import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.privacyIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                policySection(title: L10n.privacyDataCollectionTitle, body: L10n.privacyDataCollectionBody)
                policySection(title: L10n.privacyAITitle, body: L10n.privacyAIBody)
                policySection(title: L10n.privacyOCRTitle, body: L10n.privacyOCRBody)
                policySection(title: L10n.privacyStorageTitle, body: L10n.privacyStorageBody)
                policySection(title: L10n.privacyContactTitle, body: L10n.privacyContactBody)
            }
            .padding()
        }
        .navigationTitle(L10n.privacyTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
