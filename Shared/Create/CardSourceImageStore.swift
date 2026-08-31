import Foundation
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

/// Persists card source images in the App Group container as JPEG files.
/// Cards store a relative path like `card-images/{uuid}.jpg`.
enum CardSourceImageStore {
    static let folderName = "card-images"
    private static let maxPixelDimension: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.72

    static var directoryURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func fileURL(relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(".."),
              trimmed.hasPrefix(folderName + "/") else {
            return nil
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent(trimmed)
    }

    #if canImport(UIKit)
    /// Main-app OCR after a share-inbox handoff. Match the album picker: honor EXIF
    /// orientation and keep enough pixels for a full book page.
    private static let ocrMaxPixelDimension: CGFloat = 4096

    static func imageForOCR(at url: URL, maxPixelDimension: CGFloat = ocrMaxPixelDimension) -> UIImage? {
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            AppLog.info(
                "inbox decode \(Int(image.size.width))x\(Int(image.size.height)) orientation=\(image.imageOrientation.rawValue) → OCR max \(Int(maxPixelDimension))",
                category: "Share"
            )
            return downscaled(image, maxDimension: maxPixelDimension)
        }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        AppLog.info(
            "inbox ImageIO thumb \(cgImage.width)x\(cgImage.height)",
            category: "Share"
        )
        return UIImage(cgImage: cgImage)
    }

    /// Shrink a photo so Share/Action OCR stays under the extension memory cap.
    static func prepared(_ image: UIImage) -> UIImage {
        downscaled(image, maxDimension: maxPixelDimension)
    }

    /// Compress and write `image`; returns relative path on success.
    @discardableResult
    static func saveJPEG(_ image: UIImage) -> String? {
        guard let directory = directoryURL else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let scaled = downscaled(image, maxDimension: maxPixelDimension)
        guard let data = scaled.jpegData(compressionQuality: jpegQuality) else { return nil }

        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return "\(folderName)/\(fileName)"
        } catch {
            return nil
        }
    }

    static func loadUIImage(relativePath: String) -> UIImage? {
        guard let url = fileURL(relativePath: relativePath),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
