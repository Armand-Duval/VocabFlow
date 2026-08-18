import Foundation
import os
#if canImport(UIKit)
import UIKit
import Vision
#endif

enum ImageOCRService {
    /// Set false to silence `[OCR]` console diagnostics.
    static var debugLoggingEnabled = true

    private static let logger = Logger(subsystem: "com.knowellcards.app", category: "OCR")

    /// Backward-compatible: full text only.
    static func recognizeText(in image: UIImage) async throws -> String {
        try await recognize(in: image).fullText
    }

    /// Vision OCR + OpenCV-style highlighter mask → candidate vocabulary words.
    static func recognize(in image: UIImage) async throws -> OCRResult {
        #if canImport(UIKit)
        guard let normalized = image.normalizedCGImageForOCR() else {
            log("abort: normalized CGImage is nil")
            return .empty
        }
        let cgImage = await uprightImageForOCR(normalized)

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
           fullText:
        \(vision.fullText.replacingOccurrences(of: "\n", with: "\n           "))
        """)

        let mask = await maskTask
        if let mask {
            let on = mask.bytes.reduce(0) { $0 + Int($1) }
            let ratio = Double(on) / Double(max(mask.bytes.count, 1))
            log("3) highlight mask \(mask.width)x\(mask.height) ink=\(on) ratio=\(String(format: "%.4f", ratio)) (need 0.002…0.55)")
        } else {
            log("3) highlight mask = nil → no highlighted words")
        }

        let highlighted = extractHighlightedWords(
            from: vision.tokens,
            mask: mask,
            fullText: vision.fullText
        )
        let units = OCRContextExtractor.importUnits(
            fullText: vision.fullText,
            highlightedWords: highlighted
        )
        let raw = OCRResult(
            fullText: vision.fullText,
            highlightedWords: highlighted,
            importUnits: units,
            sourceImagePath: nil,
            importKind: units.isEmpty ? .none : .highlight
        )
        var result = raw.sanitizedForImport()
        if result.importUnits.isEmpty {
            let leftColumn = leftColumnHeadwords(from: vision.tokens)
            if let page = OCRVocabPageExtractor.extract(
                fullText: result.fullText,
                leftColumnWords: leftColumn
            ) {
                result = OCRResult(
                    fullText: result.fullText,
                    highlightedWords: page.words,
                    importUnits: page.units,
                    sourceImagePath: nil,
                    importKind: .vocabPage
                )
                log("6b) vocab page headwords=\(page.words) leftColumn=\(leftColumn)")
            }
        }
        log("""
        5) highlightedWords=\(highlighted) → sanitized=\(result.highlightedWords)
        6) importUnits=\(units.map { "[\($0.words.joined(separator: ", "))] \($0.sentence.prefix(72))" })
           sanitizedUnits=\(result.importUnits.count) kind=\(String(describing: result.importKind)) preferHighlight=\(result.hasHighlightContext)
        ——— OCR end ———
        """)
        return result
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
        let lineText: String
    }

    private struct VisionPayload {
        let fullText: String
        let tokens: [OCRToken]
    }

    private struct LineHit {
        let string: String
        let box: CGRect
        let candidate: VNRecognizedText
        let confidence: Float
        /// Pixel crop in the full image (top-left origin). Nil = recognized on the full frame.
        var crop: CGRect? = nil
    }

    private static func recognizeVision(in cgImage: CGImage) async throws -> VisionPayload {
        // One mixed-language request + auto-detect often keeps HUD chips / names and
        // drops wrapped English dialogue (common on CN game screenshots).
        async let latin = recognizeLines(
            in: cgImage,
            languages: ["en-US"],
            languageCorrection: true
        )
        async let cjk = recognizeLines(
            in: cgImage,
            languages: ["zh-Hans", "zh-Hant", "ja-JP", "ko-KR"],
            languageCorrection: false
        )
        let latinHits = try await latin
        let cjkHits = try await cjk
        let fullSize = CGSize(width: cgImage.width, height: cgImage.height)
        var merged = mergeLineHits(latinHits, cjkHits)
        let pageChars = merged.reduce(0) { $0 + $1.string.count }
        let looksLikeBookPage = pageChars >= 180 || merged.count >= 6

        // Band crops help game screenshots; on a full book page they duplicate lines.
        if !looksLikeBookPage, let band = lowerBandCrop(cgImage) {
            let bandHits = try await recognizeLines(
                in: band.image,
                languages: ["en-US"],
                languageCorrection: false
            )
            let remapped = bandHits.map { hit in
                LineHit(
                    string: hit.string,
                    box: remapVisionBox(hit.box, crop: band.rect, full: fullSize),
                    candidate: hit.candidate,
                    confidence: hit.confidence,
                    crop: band.rect
                )
            }
            log("2b) lower-band crop \(Int(band.rect.width))x\(Int(band.rect.height)) @y=\(Int(band.rect.minY)) extraLines=\(remapped.count) \(remapped.map(\.string))")
            merged = mergeLineHits(merged, remapped)
        }

        if !looksLikeBookPage, let band = leftBandCrop(cgImage) {
            let bandHits = try await recognizeLines(
                in: band.image,
                languages: ["en-US"],
                languageCorrection: false,
                minimumTextHeight: 0.006
            )
            let remapped = bandHits.map { hit in
                LineHit(
                    string: hit.string,
                    box: remapVisionBox(hit.box, crop: band.rect, full: fullSize),
                    candidate: hit.candidate,
                    confidence: hit.confidence,
                    crop: band.rect
                )
            }
            log("2d) left-band crop \(Int(band.rect.width))x\(Int(band.rect.height)) extraLines=\(remapped.count) \(remapped.map(\.string))")
            merged = mergeLineHits(merged, remapped)
        }

        let ordered = merged.sorted(by: readingOrder)
        log("2c) merged lines:\n" + ordered.enumerated().map { index, hit in
            String(
                format: "   L%02d conf=%.2f box=(%.2f,%.2f %.2fx%.2f) %@",
                index,
                hit.confidence,
                hit.box.minX,
                hit.box.minY,
                hit.box.width,
                hit.box.height,
                hit.string as NSString
            )
        }.joined(separator: "\n"))

        var lines: [String] = []
        var allTokens: [OCRToken] = []
        for (lineIndex, hit) in ordered.enumerated() {
            lines.append(hit.string)
            allTokens.append(contentsOf: tokens(from: hit, lineIndex: lineIndex, fullSize: fullSize))
        }
        return VisionPayload(
            fullText: sanitizeOCRText(lines.joined(separator: "\n")),
            tokens: allTokens
        )
    }

    private static func recognizeLines(
        in cgImage: CGImage,
        languages: [String],
        languageCorrection: Bool,
        minimumTextHeight: Float = 0.008,
        orientation: CGImagePropertyOrientation = .up,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) async throws -> [LineHit] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let hits = observations.compactMap(bestLineHit(from:))
                continuation.resume(returning: hits)
            }
            configure(
                request,
                languages: languages,
                languageCorrection: languageCorrection,
                minimumTextHeight: minimumTextHeight,
                recognitionLevel: recognitionLevel
            )
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Prefer a complete line over a truncated top candidate with slightly higher confidence.
    private static func bestLineHit(from observation: VNRecognizedTextObservation) -> LineHit? {
        let candidates = observation.topCandidates(3)
        guard let best = candidates.max(by: { lineScore($0) < lineScore($1) }) else { return nil }
        let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return LineHit(
            string: text,
            box: observation.boundingBox,
            candidate: best,
            confidence: best.confidence,
            crop: nil
        )
    }

    private static func lineScore(_ candidate: VNRecognizedText) -> Float {
        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let dashes = text.filter(isOCRDash).count
        return candidate.confidence * 0.55
            + Float(letters) * 0.012
            + Float(text.count) * 0.004
            - Float(dashes) * 0.08
    }

    private static func mergeLineHits(_ lhs: [LineHit], _ rhs: [LineHit]) -> [LineHit] {
        var merged = lhs
        for hit in rhs {
            if let index = merged.firstIndex(where: { boxesOverlap($0.box, hit.box) }) {
                if shouldReplace(merged[index], with: hit) {
                    merged[index] = hit
                }
            } else {
                merged.append(hit)
            }
        }
        return merged
    }

    private static func shouldReplace(_ current: LineHit, with incoming: LineHit) -> Bool {
        if incoming.string.count >= current.string.count + 3 { return true }
        if incoming.string.count + 3 <= current.string.count { return false }
        return incoming.confidence > current.confidence + 0.08
    }

    private static func boxesOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return false }
        let union = a.union(b)
        let iou = (inter.width * inter.height) / max(union.width * union.height, 0.0001)
        return iou >= 0.45
    }

    private static func readingOrder(_ lhs: LineHit, _ rhs: LineHit) -> Bool {
        let l = lhs.box
        let r = rhs.box
        if abs(l.maxY - r.maxY) > 0.02 {
            return l.maxY > r.maxY
        }
        return l.minX < r.minX
    }

    private static func lowerBandCrop(_ image: CGImage, topFraction: CGFloat = 0.40) -> (image: CGImage, rect: CGRect)? {
        let y = Int((CGFloat(image.height) * topFraction).rounded(.down))
        let rect = CGRect(x: 0, y: y, width: image.width, height: image.height - y)
        guard rect.height >= 96, let cropped = image.cropping(to: rect) else { return nil }
        return (cropped, rect)
    }

    /// Dictionary headwords usually sit in the left column; a dedicated English pass
    /// recovers lemmas that mixed CJK recognition drops.
    private static func leftBandCrop(_ image: CGImage, widthFraction: CGFloat = 0.42) -> (image: CGImage, rect: CGRect)? {
        let width = Int((CGFloat(image.width) * widthFraction).rounded(.down))
        let rect = CGRect(x: 0, y: 0, width: width, height: image.height)
        guard rect.width >= 80, let cropped = image.cropping(to: rect) else { return nil }
        return (cropped, rect)
    }

    private static func leftColumnHeadwords(from tokens: [OCRToken]) -> [String] {
        let grouped = Dictionary(grouping: tokens, by: \.lineIndex)
        var words: [String] = []
        var seen = Set<String>()
        for lineIndex in grouped.keys.sorted() {
            let lineTokens = grouped[lineIndex]!.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let latinCount = lineTokens.filter { token in
                token.text.first?.isASCII == true && token.text.first?.isLetter == true
            }.count
            // Long English prose lines are not a headword column.
            if latinCount >= 7 { continue }
            guard let first = lineTokens.first(where: { OCRVocabPageExtractor.looksLikeHeadword($0.text) }) else {
                continue
            }
            guard first.boundingBox.minX < 0.34 else { continue }
            let key = first.text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            words.append(first.text)
        }
        return words
    }

    /// Map a Vision box from a pixel crop (top-left origin) onto the full image.
    private static func remapVisionBox(_ box: CGRect, crop: CGRect, full: CGSize) -> CGRect {
        let cropFromBottom = full.height - (crop.minY + crop.height)
        let minX = (crop.minX + box.minX * crop.width) / full.width
        let maxX = (crop.minX + box.maxX * crop.width) / full.width
        let minY = (cropFromBottom + box.minY * crop.height) / full.height
        let maxY = (cropFromBottom + box.maxY * crop.height) / full.height
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }

    private static func tokens(from hit: LineHit, lineIndex: Int, fullSize: CGSize) -> [OCRToken] {
        let raw = tokenize(hit.candidate, lineIndex: lineIndex)
        guard let crop = hit.crop else { return raw }
        return raw.map { token in
            OCRToken(
                text: token.text,
                boundingBox: remapVisionBox(token.boundingBox, crop: crop, full: fullSize),
                lineIndex: token.lineIndex,
                lineText: token.lineText
            )
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
                return [OCRToken(text: string, boundingBox: box.boundingBox, lineIndex: lineIndex, lineText: string)]
            }
            return []
        }

        var tokens: [OCRToken] = []
        for range in ranges {
            let text = String(string[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let box = try? candidate.boundingBox(for: range) else { continue }
            tokens.append(OCRToken(text: text, boundingBox: box.boundingBox, lineIndex: lineIndex, lineText: string))
        }
        return tokens
    }

    private static func extractHighlightedWords(
        from tokens: [OCRToken],
        mask: HighlightMaskDetector.Mask?,
        fullText: String
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
        let threshold = HighlightPhraseMerger.hitThreshold
        var coverageRows: [String] = []
        let mergerTokens: [HighlightPhraseMerger.Token] = tokens.enumerated().map { index, token in
            let boxArea = token.boundingBox.width * token.boundingBox.height
            let overlay = OCRChromeFilter.looksLikeOverlayControl(
                token: token.text,
                lineText: token.lineText,
                boxArea: boxArea
            )
            // Overlay glow must not seed the highlighter merger (logging-only skip leaked hits).
            let coverage = overlay ? 0 : mask.highlightCoverage(ofNormalizedBox: token.boundingBox)
            let hit = coverage >= threshold
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
            return HighlightPhraseMerger.Token(
                text: token.text,
                lineIndex: token.lineIndex,
                coverage: coverage,
                minX: Double(token.boundingBox.minX),
                maxX: Double(token.boundingBox.maxX)
            )
        }
        log("""
        4) token×mask (threshold=\(threshold); show HIT + cov≥0.20)
        \(coverageRows.isEmpty ? "   (none)" : coverageRows.joined(separator: "\n"))
        """)

        let unique = HighlightPhraseMerger.merge(
            tokens: mergerTokens,
            hitThreshold: threshold,
            pageText: fullText
        )
        let refined = HighlightPhraseMerger.refine(unique, against: fullText)
        if refined.isEmpty {
            log("4b) no merged highlight phrases")
        } else {
            log("4c) merged phrases: \(unique) → refined: \(refined)")
        }
        return refined
    }

    private static func configure(
        _ request: VNRecognizeTextRequest,
        languages: [String],
        languageCorrection: Bool,
        minimumTextHeight: Float = 0.008,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) {
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = languageCorrection
        // Catch wrapped / smaller dialogue lines on screenshots.
        request.minimumTextHeight = minimumTextHeight

        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = false
            request.revision = VNRecognizeTextRequestRevision3
        }

        let supported = Set((try? request.supportedRecognitionLanguages()) ?? languages)
        let filtered = languages.filter(supported.contains)
        if !filtered.isEmpty {
            request.recognitionLanguages = filtered
        }
    }

    /// Vision often reads wrap hyphens / gutter gaps as em dashes:
    /// `algebra — ist` → `algebraist`, `告 — 诫` → `告诫`, `uses — humor` → `uses humor`.
    static func sanitizeOCRText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { repairOCRDashes($0.trimmingCharacters(in: .whitespacesAndNewlines), stripEdges: false) }
            .filter { !$0.isEmpty }

        var cleaned: [String] = []
        for line in lines {
            if let last = cleaned.last, isNearDuplicateOCRLine(last, line) {
                if line.count > last.count {
                    cleaned[cleaned.count - 1] = line
                }
                continue
            }
            cleaned.append(line)
        }

        return repairOCRDashes(unwrapOCRLines(cleaned), stripEdges: true)
    }

    /// Real dash glyphs (not ICU `\u{…}` escapes — those stay literal in raw strings
    /// and never match the em dashes Vision emits).
    private static let ocrDashClass = "[\u{00AD}\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}]"

    private static func repairOCRDashes(_ text: String, stripEdges: Bool) -> String {
        var value = text
        let dash = ocrDashClass

        value = value.replacingOccurrences(
            of: "\\s*\(dash)\\s*([,.;:!?…])",
            with: "$1",
            options: .regularExpression
        )

        if stripEdges {
            value = value.replacingOccurrences(
                of: "^\\s*\(dash)\\s+",
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(
                of: "\\s+\(dash)\\s*$",
                with: "",
                options: .regularExpression
            )
        }

        var previous = ""
        while previous != value {
            previous = value
            value = value.replacingOccurrences(
                of: "(\\p{Han})\\s*(?:\(dash)|-)\\s*(\\p{Han})",
                with: "$1$2",
                options: .regularExpression
            )
        }

        value = repairLatinOCRDashes(value)

        if stripEdges {
            value = value.replacingOccurrences(
                of: "\\s+\(dash)\\s+",
                with: " ",
                options: .regularExpression
            )
        }

        value = value.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let hyphenationSuffixes: Set<String> = [
        "ist", "ists", "ism", "isms",
        "ing", "ings", "ted", "led", "ned", "red",
        "er", "ers", "est",
        "tion", "ation", "sion", "ions",
        "ness", "ment", "ments",
        "able", "ible", "ical", "ally",
        "ous", "ious", "eous",
        "ful", "less", "hood", "ship",
        "ize", "ized", "izing", "ise", "ised",
        "ate", "ated", "ator",
        "ence", "ance", "ent", "ant",
        "ive", "ory", "ary", "ure", "age",
        "ity", "ties", "ly", "ed",
        "ning", "ting", "ling", "ring", "ming",
        "graphy", "logy"
    ]

    private static func repairLatinOCRDashes(_ text: String) -> String {
        let dash = ocrDashClass
        let pattern = "([A-Za-z]+)(?:\\s*\(dash)\\s*|\\s+-\\s+)([A-Za-z]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        var guardCount = 0
        while guardCount < 32 {
            guardCount += 1
            let ns = result as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: result, range: range),
                  let full = Range(match.range, in: result),
                  let leftRange = Range(match.range(at: 1), in: result),
                  let rightRange = Range(match.range(at: 2), in: result)
            else { break }

            let left = String(result[leftRange])
            let right = String(result[rightRange])
            let joined = hyphenationSuffixes.contains(right.lowercased())
            result.replaceSubrange(full, with: joined ? left + right : left + " " + right)
        }
        return result
    }

    /// Book typesetting wraps mid-sentence. Join those visual lines; keep a break only between paragraphs.
    private static func unwrapOCRLines(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        let average = lines.reduce(0) { $0 + $1.count } / max(lines.count, 1)
        let shortCount = lines.filter { $0.count < 28 }.count
        // Word lists / vocab pages should keep one entry per line.
        if lines.count >= 6, average < 32, shortCount * 2 >= lines.count {
            return lines.joined(separator: "\n")
        }

        var current = ""
        for line in lines {
            if current.isEmpty {
                current = line
                continue
            }
            current = joinWrappedOCRLine(current, line)
        }
        return current.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func joinWrappedOCRLine(_ left: String, _ right: String) -> String {
        if let first = right.first, first.isLetter || isCJKScalar(first),
           let last = left.last, last.isWhitespace || isOCRDash(last) {
            return strippingTrailingOCRDash(left) + right
        }

        let leftIsCJK = left.last.map(isCJKScalar) ?? false
        let rightIsCJK = right.first.map(isCJKScalar) ?? false
        if leftIsCJK || rightIsCJK {
            return left + right
        }
        return left + " " + right
    }

    private static func strippingTrailingOCRDash(_ line: String) -> String {
        var value = line
        while let last = value.last {
            if last.isWhitespace || isOCRDash(last) {
                value.removeLast()
                continue
            }
            break
        }
        return value
    }

    private static func isOCRDash(_ character: Character) -> Bool {
        switch character {
        case "-", "\u{00AD}", "\u{2010}", "\u{2011}", "\u{2012}",
             "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}":
            return true
        default:
            return false
        }
    }

    private static func isCJKScalar(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private static func isNearDuplicateOCRLine(_ a: String, _ b: String) -> Bool {
        func letters(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isWhitespace }
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        let left = letters(a)
        let right = letters(b)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        if left.count >= 18, right.count >= 18 {
            return left.contains(right) || right.contains(left)
        }
        return false
    }

    /// Book photos are often shot sideways. Probe 4 directions with a cheap pass, then bake pixels upright.
    private static func uprightImageForOCR(_ image: CGImage) async -> CGImage {
        let probe = downscaledCGImage(image, maxSide: 960) ?? image
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        var best: (orientation: CGImagePropertyOrientation, score: Int) = (.up, Int.min)
        for orientation in orientations {
            let hits = (try? await recognizeLines(
                in: probe,
                languages: ["en-US", "zh-Hans"],
                languageCorrection: false,
                minimumTextHeight: 0.01,
                orientation: orientation,
                recognitionLevel: .fast
            )) ?? []
            let score = orientationScore(hits)
            log("orientation \(orientation.rawValue) score=\(score) lines=\(hits.count)")
            if score > best.score {
                best = (orientation, score)
            }
        }
        guard best.orientation != .up, best.score > 0 else { return image }
        log("rotate OCR image to orientation \(best.orientation.rawValue)")
        return rotatedCGImage(image, orientation: best.orientation) ?? image
    }

    private static func orientationScore(_ hits: [LineHit]) -> Int {
        var score = 0
        for hit in hits {
            let letters = hit.string.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            score += letters * 3
            score += min(hit.string.count, 48)
            if hit.box.width > hit.box.height * 1.5 {
                score += 10
            }
            if hit.box.height > hit.box.width * 1.5 {
                score -= 14
            }
            if hit.string.contains("—") {
                score -= 6
            }
        }
        return score
    }

    private static func downscaledCGImage(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = CGFloat(maxSide) / CGFloat(longest)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private static func rotatedCGImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let uiOrientation: UIImage.Orientation
        switch orientation {
        case .up: return image
        case .down: uiOrientation = .down
        case .left: uiOrientation = .left
        case .right: uiOrientation = .right
        default: return image
        }
        let uiImage = UIImage(cgImage: image, scale: 1, orientation: uiOrientation)
        return uiImage.normalizedCGImageForOCR()
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
