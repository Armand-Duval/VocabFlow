import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

enum ShareTextExtractor {
    private static let loadTypePriority: [String] = [
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier,
        UTType.text.identifier,
        UTType.rtf.identifier,
        UTType.html.identifier,
        UTType.url.identifier
    ]

    static func attributedText(from extensionItems: [NSExtensionItem]) -> String? {
        for item in extensionItems {
            if let text = cleaned(item.attributedContentText?.string), isUsefulQuote(text) {
                return text
            }
            if let text = cleaned(item.attributedTitle?.string), isUsefulQuote(text) {
                return text
            }
        }
        return nil
    }

    static func firstUsableProvider(from providers: [NSItemProvider]) -> NSItemProvider? {
        providers.first { provider in
            loadTypePriority.contains { provider.hasItemConformingToTypeIdentifier($0) }
                || provider.canLoadObject(ofClass: String.self)
                || provider.canLoadObject(ofClass: URL.self)
        }
    }

    static func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        loadTypePriority.first { provider.hasItemConformingToTypeIdentifier($0) }
    }

    static func loadText(from extensionItems: [NSExtensionItem]) async -> String? {
        if let attributed = attributedText(from: extensionItems) {
            return attributed
        }

        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        return await loadText(from: providers)
    }

    /// Never uses `loadItem` — that API logs nil expectedValueClass and is unreliable on modern EX runtimes.
    static func loadText(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: String.self),
           let text = await loadObject(String.self, from: provider),
           let cleanedText = cleaned(text) {
            return cleanedText
        }

        if provider.canLoadObject(ofClass: URL.self),
           let url = await loadObject(URL.self, from: provider),
           let text = cleaned(await textFromURL(url)) {
            return text
        }

        for typeIdentifier in loadTypePriority where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let data = await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier),
               let text = cleaned(parseData(data, typeIdentifier: typeIdentifier)) {
                return text
            }

            if let text = cleaned(await loadFileText(from: provider, typeIdentifier: typeIdentifier)) {
                return text
            }
        }

        return nil
    }

    static func loadText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if let text = await loadText(from: provider), isUsefulQuote(text) {
                return text
            }
        }
        return nil
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isUsefulQuote(_ text: String) -> Bool {
        guard text.count >= 2 else { return false }

        let lower = text.lowercased()
        if lower.hasPrefix("ibooks://") || lower.hasPrefix("books://") {
            return false
        }

        return true
    }

    private static func parseData(_ data: Data, typeIdentifier: String) -> String {
        switch typeIdentifier {
        case UTType.rtf.identifier:
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
            if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return attributed.string
            }
            return String(data: data, encoding: .utf8) ?? ""
        case UTType.html.identifier:
            if let html = String(data: data, encoding: .utf8) {
                return stripHTML(html)
            }
            return ""
        case UTType.url.identifier:
            if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: raw) {
                return url.absoluteString
            }
            return String(data: data, encoding: .utf8) ?? ""
        default:
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private static func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return html
    }

    private static func loadObject<T>(_ type: T.Type, from provider: NSItemProvider) async -> T? where T: _ObjectiveCBridgeable, T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }

    private static func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadFileText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: textFromFileURL(url))
            }
        }
    }

    private static func textFromURL(_ url: URL) async -> String? {
        if url.isFileURL {
            return await Task.detached(priority: .userInitiated) {
                textFromFileURL(url)
            }.value
        }
        return url.absoluteString
    }

    private static func textFromFileURL(_ url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        // Some hosts hand a file URL whose contents are UTF-16 / Latin-1.
        if let data = try? Data(contentsOf: url) {
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
        }
        return nil
    }

    #if canImport(UIKit)
    private static let imageTypePriority: [String] = [
        "public.heic",
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.image.identifier,
        "public.image"
    ]

    static func hasImageAttachment(in extensionItems: [NSExtensionItem]) -> Bool {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        return providers.contains { provider in
            imageTypePriority.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
    }

    /// Copy the shared file into the App Group. Never decode pixels here.
    static func ingestFirstImage(from extensionItems: [NSExtensionItem]) async -> String? {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        for provider in providers {
            AppLog.info(
                "image types=\(provider.registeredTypeIdentifiers.joined(separator: ","))",
                category: "Share"
            )
            guard let typeIdentifier = imageTypePriority.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else {
                continue
            }
            if let relativePath = await ingestFile(from: provider, typeIdentifier: typeIdentifier) {
                return relativePath
            }
            AppLog.warn("ingest file missed type=\(typeIdentifier)", category: "Share")
        }
        return nil
    }

    private static func ingestFile(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                continuation.resume(returning: ingestLocalFile(url, typeIdentifier: typeIdentifier))
            }
        }
    }

    private static func ingestLocalFile(_ url: URL, typeIdentifier: String) -> String? {
        if let size = pixelSize(at: url) {
            AppLog.info("image \(size.width)x\(size.height) → inbox", category: "Share")
        } else {
            AppLog.info("image size unknown → inbox", category: "Share")
        }
        let ext = preferredExtension(for: typeIdentifier, url: url)
        do {
            return try ShareImportStore.importInboxFile(from: url, fileExtension: ext)
        } catch {
            AppLog.warn("inbox copy file failed: \(error.localizedDescription)", category: "Share")
            return nil
        }
    }

    private static func pixelSize(at url: URL) -> (width: Int, height: Int)? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        let propsOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, propsOptions as CFDictionary) as? [CFString: Any] else {
            return nil
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private static func preferredExtension(for typeIdentifier: String, url: URL?) -> String {
        if let ext = url?.pathExtension, !ext.isEmpty {
            return ext
        }
        switch typeIdentifier {
        case "public.heic": return "heic"
        case UTType.jpeg.identifier: return "jpg"
        case UTType.png.identifier: return "png"
        default: return "img"
        }
    }
    #endif
}
