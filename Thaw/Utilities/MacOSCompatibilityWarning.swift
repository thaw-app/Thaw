//
//  MacOSCompatibilityWarning.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

enum MacOSCompatibilityWarning {
    /// The first macOS this build does not support, and the one the rewrite
    /// on ``UpdateChannel/alpha`` is built against.
    ///
    /// The two readings are the same number for the same reason: the alert
    /// below tells the user that support for this release arrives through the
    /// alpha channel, so the version that triggers the warning has to be the
    /// version that makes that channel selectable.
    static nonisolated let firstUnsupportedMajorVersion = 27

    static nonisolated func shouldShow(for version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= firstUnsupportedMajorVersion
    }

    /// Warns about the running macOS and offers the channel that supports it.
    ///
    /// The offer is made only when `updatesManager` can act on it and the
    /// running system can actually be given the alpha channel. Both readings
    /// come from ``firstUnsupportedMajorVersion``, so the offer stands
    /// whenever the alert appears; the check is what keeps the alert honest
    /// if the two ever part. Without it, the user is sent to the releases
    /// page to pick a build by hand.
    @MainActor
    static func showIfNeeded(updatesManager: UpdatesManager?) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard shouldShow(for: version) else { return }

        let subscriber = UpdateChannel.alpha.isAvailable(on: version) ? updatesManager : nil

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "macOS 27 Is Not Yet Supported")
        if subscriber != nil {
            alert.informativeText = String(
                localized: """
                This version of Thaw is not yet compatible with macOS 27. Support arrives through the alpha channel, which carries the rewritten app. Thaw can subscribe you and check for a build now. If none has been published yet, it opens the preview builds on GitHub.
                """
            )
            alert.addButton(withTitle: String(localized: "Switch to Alpha Updates"))
        } else {
            alert.informativeText = String(
                localized: """
                This version of Thaw is not yet compatible with macOS 27. Preview builds are available on GitHub Releases, and macOS 27 support will be delivered through the alpha update channel.
                """
            )
            alert.addButton(withTitle: String(localized: "View Preview Builds"))
        }
        alert.addButton(withTitle: String(localized: "Continue"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let subscriber {
            subscriber.checkForAlphaUpdateAfterCompatibilityWarning()
        } else {
            NSWorkspace.shared.open(Constants.releasesURL)
        }
    }
}
