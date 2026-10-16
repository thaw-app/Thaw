//
//  MarkerPairResolver.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Pairs unresolved on-screen menu bar icons with bundle-ID-titled
/// marker windows so their NSStatusItem sourcePIDs can be recovered
/// after the spatial AX pass fails.
///
/// On macOS 26 some widgets (Little Snitch's agent) are hosted by Control
/// Center at the AX layer with no AXExtrasMenuBar, so sourcePID stays nil and
/// the namespace collides with com.apple.controlcenter. Each such widget also
/// publishes a second CG window titled with its bundle ID and the icon's width
/// (heights differ). Lookups are injected so the algorithm stays pure.
nonisolated enum MarkerPairResolver {
    /// A marker window candidate distilled from the items-only list.
    /// Markers carry bundle-ID-shaped titles (titles containing a ".")
    /// and serve as the recovery handle for paired on-screen icons.
    struct Marker: Equatable {
        let windowID: CGWindowID
        let size: CGSize
        let title: String
        /// CG-layer kCGWindowOwnerPID. Preferred PID source when it
        /// resolves to a bundle ID that is not Control Center or Thaw.
        let owningPID: pid_t?
    }

    /// A candidate icon: an on-screen menu bar window with a non-
    /// bundle-ID-shaped title that needs PID resolution.
    struct UnresolvedIcon: Equatable {
        let windowID: CGWindowID
        let title: String?
        let size: CGSize
    }

    /// One successful resolution: which icon resolved to which PID,
    /// via which marker.
    struct Resolution: Equatable {
        let iconWindowID: CGWindowID
        let resolvedPID: pid_t
        let markerWindowID: CGWindowID
        let markerTitle: String
    }

    /// Pairs unresolved icons with same-size marker windows and
    /// resolves each icon to a sourcePID via the marker. The pairing
    /// must be unique in *both* directions: a width matching more than
    /// one marker is ambiguous, and so is a width shared by more than
    /// one unresolved icon. Thaw and Control Center are excluded from
    /// the resolution paths so a marker hosted by either does not
    /// collapse the resolution back to those PIDs.
    ///
    /// Both halves matter: checking only markers let one marker resolve five
    /// icons, stamping CC's Sound and Wi-Fi with a third-party bundle ID. A
    /// wrong PID is worse than none: it renames the item and slips past the
    /// unresolved-sourcePID gates.
    ///
    /// - Parameters:
    ///   - unresolvedIcons: candidate on-screen icons. Icons whose own
    ///     title is bundle-ID-shaped (contains a dot) are skipped so
    ///     two markers cannot pair with each other.
    ///   - markers: bundle-ID-titled marker windows extracted from the
    ///     items-only list. Callers are expected to pre-filter Thaw
    ///     control items and the Thaw self-registration window.
    ///   - thawBundleID: Thaw's own bundle identifier; excluded from
    ///     both resolution paths.
    ///   - ccBundleID: Control Center's bundle identifier; excluded
    ///     from the marker's owning-PID resolution path.
    ///   - pidToBundleID: closure mapping a PID to its bundle ID,
    ///     mirroring NSRunningApplication(processIdentifier:).
    ///   - bundleIDToPID: closure mapping a bundle ID to a running
    ///     app's PID, mirroring NSRunningApplication.
    ///     runningApplications(withBundleIdentifier:).first?.
    ///     processIdentifier.
    /// - Returns: one Resolution per successfully resolved icon.
    static func resolve(
        unresolvedIcons: [UnresolvedIcon],
        markers: [Marker],
        thawBundleID: String,
        ccBundleID: String,
        pidToBundleID: (pid_t) -> String?,
        bundleIDToPID: (String) -> pid_t?
    ) -> [Resolution] {
        // Icons with bundle-ID-shaped titles are markers, not candidates.
        let candidates = unresolvedIcons.filter { icon in
            guard let title = icon.title else { return true }
            return !title.contains(".")
        }

        // When several candidates share a width, none resolve.
        var candidatesPerWidth = [CGFloat: Int]()
        for icon in candidates {
            candidatesPerWidth[icon.size.width, default: 0] += 1
        }

        var result = [Resolution]()
        for icon in candidates {
            guard candidatesPerWidth[icon.size.width] == 1 else { continue }

            // Match by width only: the icon takes the menu bar height (22-30pt)
            // while the marker has a placeholder height (33pt). The two
            // uniqueness checks still prevent misattribution.
            let matching = markers.filter {
                $0.windowID != icon.windowID && $0.size.width == icon.size.width
            }
            guard matching.count == 1, let marker = matching.first else { continue }

            let resolvedPID: pid_t? = {
                if let pid = marker.owningPID,
                   let bundleID = pidToBundleID(pid),
                   bundleID != ccBundleID,
                   bundleID != thawBundleID
                {
                    return pid
                }
                if let pid = bundleIDToPID(marker.title),
                   let bundleID = pidToBundleID(pid),
                   bundleID != ccBundleID,
                   bundleID != thawBundleID
                {
                    return pid
                }
                return nil
            }()

            guard let pid = resolvedPID else { continue }
            result.append(Resolution(
                iconWindowID: icon.windowID,
                resolvedPID: pid,
                markerWindowID: marker.windowID,
                markerTitle: marker.title
            ))
        }
        return result
    }

    /// Extracts marker candidates from raw items-only windows. A
    /// window qualifies as a marker if its title contains a dot
    /// (bundle-identifier shape), is not a Thaw control item, and is
    /// not the Thaw self-registration window.
    static func extractMarkers(
        from windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)],
        thawControlItemPrefix: String,
        thawBundleID: String
    ) -> [Marker] {
        windows.compactMap { window in
            guard let title = window.title, title.contains(".") else { return nil }
            if title.hasPrefix(thawControlItemPrefix) {
                return nil
            }
            if title == thawBundleID {
                return nil
            }
            return Marker(
                windowID: window.windowID,
                size: window.size,
                title: title,
                owningPID: window.owningPID
            )
        }
    }

    /// True when a CG window title has the generic Item-N shape macOS assigns to
    /// Control-Center-hosted items that publish no name of their own (Item-0,
    /// Item-38, ...). Shared by MenuBarItemTag.isControlCenterGenericItem and
    /// isCCHostedGenericSlot so the two can't drift.
    static func isGenericControlCenterTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.wholeMatch(of: /Item-\d+/) != nil
    }

    /// Returns true when a strict 1pt match only confirms Control Center
    /// hosting of a generic Item-N slot. CC's PID would mark it a transient CC
    /// widget that can't be hidden, so it is left for marker-pair.
    ///
    /// On one display the markers may never publish, leaving the item
    /// unresolved for the session; that beats a permanent mislabel. Named CC
    /// items (Clock, WiFi) and widgets with their own extras child are unaffected.
    static func isCCHostedGenericSlot(
        appBundleID: String?,
        windowTitle: String?,
        ccBundleID: String
    ) -> Bool {
        appBundleID == ccBundleID && isGenericControlCenterTitle(windowTitle)
    }
}

