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

    /// What the alert's default button does.
    nonisolated enum Action: Equatable {
        /// Subscribe to the alpha channel and check for the build it carries.
        case subscribeToAlpha
        /// Open the releases page so the user can pick a build by hand.
        case openReleasesPage
    }

    /// The alert an unsupported system is owed: what it says, and what its
    /// default button does.
    nonisolated struct Prompt: Equatable {
        let title: String
        let message: String
        let confirmButtonTitle: String
        let action: Action
    }

    /// The prompt for a system, or `nil` when the system is supported and no
    /// alert is due.
    ///
    /// The alpha offer needs somewhere to send the subscription, so
    /// `canSubscribe` reports whether an updates manager reached the call.
    /// Alpha availability is checked against the running system rather than
    /// assumed: the alert must not offer a channel it cannot select. Both
    /// readings come from ``firstUnsupportedMajorVersion``, so the offer
    /// stands whenever the alert appears; the check is what keeps the alert
    /// honest if the two ever part.
    ///
    /// The warning fires on every release from the unsupported one onward, so
    /// the copy names the macOS actually running rather than the first one
    /// this build turned away.
    static nonisolated func prompt(
        for version: OperatingSystemVersion,
        canSubscribe: Bool
    ) -> Prompt? {
        guard shouldShow(for: version) else {
            return nil
        }

        let release = version.majorVersion
        let title = String(localized: "macOS \(release) Is Not Yet Supported")

        guard canSubscribe, UpdateChannel.alpha.isAvailable(on: version) else {
            return Prompt(
                title: title,
                message: String(
                    localized: """
                    This version of Thaw is not yet compatible with macOS \(release). Preview builds are available on GitHub Releases, and support will be delivered through the alpha update channel.
                    """
                ),
                confirmButtonTitle: String(localized: "View Preview Builds"),
                action: .openReleasesPage
            )
        }

        return Prompt(
            title: title,
            message: String(
                localized: """
                This version of Thaw is not yet compatible with macOS \(release). Support arrives through the alpha channel, which carries the rewritten app. Thaw can subscribe you and check for a build now. If none has been published yet, it opens the preview builds on GitHub.
                """
            ),
            confirmButtonTitle: String(localized: "Switch to Alpha Updates"),
            action: .subscribeToAlpha
        )
    }

    /// Warns about the running macOS and offers the channel that supports it.
    @MainActor
    static func showIfNeeded(updatesManager: UpdatesManager?) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard let prompt = prompt(for: version, canSubscribe: updatesManager != nil) else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.addButton(withTitle: prompt.confirmButtonTitle)
        alert.addButton(withTitle: String(localized: "Continue"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        switch prompt.action {
        case .subscribeToAlpha:
            updatesManager?.checkForAlphaUpdateAfterCompatibilityWarning()
        case .openReleasesPage:
            NSWorkspace.shared.open(Constants.releasesURL)
        }
    }
}
