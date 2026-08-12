import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            privacyBody
                .padding()
        }
        .navigationTitle(L10n.privacyTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyBody: some View {
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

/// First-launch gate: product intro + privacy consent (P1-7 / P2-4).
struct FirstLaunchGateView: View {
    var onAccepted: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                introPage.tag(0)
                privacyPage.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut(duration: 0.25), value: step)

            bottomBar
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.lg)
        }
        .appPageBackground()
    }

    private var introPage: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Spacer(minLength: AppSpacing.xl)
            BrandMark(compact: false)
            Text(L10n.onboardingHeadline)
                .font(AppFont.literaryQuote())
                .foregroundStyle(AppColor.textPrimary)
            Text(L10n.onboardingBody)
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                onboardingBullet(L10n.onboardingPointCapture)
                onboardingBullet(L10n.onboardingPointReview)
                onboardingBullet(L10n.onboardingPointRemember)
            }
            .padding(.top, AppSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private var privacyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(L10n.privacyConsentTitle)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, AppSpacing.lg)

                Text(L10n.privacyConsentBody)
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textSecondary)

                AppSurfaceCard(padding: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.privacyIntro)
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textSecondary)
                        compactPolicy(L10n.privacyDataCollectionTitle, L10n.privacyDataCollectionBody)
                        compactPolicy(L10n.privacyAITitle, L10n.privacyAIBody)
                        compactPolicy(L10n.privacyStorageTitle, L10n.privacyStorageBody)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: AppSpacing.sm) {
            if step == 0 {
                Button {
                    withAnimation { step = 1 }
                } label: {
                    Text(L10n.onboardingContinue)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))
            } else {
                Button(action: onAccepted) {
                    Text(L10n.privacyAccept)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))

                Button {
                    withAnimation { step = 0 }
                } label: {
                    Text(L10n.onboardingBack)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onboardingBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(AppColor.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compactPolicy(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.secondary().weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text(body)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
