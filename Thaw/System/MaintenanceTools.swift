//
//  MaintenanceTools.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import PlatformRuntimeKit
import Subprocess
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Destructive troubleshooting helpers used by Settings → Tools.
///
/// These operate on the current user's Library and TCC entries for Thaw's own
/// bundle identifier. They are intentionally narrow: no sudo, no other apps'
/// preferences beyond Control Center's menu-bar state plists.
nonisolated enum MaintenanceTools {
    nonisolated enum ToolError: LocalizedError {
        case commandFailed(String, Int32, String)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(command, status, detail):
                let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return String(localized: "\(command) failed with exit status \(status).")
                }
                return String(localized: "\(command) failed with exit status \(status): \(trimmed)")
            }
        }
    }

    /// Quits Control Center and deletes its user preference plists so menu bar
    /// item order/visibility can be rebuilt from a clean Control Center state.
    @concurrent
    static func resetControlCenterPreferences() async throws {
        // Best-effort: Control Center may not be running.
        try? await run(path: "/usr/bin/killall", arguments: ["ControlCenter"])

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let preferences = home.appending(path: "Library/Preferences", directoryHint: .isDirectory)

        let mainPlist = preferences.appending(path: "com.apple.controlcenter.plist")
        try removeItemIfExists(at: mainPlist, using: fileManager)

        let byHost = preferences.appending(path: "ByHost", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: byHost.path(percentEncoded: false)) else {
            return
        }

        let byHostFiles = try fileManager.contentsOfDirectory(
            at: byHost,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for fileURL in byHostFiles where fileURL.lastPathComponent.hasPrefix("com.apple.controlcenter") {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Quits the menu bar hosting process and deletes the files holding saved
    /// status-item positions, so every position is rebuilt from scratch.
    ///
    /// A backup is written first and returned, because this discards the
    /// user's entire menu bar arrangement. cfprefsd is restarted before
    /// the delete: it caches other processes' domains, and would otherwise
    /// flush its stale copy back over the removal.
    ///
    /// Returns the backup, or nil when there was nothing to back up.
    @concurrent
    @discardableResult
    static func resetMenuBarLayoutPositions() async throws -> MenuBarLayoutBackups.Backup? {
        let fileManager = FileManager.default
        let backup = try MenuBarLayoutBackups.capture(fileManager: fileManager)

        // Best-effort: neither process is guaranteed to be running.
        try? await run(path: "/usr/bin/killall", arguments: [menuBarHostingProcessName])
        try? await run(path: "/usr/bin/killall", arguments: ["cfprefsd"])

        let preferences = preferencesDirectory(fileManager: fileManager)
        let hostingBundleID = SharedConstants.menuBarHostingBundleID
        try removeItemIfExists(
            at: preferences.appending(path: "\(hostingBundleID).plist"),
            using: fileManager
        )
        // On macOS 27 the positions live in the MenuBar group container, not
        // the plist above; delete every file the backup just captured.
        for source in MenuBarLayoutBackups.liveSources(fileManager: fileManager) {
            try removeItemIfExists(at: source, using: fileManager)
        }

        let byHost = preferences.appending(path: "ByHost", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: byHost.path(percentEncoded: false)) else {
            return backup
        }
        let byHostFiles = try fileManager.contentsOfDirectory(
            at: byHost,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for fileURL in byHostFiles where fileURL.lastPathComponent.hasPrefix(hostingBundleID) {
            try fileManager.removeItem(at: fileURL)
        }
        return backup
    }

    /// Puts a layout backup back, after snapshotting what it overwrites.
    ///
    /// The undo snapshot is taken before anything is killed, and a failure to
    /// take it aborts the restore: an unundoable restore is what this surface
    /// exists to avoid.
    ///
    /// cfprefsd is stopped twice on purpose. Before the copy, because it
    /// caches other processes' domains and would flush its stale copy back
    /// over the files. After, because anything that read the domain during
    /// the copy re-cached the pre-restore contents, and the host reads
    /// through that cache when launchd brings it back.
    @concurrent
    static func restoreMenuBarLayout(
        from backup: MenuBarLayoutBackups.Backup
    ) async throws -> MenuBarLayoutBackups.RestoreReport {
        let fileManager = FileManager.default
        let undo: MenuBarLayoutBackups.Backup?
        do {
            undo = try MenuBarLayoutBackups.capture(fileManager: fileManager)
        } catch {
            throw MenuBarLayoutBackups.RestoreRefusal.undoBackupFailed(error)
        }

        // Best-effort: neither process is guaranteed to be running.
        try? await run(path: "/usr/bin/killall", arguments: [menuBarHostingProcessName])
        try? await run(path: "/usr/bin/killall", arguments: ["cfprefsd"])

        let outcome = try MenuBarLayoutBackups.restoreFiles(from: backup, fileManager: fileManager)

        try? await run(path: "/usr/bin/killall", arguments: ["cfprefsd"])

        return MenuBarLayoutBackups.RestoreReport(
            undoBackup: undo,
            restored: outcome.restored,
            skipped: outcome.skipped
        )
    }

    /// Process name to killall for the current platform's menu bar host.
    private static var menuBarHostingProcessName: String {
        "MenuBarAgent"
    }

    private static func preferencesDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences", directoryHint: .isDirectory)
    }

    /// Deletes Thaw's user cache directory (~/Library/Caches/<bundle id>).
    static func clearAppCache() throws {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches", directoryHint: .isDirectory)
        try clearAppCache(
            cachesDirectory: caches,
            bundleIdentifier: Constants.bundleIdentifier,
            fileManager: .default
        )
    }

    static func clearAppCache(
        cachesDirectory: URL,
        bundleIdentifier: String,
        fileManager: FileManager
    ) throws {
        let cacheDirectory = cachesDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
        try removeItemIfExists(at: cacheDirectory, using: fileManager)
    }

    /// Removes the item at url when it exists. Any removal error propagates.
    private static func removeItemIfExists(at url: URL, using fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    /// Resets Accessibility and Screen Recording TCC decisions for Thaw so the
    /// user can re-grant them on the next launch.
    @concurrent
    static func resetAppPermissions() async throws {
        let bundleID = Constants.bundleIdentifier
        try await run(path: "/usr/bin/tccutil", arguments: ["reset", "Accessibility", bundleID])
        try await run(path: "/usr/bin/tccutil", arguments: ["reset", "ScreenCapture", bundleID])
    }

    @concurrent
    private static func run(path: String, arguments: [String]) async throws {
        let result = try await Subprocess.run(
            .path(FilePath(path)),
            arguments: Arguments(arguments),
            output: .string(limit: 64 * 1024),
            error: .string(limit: 64 * 1024)
        )
        let exitStatus: Int32 = switch result.terminationStatus {
        case let .exited(code): code
        case let .signaled(code): code
        }
        guard result.terminationStatus.isSuccess else {
            let detail = [result.standardOutput, result.standardError]
                .compactMap(\.self)
                .joined(separator: "\n")
            throw ToolError.commandFailed(URL(fileURLWithPath: path).lastPathComponent, exitStatus, detail)
        }
    }
}
