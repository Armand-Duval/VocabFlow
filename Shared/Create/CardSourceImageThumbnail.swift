import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Compact thumbnail for a card's persisted source image (App Group JPEG).
struct CardSourceImageThumbnail: View {
    let relativePath: String?
    var maxHeight: CGFloat = 160
    var cornerRadius: CGFloat = AppRadius.card
    /// When true, tap opens a fullscreen preview and consumes the gesture
    /// so parent flip/reveal taps do not fire.
    var allowsFullscreenPreview: Bool = true

    @State private var showPreview = false

    var body: some View {
        #if canImport(UIKit)
        if let relativePath,
           let image = CardSourceImageStore.loadUIImage(relativePath: relativePath) {
            Group {
                if allowsFullscreenPreview {
                    Button {
                        showPreview = true
                    } label: {
                        thumbnail(image)
                    }
                    .buttonStyle(.plain)
                } else {
                    thumbnail(image)
                }
            }
            .fullScreenCover(isPresented: $showPreview) {
                CardSourceImagePreview(image: image, isPresented: $showPreview)
            }
        }
        #endif
    }

    #if canImport(UIKit)
    private func thumbnail(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel(L10n.cardSourceImageLabel)
            .accessibilityAddTraits(allowsFullscreenPreview ? .isButton : [])
            .accessibilityHint(allowsFullscreenPreview ? L10n.cardSourceImageExpandHint : "")
    }
    #endif
}

#if canImport(UIKit)
/// Fullscreen source-image viewer with pinch zoom; tap close / background to dismiss.
private struct CardSourceImagePreview: View {
    let image: UIImage
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .padding(AppSpacing.md)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(4, max(1, baseScale * value))
                        }
                        .onEnded { _ in
                            baseScale = scale
                            if scale < 1.05 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scale = 1
                                    baseScale = 1
                                }
                            }
                        }
                )
                // Double-tap toggles zoom; single tap on image should not dismiss while zoomed.
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if scale > 1.2 {
                            scale = 1
                            baseScale = 1
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button(L10n.close) {
                        dismiss()
                    }
                    .font(AppFont.secondary().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
                Spacer()
            }
        }
    }

    private func dismiss() {
        isPresented = false
    }
}
#endif
