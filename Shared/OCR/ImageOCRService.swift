import Foundation
import os
#if canImport(UIKit)
import UIKit
import Vision
#endif

enum ImageOCRService {
    /// Set false to silence `[OCR]` console diagnostics.
    static var debugLoggingEnabled = true

    private static let logger = Logger(subsystem: "com.knowell.app1", category: "OCR")

    /// Backward-compatible: full text only.
    static func recognizeText(in image: UIImage) async throws -> String {
        try await recognize(in: image).fullText
    }

    /// Vision OCR + OpenCV-style highlighter mask → candidate vocabulary words.
    static func recognize(in image: UIImage) async throws -> OCRResult {
        #if canImport(UIKit)
        guard let cgImage = image.normalizedCGImageForOCR() else {
            log("abort: normalized CGImage is nil")
            return .empty
        }

        log("""
        ——— OCR start ———
        1) image \(cgImage.width)x\(cgImage.height)
        """)

        async let maskTask: HighlightMaskDetector.Mask? = Task.detached(priority: .userInitiated) {
            HighlightMaskDetector.makeMask(from: cgImage)
        }.value

        let vision = try await recognizeVision(in: cgImage)
        log("""
        2) Vision lines=\(vision.fullText.split(separator: "\n").count) tokens=\(vision.tokens.count)
           fullText preview: \(vision.fullText.prefix(160).replacingOccurrences(of: "\n", with: "↵"))
        """)

        let mask = await maskTask
        if let mask {
            let on = mask.bytes.reduce(0) { $0 + Int($1) }
            let ratio = Double(on) / Double(max(mask.bytes.count, 1))
            log("3) highlight mask \(mask.width)x\(mask.height) ink=\(on) ratio=\(String(format: "%.4f", ratio)) (need 0.002…0.55)")
        } else {
            log("3) highlight mask = nil → no highlighted words")
        }

        let highlighted = extractHighlightedWords(from: vision.tokens, mask: mask)
        let units = OCRContextExtractor.importUnits(
            fullText: vision.fullText,
            highlightedWords: highlighted
        )
        log("""
        5) highlightedWords=\(highlighted)
        6) importUnits=\(units.map { "[\($0.words.joined(separator: ", "))] \($0.sentence.prefix(72))" })
        ——— OCR end ———
        """)
        return OCRResult(
            fullText: vision.fullText,
            highlightedWords: highlighted,
            importUnits: units
        )
        #else
        _ = image
        return .empty
        #endif
    }

    private static func log(_ message: String) {
        guard debugLoggingEnabled else { return }
        // App + Share/Action extensions: pick the matching process in Xcode Console.
        NSLog("[OCR] %@", message)
        logger.notice("\(message, privacy: .public)")
    }

    #if canImport(UIKit)
    private struct OCRToken {
        let text: String
        let boundingBox: CGRect
        let lineIndex: Int
    }

    private struct VisionPayload {
        let fullText: String
        let tokens: [OCRToken]
    }

    private static func recognizeVision(in cgImage: CGImage) async throws -> VisionPayload {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { lhs, rhs in
                        let l = lhs.boundingBox
                        let r = rhs.boundingBox
                        if abs(l.maxY - r.maxY) > 0.02 {
                            return l.maxY > r.maxY
                        }
                        return l.minX < r.minX
                    }

                var lines: [String] = []
                var tokens: [OCRToken] = []
                for (lineIndex, observation) in observations.enumerated() {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    tokens.append(contentsOf: tokenize(candidate, lineIndex: lineIndex))
                }
                continuation.resume(
                    returning: VisionPayload(
                        fullText: sanitizeOCRText(lines.joined(separator: "\n")),
                        tokens: tokens
                    )
                )
            }

