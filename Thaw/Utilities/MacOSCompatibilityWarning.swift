//
//  MacOSCompatibilityWarning.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

enum MacOSCompatibilityWarning {
    /// The first macOS this build doesn't support, and the one the rewrite
    /// targets. On it, ``UpdateChannel/beta`` also takes the rewrite's alpha
    /// builds, so the channel the alert switches to always reaches one.
    static nonisolated let firstUnsupportedMajorVersion = 27

    static nonisolated func shouldShow(for version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= firstUnsupportedMajorVersion
    }

    /// What the alert's default button does.
    nonisolated enum Action: Equatable {
        /// Subscribe to the beta channel and check for the build it carries.
        case subscribeToBeta
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

    /// The prompt for a system, or `nil` when it's supported.
    ///
    /// `canSubscribe` says whether an updates manager reached the call. The copy
    /// names the running macOS, since the warning fires on every release from the
    /// unsupported one onward.
    static nonisolated func prompt(
        for version: OperatingSystemVersion,
        canSubscribe: Bool
    ) -> Prompt? {
        guard shouldShow(for: version) else {
            return nil
        }

        let release = version.majorVersion
        let title = String(localized: "macOS \(release) Is Not Yet Supported")

        guard canSubscribe else {
            return Prompt(
                title: title,
                message: String(
                    localized: """
                    This version of Thaw is not yet compatible with macOS \(release). Support is coming through the alpha and beta update channels, and preview builds are available on GitHub Releases.
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
                This version of Thaw is not yet compatible with macOS \(release). Support is coming through the alpha and beta update channels, which carry the rewritten app. Thaw can switch you to beta updates and check for a build now. If none has been published yet, it opens the preview builds on GitHub.
                """
            ),
            confirmButtonTitle: String(localized: "Switch to Beta Updates"),
            action: .subscribeToBeta
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
        case .subscribeToBeta:
            updatesManager?.checkForBetaUpdateAfterCompatibilityWarning()
        case .openReleasesPage:
            NSWorkspace.shared.open(Constants.releasesURL)
        }
    }
}
