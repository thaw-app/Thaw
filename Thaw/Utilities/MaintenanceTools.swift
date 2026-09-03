//
//  MaintenanceTools.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Subprocess
// Prefer the `System` module when available: Subprocess's API surface uses
// `System.FilePath`, so both sides must resolve to the same module or the
// types won't unify.
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
    private static let legacyCacheDirectoryName = "com.stonerl.thaw"

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

    /// Quits the menu bar hosting process and deletes its preference plist, so
    /// every saved status-item position is rebuilt from scratch.
    ///
    /// `cfprefsd` is restarted *before* the delete: it caches other processes'
    /// domains, and would otherwise flush its stale copy back over the removal.
    @concurrent
    static func resetMenuBarLayoutPositions() async throws {
        // Best-effort: neither process is guaranteed to be running.
        try? await run(path: "/usr/bin/killall", arguments: [menuBarHostingProcessName])
        try? await run(path: "/usr/bin/killall", arguments: ["cfprefsd"])

        let fileManager = FileManager.default
        let preferences = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences", directoryHint: .isDirectory)

        let hostingBundleID = SharedConstants.menuBarHostingBundleID
        try removeItemIfExists(
            at: preferences.appending(path: "\(hostingBundleID).plist"),
            using: fileManager
        )

        let byHost = preferences.appending(path: "ByHost", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: byHost.path(percentEncoded: false)) else {
            return
        }
        let byHostFiles = try fileManager.contentsOfDirectory(
            at: byHost,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for fileURL in byHostFiles where fileURL.lastPathComponent.hasPrefix(hostingBundleID) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Process name to `killall` for the current platform's menu bar host.
    private static var menuBarHostingProcessName: String {
        "ControlCenter"
    }

    /// Deletes Thaw's user cache directory (`~/Library/Caches/<bundle id>`).
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
        for directoryName in appCacheDirectoryNames(bundleIdentifier: bundleIdentifier) {
            let cacheDirectory = cachesDirectory.appending(path: directoryName, directoryHint: .isDirectory)
            try removeItemIfExists(at: cacheDirectory, using: fileManager)
        }
    }

    /// Removes the item at `url` when it exists. Any removal error propagates.
    private static func removeItemIfExists(at url: URL, using fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    static func appCacheDirectoryNames(bundleIdentifier: String) -> [String] {
        var names = [bundleIdentifier]
        if bundleIdentifier != legacyCacheDirectoryName {
            names.append(legacyCacheDirectoryName)
        }
        return names
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
