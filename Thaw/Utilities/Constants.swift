//
//  Constants.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// App-specific constants for the main Thaw target.
/// System-framework paths shared with XPC targets live in SharedConstants.
nonisolated enum Constants {
    // swiftlint:disable force_unwrapping

    /// The version string in the app's bundle.
    static let versionString = Bundle.main.versionString!

    /// The build string in the app's bundle.
    static let buildString = Bundle.main.buildString!

    /// The commit the build was stamped with, or "unknown" outside git.
    static let commitString = Bundle.main.object(forInfoDictionaryKey: "GitCommitSHA") as? String ?? "unknown"

    /// Version, build, commit and macOS, one per line, for bug reports and
    /// the About pane's copy button, so both always say the same thing.
    static var buildDescription: String {
        """
        \(displayName) \(versionString) (\(buildString))
        Commit: \(commitString)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }

    /// The user-readable copyright string in the app's bundle.
    static let copyrightString = Bundle.main.copyrightString!

    /// The app's bundle identifier.
    static let bundleIdentifier = Bundle.main.bundleIdentifier!

    /// The app's display name.
    static let displayName = Bundle.main.displayName

    /// Sparkle update checks are available on all supported OS versions.
    ///
    /// macOS 27 preview builds use the alpha channel by default; Stable and
    /// Development remain available when those appcast items apply.
    static var supportsSparkleUpdates: Bool {
        true
    }

    // swiftlint:enable force_unwrapping

    /// The onboarding flow's own version, compared against
    /// Defaults.Key.onboardingVersion to decide whether a returning user is
    /// shown the tour again. Bumped by hand, not derived from versionString,
    /// which changes every patch and would replay the tour after each update.
    /// Upgraders from the original Thaw arrive with hasSeenOnboarding set and
    /// version 0, so version 2 welcomes them once.
    static let currentOnboardingVersion = 2

    // MARK: - Thaw-owned menu bar identity

    /// Whether a bundle identifier belongs to Thaw. The list lives in
    /// ThawMenuBarIdentity so the app and the runtime kit agree.
    static func isThawOwnedBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        ThawMenuBarIdentity.owns(bundleIdentifier: bundleIdentifier)
    }

    /// Tuned values for the macOS 27 MenuBarAgent/assertion implementation.
    /// Keeping them together makes capture and overlay behavior auditable as a
    /// single operating-system compatibility policy.
    enum MenuBarTuning {
        static let imageCaptureObserverDebounceMilliseconds = 200
        /// Inner (leading) breathing room for the split trailing pill on
        /// macOS 27. The AX item frame starts the rounded cap flush with the
        /// glyph border, so without this the leftmost icons are clipped by the
        /// curve; it must clear the cap radius (~half the bar height).
        static let trailingPillLeadingInnerMargin: CGFloat = 7
        /// Outer (trailing) breathing room for the split trailing pill on
        /// macOS 27, the mirror of trailingPillLeadingInnerMargin: the right
        /// rounded cap curves in over the rightmost item, so it must clear the
        /// cap radius.
        static let trailingPillTrailingOuterMargin: CGFloat = 10
        static let syntheticDragDropInset: CGFloat = 2
        static let syntheticDragSettleDelay: Duration = .milliseconds(250)

        // MARK: Startup

        /// Delay before the first post-launch menu bar scan. Gives status items
        /// time to register before the cold-boot cache pass.
        static let startupInitialScanDelay: Duration = .milliseconds(350)
        /// Longer settle for the menu bar hosting process (Control Center /
        /// MenuBarAgent and its BentoBox modules), which attach later than
        /// ordinary app status items.
        static let startupMenuBarHostSettleDelay: Duration = .milliseconds(500)
        /// Interval between startup settling polls.
        static let startupSettlingPollInterval: Duration = .milliseconds(500)

        // MARK: Thaw Bar (macOS 27)

        /// How long to wait after relaxing the visibility assertion for
        /// MenuBarAgent to recomposite a revealed item before clicking it.
        static let thawBarRevealSettle: Duration = .milliseconds(400)
        /// Grace after a click for the item's menu to open before the
        /// status-item glyph is re-concealed.
        static let thawBarPostClickSettle: Duration = .milliseconds(150)
        /// Short render settle after AX bounds stabilize but before the SCK
        /// screenshot, so MenuBarAgent finishes compositing the revealed glyph.
        /// Without this the crop captures a partially-rendered icon.
        static let layoutPrewarmRenderSettle: Duration = .milliseconds(200)
        /// Window after a native menu-bar visibility change during which Thaw
        /// defers its own mutations, letting the system settle the new layout
        /// before Thaw reorders or reveals items on top of it.
        static let nativeMenuBarMutationSettle: Duration = .milliseconds(900)

        /// How long a differing macOS 27 item signature must persist, unchanged,
        /// before the autonomous cache tick treats it as a real layout change.
        /// Enumeration flaps and the fast poll would otherwise confirm a flap on
        /// the second sighting and rewrite the layout, visibly reordering icons.
        static let signatureStabilityGrace: Duration = .seconds(3)

        /// Interval between polls while waiting for MenuBarAgent to relaunch and
        /// re-sort after a preferred-position write (batch reorder or single
        /// move). MenuBarAgent is a managed launch agent that relaunches within
        /// ~1-2 s, so the wait polls at this cadence rather than guessing a
        /// fixed delay.
        static let menuBarAgentResortPollInterval: Duration = .milliseconds(250)

        /// How long a nudged preferred-position write is given to move the bar
        /// before the wait hands the move to the synthetic drag. MenuBarAgent
        /// silently drops most writes, and an honored write starts shifting the
        /// bar within a poll or two. Only the "bar never moved" case bails
        /// early; once it moves, the wait runs to the full deadline.
        static let menuBarAgentBarMovedProbeWindow: Duration = .milliseconds(1200)

        // MARK: Show-on-hover retention

        /// Vertical slack, in points, kept below the menu bar bottom edge while
        /// a section is revealed via show-on-hover, so cursor tremor at the
        /// edge does not start a show, hide, show loop. Smaller than the Thaw
        /// Bar pad: dipping toward app content is more likely intentional.
        static let hoverRetentionPadding: CGFloat = 8
    }

    /// The relative luminance above which the menu bar is considered "bright"
    /// and the items drawn on it switch to dark content. Used for non-notched
    /// displays.
    ///
    /// This is ForegroundContrast.flipLuminance, the point where black
    /// starts contrasting more with the background than white does, and so the
    /// last place the switch can be made without handing one of the two sides
    /// a worse reading than it had to have.
    static let menuBarBrightnessThreshold = ForegroundContrast.flipLuminance

    /// The same threshold for notched displays.
    /// Matches the non-notched threshold to avoid biasing toward dark text on
    /// notched displays where the black notch area lowers the sampled average.
    static let notchedDisplayBrightnessThreshold = ForegroundContrast.flipLuminance

    // MARK: - App URLs (from Info.plist)

    /// Info.plist key used to configure the repository URL.
    static let repositoryURLInfoPlistKey = "ThawRepositoryURL"

    /// Info.plist key used to configure the changelog URL.
    static let changelogURLInfoPlistKey = "ThawChangelogURL"

    /// Info.plist key used to configure the donation URL.
    static let donateURLInfoPlistKey = "ThawDonateURL"

    /// Info.plist key used to configure the community chat URL.
    static let discordURLInfoPlistKey = "ThawDiscordURL"

    /// Info.plist key used to configure the executable URI for
    /// MenuBarItemSpacingManager shell commands.
    static let menuBarItemSpacingExecutableURIInfoPlistKey = "ThawMenuBarItemSpacingExecutableURI"

    /// The project's GitHub repository URL.
    static let repositoryURL: URL = requiredInfoPlistURL(repositoryURLInfoPlistKey)

    /// The changelog document, fetched from the Thaw repository.
    static let changelogURL: URL = requiredInfoPlistURL(changelogURLInfoPlistKey)

    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    static let frequentIssuesURL = repositoryURL.appending(path: "blob/development/FREQUENT_ISSUES.md")
    static let contributorsURL = repositoryURL.appending(path: "graphs/contributors")
    static let translatorsURL = repositoryURL.appending(path: "blob/development/CREDITS.md")

    /// The URL for sponsoring/donating.
    static let donateURL: URL = requiredInfoPlistURL(donateURLInfoPlistKey)

    /// The project's community chat.
    static let discordURL: URL = requiredInfoPlistURL(discordURLInfoPlistKey)

    /// The Crowdin project URL for community translations.
    static let translateURL = URL(string: "https://crowdin.com/project/thaw")!

    /// The Lab discussion category, where users vote on which experiments
    /// should graduate to stable features.
    static let labDiscussionURL = URL(string: "https://github.com/orgs/thaw-app/discussions/categories/the-lab")!

    /// The executable URL used by MenuBarItemSpacingManager.
    static let menuBarItemSpacingExecutableURL: URL = requiredInfoPlistURL(menuBarItemSpacingExecutableURIInfoPlistKey)

    // MARK: - Helpers

    /// Returns a required URL from the bundle's Info.plist.
    private static func requiredInfoPlistURL(_ key: String) -> URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            let url = URL(string: value),
            url.scheme != nil
        else {
            fatalError("Missing or invalid Info.plist URL for key: \(key)")
        }
        return url
    }

    /// The arrow character used in menu path descriptions (→).
    /// Extracted so translators see %@ instead of a unicode arrow.
    static let menuArrow = "\u{2192}"
}