/// Decides whether a Control Center-hosted window's title names its owning
/// app. Corroborates SourcePIDCache's loose spatial fallback (AirBuddy ~2pt
/// off, SpamSieve ~8pt) so a nearby unrelated neighbor is never attributed.
nonisolated enum HostedItemOwnership {
    /// Returns the single running bundle identifier a window title names
    /// outright, or `nil`. Case-insensitive.
    ///
    /// Unlike ``titleIndicatesOwner(_:bundleID:)``, exact equality needs no
    /// spatial corroboration, which CC-hosted items can never supply (#854).
    /// Requiring a unique match rules out two processes sharing an identifier.
    static func exactlyNamedOwner(_ title: String?, runningBundleIDs: [String]) -> String? {
        guard let title, !title.isEmpty else { return nil }
        let needle = title.lowercased()
        // A bundle identifier has at least two components; without this a
        // one-word slot title could match a malformed identifier.
        guard needle.split(separator: ".", omittingEmptySubsequences: false).count >= 2 else {
            return nil
        }
        let matches = runningBundleIDs.filter { $0.lowercased() == needle }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    /// Returns true when title and bundleID, as reverse-DNS strings, agree on
    /// at least two leading components and either one is a component-prefix of
    /// the other or their first differing component is a prefix of its
    /// counterpart. Case-insensitive.
    ///
    /// Matches codes.rambo.AirBuddy.Menu to codes.rambo.AirBuddyHelper; rejects
    /// pl.maketheweb.pixelsnap2 vs pl.maketheweb.cleanshotx. A title with no
    /// dots qualifies only as the bundle's final component (BetterTouchTool).
    static func titleIndicatesOwner(_ title: String?, bundleID: String) -> Bool {
        guard let title, !title.isEmpty else { return false }
        let titleParts = title.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        let bundleParts = bundleID.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        // Reject empty components: "" prefixes everything, so "pl.maketheweb."
        // would otherwise match any app from that vendor.
        guard bundleParts.count >= 2,
              titleParts.allSatisfy({ !$0.isEmpty }),
              bundleParts.allSatisfy({ !$0.isEmpty })
        else { return false }

        // A dotless title matches only the final component; a vendor component
        // would hand every widget from that vendor to whichever app came first.
        if titleParts.count == 1, let appComponent = bundleParts.last {
            return titleParts[0] == appComponent
        }

        // Two-component titles are neither a bare name nor reverse-DNS.
        guard titleParts.count >= 3 else { return false }

        let shared = zip(titleParts, bundleParts).prefix { $0 == $1 }.count
        // Require agreement on at least the vendor plus one component so a
        // bare vendor prefix (com.apple, pl.maketheweb) is never enough.
        guard shared >= 2 else { return false }
        // One component array is a full prefix of the other.
        if shared == titleParts.count || shared == bundleParts.count {
            return true
        }
        // Otherwise the first differing component must be a prefix of its
        // counterpart (airbuddy vs airbuddyhelper).
        return titleParts[shared].hasPrefix(bundleParts[shared])
            || bundleParts[shared].hasPrefix(titleParts[shared])
    }
}
