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

    static func loadText(from provider: NSItemProvider) async -> String? {
        guard let typeIdentifier = preferredTypeIdentifier(for: provider) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                let text = cleaned(parseItem(item, typeIdentifier: typeIdentifier))
                continuation.resume(returning: text)
            }
        }
    }

    static func loadText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if let text = await loadText(from: provider), isUsefulQuote(text) {
                return text
            }
        }
        return nil
    }

    static func parseItem(_ item: NSSecureCoding?, typeIdentifier: String) -> String {
        if let text = item as? String {
            return normalizeSharedString(text, typeIdentifier: typeIdentifier)
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string
        }
        if let data = item as? Data {
            return parseData(data, typeIdentifier: typeIdentifier)
        }
        if let url = item as? URL {
            if url.isFileURL {
                return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            if typeIdentifier == UTType.url.identifier {
                return url.absoluteString
            }
        }
        return ""
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

    private static func normalizeSharedString(_ text: String, typeIdentifier: String) -> String {
        if typeIdentifier == UTType.html.identifier {
            return stripHTML(text)
        }
        return text
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

    #if canImport(UIKit)
    private static let imageTypePriority: [String] = [
        UTType.image.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        "public.image"
    ]

    static func loadTextFromImages(from extensionItems: [NSExtensionItem]) async -> String? {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        for provider in providers {
            guard let image = await loadUIImage(from: provider) else { continue }
            guard let text = try? await ImageOCRService.recognizeText(in: image) else { continue }
            if let cleaned = cleaned(text) {
                return cleaned
            }
        }
        return nil
    }

    static func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
        for typeIdentifier in imageTypePriority where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let image = await loadUIImage(from: provider, typeIdentifier: typeIdentifier) {
                return image
            }
        }
        return nil
    }

    private static func loadUIImage(from provider: NSItemProvider, typeIdentifier: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let image = item as? UIImage {
                    continuation.resume(returning: image)
                    return
                }
                if let url = item as? URL,
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                    return
                }
                if let data = item as? Data,
                   let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
    #endif
}
