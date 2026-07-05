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
enum Constants {
    // swiftlint:disable force_unwrapping

    /// The version string in the app's bundle.
    static let versionString = Bundle.main.versionString!

    /// The build string in the app's bundle.
    static let buildString = Bundle.main.buildString!

    /// The user-readable copyright string in the app's bundle.
    static let copyrightString = Bundle.main.copyrightString!

    /// The app's bundle identifier.
    static let bundleIdentifier = Bundle.main.bundleIdentifier!

    /// The app's display name.
    static let displayName = Bundle.main.displayName

    /// Sparkle update checks are disabled on the macOS 27 preview build.
    static var supportsSparkleUpdates: Bool {
        if #available(macOS 27, *) {
            return false
        }
        return true
    }

    /// Label for the macOS 27 preview build shown in About.
    static let macOS27PreviewName = "macOS 27 Preview 5"

    // swiftlint:enable force_unwrapping

    // MARK: - Thaw-owned menu bar identity

    /// Bundle identifiers that can own Thaw's menu bar control surface.
    ///
    /// macOS 27 normally reports the live icon as `com.stonerl.Thaw`, but some
    /// AX/defaults paths have exposed it through a MenuBarHost-style owner. Keep
    /// both protected so hiding another app can never remove Thaw's recovery UI.
    static var thawOwnedBundleIdentifiers: Set<String> {
        [
            bundleIdentifier,
            "\(bundleIdentifier).MenuBarHost",
        ]
    }

    static func isThawOwnedBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return thawOwnedBundleIdentifiers.contains(bundleIdentifier)
    }

    static func isThawOwnedAssignmentIdentifier(_ identifier: String) -> Bool {
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
    enum MenuBarTuning {
        static let imageCaptureObserverDebounceMilliseconds = 200
        static let minimumLiveImageRefreshInterval: TimeInterval = 1
        /// Inner (leading) breathing room for the split trailing pill on
        /// macOS 27. The AX item frame starts the rounded cap flush with the
        /// inner glyph's border, so without this the leftmost icons (e.g.
        /// Proton, Sound) are clipped by the curve. Must clear the rounded cap
        /// radius (~half the menu-bar height, ≈11 pt) plus visible breathing
        /// room, so it sits well past the legacy 7 pt CGS outset.
        static let trailingPillLeadingInnerMargin: CGFloat = 7
        /// Outer (trailing) breathing room for the split trailing pill on
        /// macOS 27 — the mirror of ``trailingPillLeadingInnerMargin``. The right
        /// rounded cap (radius ≈ half the menu-bar height) curves in over the
        /// rightmost item (the Clock) at the legacy 7 pt outset, so the pill
        /// looks like it stops short of covering it. Clear the cap radius.
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
        static let iceBarRevealSettle: Duration = .milliseconds(400)
        /// Grace after a click for the item's menu to open before the
        /// status-item glyph is re-concealed.
        static let iceBarPostClickSettle: Duration = .milliseconds(150)
        /// Settle before capturing the glyphs of a freshly-revealed section.
        static let iceBarCaptureSettle: Duration = .milliseconds(350)
        /// Slower layout-only prewarm; MenuBarAgent can publish partial AX
        /// bounds before the revealed glyph has finished recompositing.
        static let layoutPrewarmCaptureSettle: Duration = .milliseconds(800)

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
        static let hoverRetentionPadding: CGFloat = 8
    }

    /// The brightness threshold above which the menu bar is considered "bright".
    /// When the menu bar brightness exceeds this value, items should use dark colors.
    /// Used for non-notched displays.
    static let menuBarBrightnessThreshold: CGFloat = 0.67

    /// The brightness threshold for notched displays.
    /// Matches the non-notched threshold to avoid biasing toward dark text on
    /// notched displays where the black notch area lowers the sampled average.
    static let notchedDisplayBrightnessThreshold: CGFloat = 0.67

    // MARK: - App URLs (from Info.plist)

    /// Info.plist key used to configure the repository URL.
    static let repositoryURLInfoPlistKey = "ThawRepositoryURL"

    /// Info.plist key used to configure the donation URL.
    static let donateURLInfoPlistKey = "ThawDonateURL"

    /// Info.plist key used to configure the executable URI for
    /// `MenuBarItemSpacingManager` shell commands.
    static let menuBarItemSpacingExecutableURIInfoPlistKey = "ThawMenuBarItemSpacingExecutableURI"

    /// The project's GitHub repository URL.
    static let repositoryURL: URL = requiredInfoPlistURL(repositoryURLInfoPlistKey)

    /// The URL for filing issues.
    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The URL for sponsoring/donating.
    static let donateURL: URL = requiredInfoPlistURL(donateURLInfoPlistKey)

    /// The executable URL used by `MenuBarItemSpacingManager`.
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
