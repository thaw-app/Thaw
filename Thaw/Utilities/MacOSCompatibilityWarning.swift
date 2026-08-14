//
//  MacOSCompatibilityWarning.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

enum MacOSCompatibilityWarning {
    static nonisolated func shouldShow(for version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= 27
    }

    @MainActor
    static func showIfNeeded() {
        guard shouldShow(for: ProcessInfo.processInfo.operatingSystemVersion) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "macOS 27 Is Not Yet Supported")
        alert.informativeText = String(
            localized: """
            This version of Thaw is not yet compatible with macOS 27. Preview builds are available on GitHub Releases, and macOS 27 support will be delivered through the alpha update channel.
            """
        )
        alert.addButton(withTitle: String(localized: "View Preview Builds"))
        alert.addButton(withTitle: String(localized: "Continue"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Constants.releasesURL)
        }
    }
}
