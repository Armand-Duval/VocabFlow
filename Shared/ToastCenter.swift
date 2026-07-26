import SwiftUI

@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var message: String?
    private var clearTask: Task<Void, Never>?

    func show(_ message: String, duration: TimeInterval = 2.4) {
        clearTask?.cancel()
        self.message = message
        clearTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if self.message == message {
                self.message = nil
            }
        }
    }

    func dismiss() {
        clearTask?.cancel()
        message = nil
    }
}

struct ToastCenterModifier: ViewModifier {
    @State private var toastCenter = ToastCenter.shared
    var bottomPadding: CGFloat = 96

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = toastCenter.message {
                    ToastBanner(message: message)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toastCenter.message)
    }
}

extension View {
    func appToast(bottomPadding: CGFloat = 96) -> some View {
        modifier(ToastCenterModifier(bottomPadding: bottomPadding))
    }
}

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.lg)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
    }
}

struct LoadingOverlayModifier: ViewModifier {
    let isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                LoadingOverlay(message: message)
            }
        }
    }
}

extension View {
    func loadingOverlay(isPresented: Bool, message: String) -> some View {
        modifier(LoadingOverlayModifier(isPresented: isPresented, message: message))
    }
}
