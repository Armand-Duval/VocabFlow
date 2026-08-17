import CryptoKit
import Foundation
import UIKit

struct OriginalPackRecord: Sendable {
    let fileURL: URL
    let fileName: String
    let byteCount: Int
    let sha256: String
}

/// Keeps the untouched download / import bytes so they can be compared with
/// a copy fetched outside the app. This is not the KnoWell-exported apkg.
enum OriginalPackArchive {
    static let folderName = "OriginalPacks"

    static func directory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = docs.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    static func save(
        data: Data,
        suggestedName: String,
        fileExtension: String,
        sourceURL: URL? = nil
    ) throws -> OriginalPackRecord {
        let folder = try directory()
        let base = sanitizedName(suggestedName)
        let ext = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let stamp = dayStamp(.now)
        let fileName = "\(base)-\(stamp).\(ext)"
        let fileURL = folder.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)

        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let meta: [String: Any] = [
            "fileName": fileName,
            "byteCount": data.count,
            "sha256": sha256,
            "sourceURL": sourceURL?.absoluteString ?? "",
            "savedAt": ISO8601DateFormatter().string(from: .now)
        ]
        if let metaData = try? JSONSerialization.data(
            withJSONObject: meta,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? metaData.write(
                to: folder.appendingPathComponent("\(fileName).meta.json"),
                options: .atomic
            )
        }

        try pruneIfNeeded(in: folder, keeping: 12)
        return OriginalPackRecord(
            fileURL: fileURL,
            fileName: fileName,
            byteCount: data.count,
            sha256: sha256
        )
    }

    @discardableResult
    static func openInFiles() -> Bool {
        guard let folder = try? directory() else { return false }
        var components = URLComponents()
        components.scheme = "shareddocuments"
        components.path = folder.path
        guard let url = components.url else { return false }
        UIApplication.shared.open(url)
        return true
    }

    static func hasSavedPacks() -> Bool {
        guard let folder = try? directory() else { return false }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "apkg" || ext == "json" || ext == "zip"
        }
    }

    private static func pruneIfNeeded(in folder: URL, keeping: Int) throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "apkg" || ext == "json" || ext == "zip"
        }
        .sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        for url in files.dropFirst(keeping) {
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: url.appendingPathExtension("meta.json"))
            let sidecar = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".meta.json")
            try? fm.removeItem(at: sidecar)
        }
    }

    private static func sanitizedName(_ name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let allowed = cleaned.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " }
        let collapsed = allowed
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .joined(separator: "_")
        return collapsed.isEmpty ? "pack" : String(collapsed.prefix(48))
    }

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
