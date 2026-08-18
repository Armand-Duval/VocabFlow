import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
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
        UTType.image.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        "public.image"
    ]

    static func loadTextFromImages(from extensionItems: [NSExtensionItem]) async -> String? {
        await loadOCRFromImages(from: extensionItems)?.fullText
    }

    /// Save shared image to App Group storage without performing OCR.
    /// OCR will be performed later in the main app.
    static func saveSharedImage(from extensionItems: [NSExtensionItem]) async -> String? {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        for provider in providers {
            guard let image = await loadUIImage(from: provider) else { continue }
            return CardSourceImageStore.saveJPEG(image)
        }
        return nil
    }

    static func loadOCRFromImages(from extensionItems: [NSExtensionItem]) async -> OCRResult? {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        for provider in providers {
            guard let image = await loadUIImage(from: provider) else { continue }
            let sourceImagePath = CardSourceImageStore.saveJPEG(image)
            guard let result = try? await ImageOCRService.recognize(in: image) else { continue }
            guard let cleanedText = cleaned(result.fullText) else { continue }
            return OCRResult(
                fullText: cleanedText,
                highlightedWords: result.highlightedWords,
                importUnits: result.importUnits.isEmpty
                    ? OCRContextExtractor.importUnits(
                        fullText: cleanedText,
                        highlightedWords: result.highlightedWords
                    )
                    : result.importUnits,
                sourceImagePath: sourceImagePath
            )
        }
        return nil
    }

    static func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
        if provider.canLoadObject(ofClass: UIImage.self),
           let image = await loadUIImageObject(from: provider) {
            return image
        }

        for typeIdentifier in imageTypePriority where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let data = await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier),
               let image = UIImage(data: data) {
                return image
            }
            if let image = await loadFileImage(from: provider, typeIdentifier: typeIdentifier) {
                return image
            }
        }
        return nil
    }

    private static func loadUIImageObject(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    private static func loadFileImage(from provider: NSItemProvider, typeIdentifier: String) async -> UIImage? {
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
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    #endif
}
