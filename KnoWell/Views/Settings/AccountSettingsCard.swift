import AuthenticationServices
import SwiftUI

struct AccountSettingsCard: View {
    var compact: Bool = false

    @State private var accountSession = AccountSession.shared
    @State private var isSigningInApple = false
    @State private var isSigningInWeChat = false
    @State private var errorMessage: String?

    var body: some View {
        AppSurfaceCard(padding: compact ? AppSpacing.sm : AppSpacing.md) {
            VStack(alignment: .leading, spacing: compact ? AppSpacing.sm : AppSpacing.md) {
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
        .onChange(of: errorMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            ToastCenter.shared.show("\(L10n.accountSignInFailed)：\(message)")
            errorMessage = nil
        }
    }

    private func signedInHeader(_ profile: AccountProfile) -> some View {
        HStack(spacing: AppSpacing.sm) {
            avatarView(for: profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.headline)
                    .font(compact ? AppFont.secondary().weight(.semibold) : AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)
                Text(profile.providerLabel)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textMuted)
            }

            Spacer(minLength: 0)
        }
    }

    private var signedOutHeader: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : AppSpacing.xs) {
            Text(L10n.accountSignedOutTitle)
                .font(compact ? AppFont.secondary().weight(.semibold) : AppFont.sectionTitle())
                .foregroundStyle(AppColor.textPrimary)
            if !compact {
                Text(L10n.accountSignedOutMessage)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var signInButtons: some View {
        VStack(spacing: compact ? AppSpacing.xs : AppSpacing.sm) {
            if AccountAuthConfig.isAppleSignInAvailable {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: compact ? 40 : 48)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                .disabled(isSigningInApple || isSigningInWeChat)
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
                .padding(.vertical, compact ? 10 : 14)
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

    @ViewBuilder
    private func avatarView(for profile: AccountProfile) -> some View {
        let size: CGFloat = compact ? 40 : 52
        ZStack {
            Circle()
                .fill(AppColor.accentBackground(0.16))
                .frame(width: size, height: size)
            Image(systemName: profile.provider == .apple ? "apple.logo" : "message.fill")
                .font(compact ? .body : .title3)
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
