//
//  Constants.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// App-specific constants for the main Thaw target.
/// System-framework paths shared with XPC targets live in `SharedConstants`.
public enum Constants {
    /// The version string in the app's bundle.
    public static let versionString = Bundle.main.versionString ?? "0.0.0"

    /// The build string in the app's bundle.
    public static let buildString = Bundle.main.buildString ?? "0"

    /// The user-readable copyright string in the app's bundle.
    public static let copyrightString = Bundle.main.copyrightString ?? "Copyright © 2026 Thaw App"

    /// The app's bundle identifier.
    public static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.stonerl.Thaw"

    /// The app's display name.
    public static let displayName = Bundle.main.displayName

    /// Sparkle update checks are available on all supported OS versions.
    ///
    /// macOS 27 preview builds default to the `alpha` channel in the app.
    public static var supportsSparkleUpdates: Bool {
        true
    }

    /// Label for the macOS 27 preview build shown in About.
    public static let macOS27PreviewName = "macOS 27 Preview 5"

    // MARK: - Thaw-owned menu bar identity

    /// Bundle identifiers that can own Thaw's menu bar control surface.
    ///
    /// macOS 27 normally reports the live icon as `com.stonerl.Thaw`, but some
    /// AX/defaults paths have exposed it through a MenuBarHost-style owner. Keep
    /// both protected so hiding another app can never remove Thaw's recovery UI.
    public static var thawOwnedBundleIdentifiers: Set<String> {
        [
            bundleIdentifier,
            "\(bundleIdentifier).MenuBarHost",
        ]
    }

    public static func isThawOwnedBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return thawOwnedBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func isThawOwnedAssignmentIdentifier(_ identifier: String) -> Bool {
        if identifier.hasPrefix("Thaw.ControlItem.") {
            return true
        }

        return thawOwnedBundleIdentifiers.contains { bundleIdentifier in
            identifier == bundleIdentifier ||
                identifier.hasPrefix("\(bundleIdentifier):")
        }
    }

    /// Tuned values for the macOS 27 MenuBarAgent/assertion implementation.
    /// Keeping them together makes capture and overlay behavior auditable as a
    /// single operating-system compatibility policy.
    public enum MenuBarTuning {
        public static let imageCaptureObserverDebounceMilliseconds = 200
        public static let minimumLiveImageRefreshInterval: TimeInterval = 1
        /// Inner (leading) breathing room for the split trailing pill on
        /// macOS 27. The AX item frame starts the rounded cap flush with the
        /// inner glyph's border, so without this the leftmost icons (e.g.
        /// Proton, Sound) are clipped by the curve. Must clear the rounded cap
        /// radius (~half the menu-bar height, ≈11 pt) plus visible breathing
        /// room, so it sits well past the legacy 7 pt CGS outset.
        public static let trailingPillLeadingInnerMargin: CGFloat = 7
        /// Outer (trailing) breathing room for the split trailing pill on
        /// macOS 27 — the mirror of ``trailingPillLeadingInnerMargin``. The right
        /// rounded cap (radius ≈ half the menu-bar height) curves in over the
        /// rightmost item (the Clock) at the legacy 7 pt outset, so the pill
        /// looks like it stops short of covering it. Clear the cap radius.
        public static let trailingPillTrailingOuterMargin: CGFloat = 10
        public static let syntheticDragDropInset: CGFloat = 2
        public static let syntheticDragSettleDelay: Duration = .milliseconds(250)

        // MARK: Startup

        /// Delay before the first post-launch menu bar scan. Gives status items
        /// time to register before the cold-boot cache pass.
        public static let startupInitialScanDelay: Duration = .milliseconds(350)
        /// Longer settle for the menu bar hosting process (Control Center /
        /// MenuBarAgent and its BentoBox modules), which attach later than
        /// ordinary app status items.
        public static let startupMenuBarHostSettleDelay: Duration = .milliseconds(500)
        /// Interval between startup settling polls.
        public static let startupSettlingPollInterval: Duration = .milliseconds(500)

        // MARK: Thaw Bar (macOS 27)

