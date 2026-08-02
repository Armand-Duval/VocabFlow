import SwiftUI

/// Role for rows / confirm primary buttons inside app-styled sheets.
enum AppSheetActionRole {
    case standard
    case accent
    case destructive
}

struct AppSheetAction: Identifiable {
    let id = UUID()
    let title: String
    var systemImage: String? = nil
    var role: AppSheetActionRole = .standard
    var isEnabled: Bool = true
    let handler: () -> Void
}

struct AppSelectionOption: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String? = nil

    init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    init(id: UUID, title: String, subtitle: String? = nil) {
        self.id = id.uuidString
        self.title = title
        self.subtitle = subtitle
    }
}

/// Bottom sheet choice list — replaces system `Menu` / short `confirmationDialog` menus.
struct AppActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var title: String? = nil
    var message: String? = nil
    let actions: [AppSheetAction]
    var cancelTitle: String = L10n.cancel

    var body: some View {
        VStack(spacing: 0) {
            sheetGrabber

            if title != nil || message != nil {
                VStack(spacing: 6) {
                    if let title {
                        Text(title)
                            .font(AppFont.sectionTitle())
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    if let message {
                        Text(message)
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
            }

            VStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        Divider().overlay(AppColor.borderSubtle)
                    }
                    actionRow(action)
                }
            }
            .background(AppColor.surfaceMuted, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .padding(.horizontal, AppSpacing.md)

            Button {
                dismiss()
            } label: {
                Text(cancelTitle)
                    .font(AppFont.body().weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.md)
        }
        .background(AppColor.surface)
    }

    private var sheetGrabber: some View {
        Capsule()
            .fill(AppColor.border)
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, AppSpacing.md)
    }

    private func actionRow(_ action: AppSheetAction) -> some View {
        Button {
            dismiss()
            // Let the sheet finish dismissing before presenting follow-up UI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                action.handler()
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.medium))
                        .frame(width: 22)
                }
                Text(action.title)
                    .font(AppFont.body().weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground(for: action))
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.4)
    }

    private func foreground(for action: AppSheetAction) -> Color {
        switch action.role {
        case .standard: AppColor.textPrimary
        case .accent: AppColor.accent
        case .destructive: AppColor.danger
        }
    }
}

/// Confirm panel with primary + cancel — replaces system `confirmationDialog` popovers.
struct AppConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var message: String? = nil
    let confirmTitle: String
    var confirmRole: AppSheetActionRole = .accent
    var cancelTitle: String = L10n.cancel
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.border)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, AppSpacing.md)

            VStack(spacing: 8) {
                Text(title)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)

            Group {
                if confirmRole == .destructive {
                    Button {
                        // Run confirm before dismiss — callers often bind isPresented to the
                        // same optional payload; dismissing first would nil it out.
                        onConfirm()
                        dismiss()
                    } label: {
                        Text(confirmTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DestructiveSheetButtonStyle())
                } else {
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text(confirmTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, AppSpacing.md)

            Button {
                dismiss()
            } label: {
                Text(cancelTitle)
                    .font(AppFont.body().weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
        .background(AppColor.surface)
    }

}

/// Single-select list — replaces `.pickerStyle(.menu)`.
struct AppSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [AppSelectionOption]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.border)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, AppSpacing.sm)

            Text(title)
                .font(AppFont.sectionTitle())
                .foregroundStyle(AppColor.textPrimary)
                .padding(.bottom, AppSpacing.md)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            Divider().overlay(AppColor.borderSubtle)
                        }
                        Button {
                            onSelect(option.id)
                            dismiss()
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(AppFont.body().weight(.medium))
                                        .foregroundStyle(AppColor.textPrimary)
                                    if let subtitle = option.subtitle {
                                        Text(subtitle)
                                            .font(AppFont.caption())
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if option.id == selectedID {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppColor.accent)
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(AppColor.surfaceMuted, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .padding(.horizontal, AppSpacing.md)
            }

            Button {
                dismiss()
            } label: {
                Text(L10n.cancel)
                    .font(AppFont.body().weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
        .background(AppColor.surface)
    }
}

private struct DestructiveSheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(AppColor.danger.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension View {
    func appActionSheet(
        isPresented: Binding<Bool>,
        title: String? = nil,
        message: String? = nil,
        actions: [AppSheetAction],
        height: CGFloat? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            AppActionSheet(title: title, message: message, actions: actions)
                .appSheetChrome(height: height ?? actionSheetHeight(title: title, message: message, count: actions.count))
        }
    }

    func appConfirmSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        confirmTitle: String,
        confirmRole: AppSheetActionRole = .accent,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            AppConfirmSheet(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                confirmRole: confirmRole,
                onConfirm: onConfirm
            )
            .appSheetChrome(height: message == nil ? 220 : 280)
        }
    }

    func appSelectionSheet(
        isPresented: Binding<Bool>,
        title: String,
        options: [AppSelectionOption],
        selectedID: String?,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            AppSelectionSheet(
                title: title,
                options: options,
                selectedID: selectedID,
                onSelect: onSelect
            )
            .appSheetChrome(
                height: min(120 + CGFloat(options.count) * 56 + 72, 480),
                allowsMedium: options.count > 6
            )
        }
    }

    func appSelectionSheet(
        isPresented: Binding<Bool>,
        title: String,
        options: [AppSelectionOption],
        selectedID: UUID?,
        onSelect: @escaping (UUID) -> Void
    ) -> some View {
        appSelectionSheet(
            isPresented: isPresented,
            title: title,
            options: options,
            selectedID: selectedID?.uuidString
        ) { raw in
            if let id = UUID(uuidString: raw) {
                onSelect(id)
            }
        }
    }

    @ViewBuilder
    fileprivate func appSheetChrome(height: CGFloat, allowsMedium: Bool = false) -> some View {
        if allowsMedium {
            self
                .presentationDetents([.height(height), .medium])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(AppRadius.sheet)
                .presentationBackground(AppColor.surface)
        } else {
            self
                .presentationDetents([.height(height)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(AppRadius.sheet)
                .presentationBackground(AppColor.surface)
        }
    }
}

private func actionSheetHeight(title: String?, message: String?, count: Int) -> CGFloat {
    var height: CGFloat = 24 + 12 // grabber
    if title != nil { height += 28 }
    if message != nil { height += 36 }
    if title != nil || message != nil { height += 12 }
    height += CGFloat(max(count, 1)) * 52 + 16
    height += 56 // cancel
    height += 24
    return height
}