            configure(request)
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func tokenize(_ candidate: VNRecognizedText, lineIndex: Int) -> [OCRToken] {
        let string = candidate.string
        guard !string.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        // Latin words / numbers
        let latin = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9'’\-]*"#)
        let ns = string as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let latin {
            for match in latin.matches(in: string, range: full) {
                if let range = Range(match.range, in: string) {
                    ranges.append(range)
                }
            }
        }
        // CJK runs (1+ ideographs)
        let cjk = try? NSRegularExpression(pattern: #"[\u4E00-\u9FFF\u3400-\u4DBF]{1,12}"#)
        if let cjk {
            for match in cjk.matches(in: string, range: full) {
                if let range = Range(match.range, in: string) {
                    ranges.append(range)
                }
            }
        }

        ranges.sort { $0.lowerBound < $1.lowerBound }

        if ranges.isEmpty {
            if let box = try? candidate.boundingBox(for: string.startIndex..<string.endIndex) {
                return [OCRToken(text: string, boundingBox: box.boundingBox, lineIndex: lineIndex)]
            }
            return []
        }

        var tokens: [OCRToken] = []
        for range in ranges {
            let text = String(string[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let box = try? candidate.boundingBox(for: range) else { continue }
            tokens.append(OCRToken(text: text, boundingBox: box.boundingBox, lineIndex: lineIndex))
        }
        return tokens
    }

    private static func extractHighlightedWords(
        from tokens: [OCRToken],
        mask: HighlightMaskDetector.Mask?
    ) -> [String] {
        guard let mask else { return [] }
        // Require enough highlight ink overall; otherwise treat as no markers.
        let highlightRatio = Double(mask.bytes.reduce(0) { $0 + Int($1) }) / Double(max(mask.bytes.count, 1))
        guard highlightRatio >= 0.002, highlightRatio <= 0.55 else {
            log("4) skip tokens: mask ratio \(String(format: "%.4f", highlightRatio)) out of range")
            return []
        }

        // True markers on this page land ~0.44 with mid-tight mask; prior bleed ("great")
        // no longer appears once HSV/morph are tightened — so 0.40 is safe here.
        // Do not require centerOn — glyph centers often sit on black strokes, not yellow ink.
        let threshold = 0.40
        var coverageRows: [String] = []
        let flagged = tokens.enumerated().map { index, token -> Bool in
            let coverage = mask.highlightCoverage(ofNormalizedBox: token.boundingBox)
            let hit = coverage >= threshold
            // Only print hits + near-misses to keep Console readable.
            if hit || coverage >= 0.20 {
                coverageRows.append(
                    String(
                        format: "   [%02d] L%d %-16@ cov=%.2f %@ box=(%.2f,%.2f,%.2f×%.2f)",
                        index,
                        token.lineIndex,
                        token.text as NSString,
                        coverage,
                        hit ? "HIT" : "near",
                        token.boundingBox.minX,
                        token.boundingBox.minY,
                        token.boundingBox.width,
                        token.boundingBox.height
                    )
                )
            }
            return hit
        }
        log("""
        4) token×mask (threshold=\(threshold); show HIT + cov≥0.20)
        \(coverageRows.isEmpty ? "   (none)" : coverageRows.joined(separator: "\n"))
        """)

        guard flagged.contains(true) else {
            log("4b) no token passed coverage threshold")
            return []
        }

        // If almost every token is flagged, user likely tinted the whole paragraph.
        let flaggedCount = flagged.filter { $0 }.count
        if Double(flaggedCount) / Double(max(tokens.count, 1)) >= 0.85, tokens.count >= 8 {
            log("4b) skip: \(flaggedCount)/\(tokens.count) flagged (≥85%) → treat as whole-page tint")
            return []
        }

        var phrases: [String] = []
        var current: [String] = []
        var lastLine = -1

        for (index, token) in tokens.enumerated() {
            guard flagged[index] else {
                flushPhrase(&current, into: &phrases)
                continue
            }
            if token.lineIndex != lastLine, !current.isEmpty {
                flushPhrase(&current, into: &phrases)
            }
            current.append(token.text)
            lastLine = token.lineIndex
        }
        flushPhrase(&current, into: &phrases)

        log("4c) merged phrases before dedupe: \(phrases)")

        var seen = Set<String>()
        var unique: [String] = []
        for phrase in phrases {
            let key = phrase.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(phrase)
        }
        return unique
    }

    private static func flushPhrase(_ parts: inout [String], into phrases: inout [String]) {
        defer { parts.removeAll(keepingCapacity: true) }
        guard !parts.isEmpty else { return }
        let joined: String
        if parts.allSatisfy(isMostlyCJK) {
            joined = parts.joined()
        } else {
            joined = parts.joined(separator: " ")
        }
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        // Vocabulary-sized spans only.
        guard trimmed.count >= 1, trimmed.count <= 40 else { return }
        if trimmed.count >= 28, trimmed.contains(where: { $0.isWhitespace }) { return }
        phrases.append(trimmed)
    }

    private static func isMostlyCJK(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let cjk = scalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }.count
        return Double(cjk) / Double(scalars.count) >= 0.6
    }

    private static func configure(_ request: VNRecognizeTextRequest) {
        request.recognitionLevel = .accurate
        // Language correction often mangles CJK into Latin symbols.
        request.usesLanguageCorrection = false

        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
            request.revision = VNRecognizeTextRequestRevision3
        }

        let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        let supported = Set(
            (try? request.supportedRecognitionLanguages()) ?? preferred
        )
        let languages = preferred.filter(supported.contains)
        if !languages.isEmpty {
            // Chinese first — English-first ordering commonly breaks 中文 OCR.
            request.recognitionLanguages = languages
        }
    }

    private static func sanitizeOCRText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}

#if canImport(UIKit)
private extension UIImage {
    /// Vision reads `cgImage` pixels as-up; honor `imageOrientation` first.
    func normalizedCGImageForOCR() -> CGImage? {
        if imageOrientation == .up, let cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
#endif
