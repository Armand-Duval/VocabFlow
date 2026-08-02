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
    var progress: (completed: Int, total: Int)? = nil

    var body: some View {
        ZStack {
            AppColor.pageBackground.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: 8) {
                    skeletonBar(widthFraction: 0.72)
                    skeletonBar(widthFraction: 0.92)
                    skeletonBar(widthFraction: 0.58)
                }
                .frame(maxWidth: 220)
                .redacted(reason: .placeholder)
                .shimmering()

                if let progress, progress.total > 0 {
                    ProgressView(
                        value: Double(min(progress.completed, progress.total)),
                        total: Double(progress.total)
                    )
                    .tint(AppColor.accent)
                    .frame(maxWidth: 220)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(AppColor.accent)
                }

                Text(message)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.15), value: message)
            }
            .padding(AppSpacing.lg)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .appSoftShadow()
        }
    }

    private func skeletonBar(widthFraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppColor.surfaceMuted)
            .frame(height: 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, (1 - widthFraction) * 220)
    }
}

private struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(0.55 + 0.35 * phase)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmeringModifier())
    }
}

struct LoadingOverlayModifier: ViewModifier {
    let isPresented: Bool
    let message: String
    var progress: (completed: Int, total: Int)? = nil

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                LoadingOverlay(message: message, progress: progress)
            }
        }
    }
}

extension View {
    func loadingOverlay(
        isPresented: Bool,
        message: String,
        progress: (completed: Int, total: Int)? = nil
    ) -> some View {
        modifier(LoadingOverlayModifier(isPresented: isPresented, message: message, progress: progress))
    }
}