        /// How long to wait after relaxing the visibility assertion for
        /// MenuBarAgent to recomposite a revealed item before clicking it.
        public static let iceBarRevealSettle: Duration = .milliseconds(400)
        /// Grace after a click for the item's menu to open before the
        /// status-item glyph is re-concealed.
        public static let iceBarPostClickSettle: Duration = .milliseconds(150)
        /// Settle before capturing the glyphs of a freshly-revealed section.
        public static let iceBarCaptureSettle: Duration = .milliseconds(350)
        /// Slower layout-only prewarm; MenuBarAgent can publish partial AX
        /// bounds before the revealed glyph has finished recompositing.
        public static let layoutPrewarmCaptureSettle: Duration = .milliseconds(800)
        /// Short render settle after AX bounds stabilize but before the SCK
        /// screenshot, so MenuBarAgent finishes compositing the revealed glyph.
        /// Without this the crop captures a partially-rendered icon.
        public static let layoutPrewarmRenderSettle: Duration = .milliseconds(200)

        /// Interval between polls while waiting for MenuBarAgent to relaunch and
        /// re-sort after a preferred-position write (batch reorder or single
        /// move). MenuBarAgent is a managed launch agent that relaunches within
        /// ~1-2 s, so the wait polls at this cadence rather than guessing a
        /// fixed delay.
        public static let menuBarAgentResortPollInterval: Duration = .milliseconds(250)
        /// Maximum polls (≈3 s at ``menuBarAgentResortPollInterval``) to wait for
        /// MenuBarAgent's re-sort to satisfy the desired layout before the caller
        /// reads current geometry and moves on.
        public static let menuBarAgentResortMaxPolls = 12

        // MARK: Show-on-hover retention

        /// Vertical slack, in points, kept below the menu bar bottom edge while
        /// a section is revealed via show-on-hover. Without this, the hide arm
        /// of `handleShowOnHover` runs against a 1-pixel-precise
        /// `isMouseInsideMenuBar` boundary, so cursor micro-tremor at the edge
        /// of an inline (non-Thaw Bar) reveal schedules a hide that survives
        /// `rehideInterval`, fires `hide()`, and re-arms `showOnHoverAllowed`
        /// — restarting the show→hide→show loop. The band absorbs that tremor
        /// the same way `isMouseInsideIceBar`'s 15 pt pad and
        /// `isMouseNearMenuBar`'s 80 pt pad already do elsewhere. Kept smaller
        /// than the Thaw Bar pad because dipping below the menu bar toward app
        /// content is more likely to be intentional than dipping off the
        /// floating Thaw Bar popover.
        public static let hoverRetentionPadding: CGFloat = 8
    }

    /// The brightness threshold above which the menu bar is considered "bright".
    /// When the menu bar brightness exceeds this value, items should use dark colors.
    /// Used for non-notched displays.
    public static let menuBarBrightnessThreshold: CGFloat = 0.67

    /// The brightness threshold for notched displays.
    /// Matches the non-notched threshold to avoid biasing toward dark text on
    /// notched displays where the black notch area lowers the sampled average.
    public static let notchedDisplayBrightnessThreshold: CGFloat = 0.67

    // MARK: - App URLs (from Info.plist)

    /// Info.plist key used to configure the repository URL.
    public static let repositoryURLInfoPlistKey = "ThawRepositoryURL"

    /// Info.plist key used to configure the donation URL.
    public static let donateURLInfoPlistKey = "ThawDonateURL"

    /// Info.plist key used to configure the executable URI for
    /// `MenuBarItemSpacingManager` shell commands.
    public static let menuBarItemSpacingExecutableURIInfoPlistKey = "ThawMenuBarItemSpacingExecutableURI"

    /// The project's GitHub repository URL.
    public static let repositoryURL: URL = requiredInfoPlistURL(repositoryURLInfoPlistKey)

    /// The URL for filing issues.
    public static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The URL for sponsoring/donating.
    public static let donateURL: URL = requiredInfoPlistURL(donateURLInfoPlistKey)

    /// The executable URL used by `MenuBarItemSpacingManager`.
    public static let menuBarItemSpacingExecutableURL: URL = requiredInfoPlistURL(menuBarItemSpacingExecutableURIInfoPlistKey)

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
    public static let menuArrow = "\u{2192}"
}
