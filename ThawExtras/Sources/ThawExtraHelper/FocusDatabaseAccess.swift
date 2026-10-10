//
//  FocusDatabaseAccess.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import OSLog

/// The entitled-only Focus service requires a database fallback; an open-panel selection grants this bundle folder-only access instead of EPERM.
/// Thaw's grants do not carry over, and database access reports Focus state but cannot switch modes.
@MainActor
final class FocusDatabaseAccess {
    private static let bookmarkKey = "FocusDatabaseBookmark"
    private static let folder = URL(filePath: NSHomeDirectory()).appending(path: "Library/DoNotDisturb/DB")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThawExtraHelper", category: "focus")
    private var scopedURL: URL?

    /// Re-arms a grant stored by an earlier launch. Does nothing without one.
    func activate() {
        guard scopedURL == nil, let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            logger.notice("Stored Focus bookmark no longer resolves; discarding it")
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return
        }
        // Outside the sandbox the pick itself is what the system remembers,
        // so a false return here is not a failure on its own.
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
        if isStale {
            store(url)
        }
    }

    /// Asks the user to pick the Focus folder. Returns whether it is readable
    /// afterwards.
    func request() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        // Open on the parent so "DB" is listed and can be selected. Opened on
        // the folder itself, the panel shows only its contents.
        panel.directoryURL = Self.folder.deletingLastPathComponent()
        panel.title = String(localized: "Allow Access to Focus")
        panel.message = String(
            localized: "Select the “DB” folder so Thaw's Focus icon can show which Focus is on. Thaw is granted access to this folder only."
        )
        panel.prompt = String(localized: "Allow Access")
        NSApp.activate()
        guard panel.runModal() == .OK, let picked = panel.url else { return false }
        guard picked.standardizedFileURL.path == Self.folder.standardizedFileURL.path else {
            logger.notice("Focus access panel returned another folder; ignoring it")
            return false
        }
        store(picked)
        activate()
        return FileManager.default.isReadableFile(atPath: Self.folder.appending(path: "Assertions.json").path)
    }

    private func store(_ url: URL) {
        let data = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(includingResourceValuesForKeys: nil, relativeTo: nil))
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }
}
