import AuthenticationServices
import SwiftUI

struct AccountSettingsCard: View {
    @State private var accountSession = AccountSession.shared
    @State private var isSigningInApple = false
    @State private var isSigningInWeChat = false
    @State private var errorMessage: String?

    var body: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let profile = accountSession.profile {
                    signedInHeader(profile)
                    Button(L10n.accountSignOut, role: .destructive) {
                        accountSession.signOut()
                    }
                    .font(AppFont.secondary())
                } else {
                    signedOutHeader
                    signInButtons
                }
            }
        }
        .alert(L10n.accountSignInFailed, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func signedInHeader(_ profile: AccountProfile) -> some View {
        HStack(spacing: AppSpacing.sm) {
            avatarView(for: profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.headline)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)
                Text(profile.providerLabel)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var signedOutHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L10n.accountSignedOutTitle)
                .font(AppFont.sectionTitle())
                .foregroundStyle(AppColor.textPrimary)
            Text(L10n.accountSignedOutMessage)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var signInButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            if AccountAuthConfig.isAppleSignInAvailable {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                .disabled(isSigningInApple || isSigningInWeChat)
            } else {
                appleSignInUnavailableRow
            }

            Button {
                Task { await signInWithWeChat() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "message.fill")
                    Text(L10n.accountSignInWeChat)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color(red: 0.09, green: 0.72, blue: 0.27), in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSigningInApple || isSigningInWeChat)

            if isSigningInApple || isSigningInWeChat {
                ProgressView()
                    .tint(AppColor.accent)
            }
        }
    }

    private var appleSignInUnavailableRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "apple.logo")
                    .font(.body.weight(.semibold))
                Text(L10n.accountSignInApple)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, AppSpacing.md)
            .foregroundStyle(AppColor.textSecondary)
            .background(AppColor.surfaceMuted, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))

            Text(L10n.accountAppleUnavailable)
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private func avatarView(for profile: AccountProfile) -> some View {
        ZStack {
            Circle()
                .fill(AppColor.accentBackground(0.16))
                .frame(width: 52, height: 52)
            Image(systemName: profile.provider == .apple ? "apple.logo" : "message.fill")
                .font(.title3)
                .foregroundStyle(AppColor.accent)
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = L10n.accountAppleMissingCredential
                return
            }
            let formatter = PersonNameComponentsFormatter()
            let formattedName = credential.fullName.flatMap { name in
                let value = formatter.string(from: name).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let profile = AccountProfile(
                provider: .apple,
                userID: credential.user,
                displayName: formattedName,
                email: credential.email,
                avatarURL: nil,
                signedInAt: .now
            )
            do {
                try accountSession.update(profile)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithWeChat() async {
        isSigningInWeChat = true
        defer { isSigningInWeChat = false }
        do {
            let profile = try await WeChatSignInService.startSignIn()
            try accountSession.update(profile)
        } catch let error as WeChatSignInError {
            switch error {
            case .backendRequired:
                errorMessage = L10n.accountWeChatBackendRequired
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AccountSettingsCard()
        .padding()
        .appPageBackground()
}
