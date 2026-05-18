//
//  MarkerPairResolver.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Pairs unresolved on-screen menu bar icons with bundle-ID-titled
/// marker windows so their NSStatusItem sourcePIDs can be recovered
/// after the spatial AX pass fails.
///
/// On macOS 26 some widgets (Little Snitch's agent observed in the
/// wild) have their NSStatusItem hosted by Control Center at the AX
/// layer and do not publish an AXExtrasMenuBar of their own. The
/// CG-to-AX spatial resolver in SourcePIDCache cannot find a per-app
/// extras child for them, sourcePID stays nil, and the namespace
/// falls back to com.apple.controlcenter, colliding with Apple's real
/// Control Center items and with any other widget hit by the same
/// failure.
///
/// Structurally, every NSStatusItem-style widget also publishes a
/// SECOND CG window in the items-only list whose title is the
/// widget's bundle identifier and whose width matches the on-screen
/// icon (heights diverge: the icon takes the active display's menu
/// bar height while the marker carries a placeholder height). This
/// resolver pairs icons with markers by width and synthesizes the
/// sourcePID via injected lookups so the algorithm stays pure and
/// testable.
enum MarkerPairResolver {
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
    /// resolves each icon to a sourcePID via the marker. Multi-match
    /// cases (two unresolved icons sharing a size with two markers)
    /// are skipped to prevent misattribution. Thaw and Control Center
    /// are excluded from the resolution paths so a marker hosted by
    /// either does not collapse the resolution back to those PIDs.
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
        var result = [Resolution]()
        for icon in unresolvedIcons {
            if let title = icon.title, title.contains(".") { continue }

            // Match by width only, not exact size. The on-screen icon
            // and its off-screen marker share width (the widget's
            // intrinsic icon width), but heights differ: the icon
            // takes the active display's menu bar height (typically
            // 22-30pt depending on the display and notch state) while
            // the marker carries a default placeholder height
            // (33pt observed in field logs). Exact size matching
            // rejected legitimate pairs whose widths agreed but whose
            // heights drifted by 3pt. The uniqueness check on
            // matching.count == 1 still prevents misattribution when
            // multiple markers happen to share a width.
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
            if title.hasPrefix(thawControlItemPrefix) { return nil }
            if title == thawBundleID { return nil }
            return Marker(
                windowID: window.windowID,
                size: window.size,
                title: title,
                owningPID: window.owningPID
            )
        }
    }
}
