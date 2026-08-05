import Foundation
import SwiftData
import UIKit

extension Notification.Name {
    static let dailyAutoBackupBannerDidChange = Notification.Name("knowell.dailyAutoBackup.bannerDidChange")
}

/// Daily JSON + Anki backups. iOS cannot run code at exact midnight while killed;
/// we catch up on the first launch/activation after local midnight, and also fire
/// when the app stays foreground across midnight.
@MainActor
enum DailyAutoBackupService {
    private static let enabledKey = "backup.dailyAuto.enabled"
    private static let lastCompletedDayKey = "backup.dailyAuto.lastCompletedDay"
    private static let bannerVisibleKey = "backup.dailyAuto.bannerVisible"
    private static let bannerTextKey = "backup.dailyAuto.bannerText"
    private static let keepDays = 14

    private static var midnightTask: Task<Void, Never>?
    private static var isRunning = false

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var pendingBannerText: String? {
        guard defaults.bool(forKey: bannerVisibleKey) else { return nil }
        let text = defaults.string(forKey: bannerTextKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : L10n.libraryAutoBackupBanner
    }

    static func dismissBanner() {
        defaults.set(false, forKey: bannerVisibleKey)
        defaults.removeObject(forKey: bannerTextKey)
        NotificationCenter.default.post(name: .dailyAutoBackupBannerDidChange, object: nil)
    }

    /// Opens the AutoBackup folder in the system Files app (UIFileSharingEnabled).
    @discardableResult
    static func openAutoBackupInFiles() -> Bool {
        guard let folder = try? autoBackupDirectory(),
              let url = filesAppURL(for: folder) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    /// Call on app launch / becoming active.
    static func runIfNeeded(in context: ModelContext) async {
        guard isEnabled else {
            AppLog.info("Daily auto-backup skipped (disabled)", category: "Backup")
            scheduleMidnightWatch(in: context)
            return
        }
        await performBackupIfDue(in: context)
        scheduleMidnightWatch(in: context)
    }

    private static func scheduleMidnightWatch(in context: ModelContext) {
        midnightTask?.cancel()
        guard isEnabled else { return }
        guard let nextMidnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let delay = max(1, nextMidnight.timeIntervalSinceNow)
        midnightTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await performBackupIfDue(in: context)
            scheduleMidnightWatch(in: context)
        }
    }

    private static func performBackupIfDue(in context: ModelContext) async {
        guard isEnabled else { return }
        let today = dayKey(.now)
        if defaults.string(forKey: lastCompletedDayKey) == today {
            AppLog.debug("Daily auto-backup already done for \(today)", category: "Backup")
            return
        }
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            let cards = try context.fetch(FetchDescriptor<FlashCard>())
            guard !cards.isEmpty else {
                // Nothing to back up — still mark the day so we don't retry endlessly.
                defaults.set(today, forKey: lastCompletedDayKey)
                AppLog.info("Daily auto-backup: no cards, marked \(today)", category: "Backup")
                return
            }
            let decks = try context.fetch(
                FetchDescriptor<Deck>(
                    sortBy: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)]
                )
            )

            let folder = try autoBackupDirectory()
            let stamp = today
            let jsonURL = folder.appendingPathComponent("knowell-auto-\(stamp).json")
            let apkgURL = folder.appendingPathComponent("knowell-auto-\(stamp).apkg")

            let jsonData = try BackupService.export(cards: cards, decks: decks)
            try jsonData.write(to: jsonURL, options: .atomic)

            let apkgData = try ApkgExportService.export(cards: cards, deckName: nil)
            try apkgData.write(to: apkgURL, options: .atomic)

            try pruneOldBackups(in: folder, keepingDays: keepDays)

            defaults.set(today, forKey: lastCompletedDayKey)
            defaults.set(true, forKey: bannerVisibleKey)
            defaults.set(L10n.libraryAutoBackupBanner, forKey: bannerTextKey)
            BackupReminderService.recordBackupCompleted()
            NotificationCenter.default.post(name: .dailyAutoBackupBannerDidChange, object: nil)
            AppLog.info(
                "Daily auto-backup ok: \(cards.count) cards → \(jsonURL.lastPathComponent), \(apkgURL.lastPathComponent)",
                category: "Backup"
            )
        } catch {
            AppLog.error("Daily auto-backup failed: \(error.localizedDescription)", category: "Backup")
        }
    }

    private static func autoBackupDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = docs.appendingPathComponent("AutoBackup", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Undocumented but widely used scheme to reveal a Documents path in Files.
    private static func filesAppURL(for fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "shareddocuments"
        components.path = fileURL.path
        return components.url
    }

    private static func pruneOldBackups(in folder: URL, keepingDays: Int) throws {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: .now) ?? .distantPast
        let files = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in files {
            guard url.pathExtension == "json" || url.pathExtension == "apkg" else { continue }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func dayKey(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
