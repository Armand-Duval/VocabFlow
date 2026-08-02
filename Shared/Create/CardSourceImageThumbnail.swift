import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Compact thumbnail for a card's persisted source image (App Group JPEG).
struct CardSourceImageThumbnail: View {
    let relativePath: String?
    var maxHeight: CGFloat = 160
    var cornerRadius: CGFloat = AppRadius.card

    var body: some View {
        #if canImport(UIKit)
        if let relativePath,
           let image = CardSourceImageStore.loadUIImage(relativePath: relativePath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .accessibilityLabel(L10n.cardSourceImageLabel)
        }
        #endif
    }
}
