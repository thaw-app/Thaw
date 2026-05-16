//
//  MarkerPairResolverTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for MarkerPairResolver, the helper that
/// pairs unresolved on-screen icons with bundle-ID-titled marker
/// windows and resolves them to a sourcePID via injected lookups.
///
/// Covers the macOS 26 marker-pair workflow used by SourcePIDCache
/// when the spatial AX pass cannot reach a widget's own
/// AXExtrasMenuBar.
final class MarkerPairResolverTests: XCTestCase {
    // MARK: - Constants

    private let thawBundleID = "com.stonerl.Thaw"
    private let ccBundleID = "com.apple.controlcenter"
    private let thawControlItemPrefix = "Thaw.ControlItem."

    // MARK: - Helpers

    private func icon(
        windowID: CGWindowID,
        title: String?,
        size: CGSize = CGSize(width: 116, height: 33)
    ) -> MarkerPairResolver.UnresolvedIcon {
        MarkerPairResolver.UnresolvedIcon(windowID: windowID, title: title, size: size)
    }

    private func marker(
        windowID: CGWindowID,
        title: String,
        size: CGSize = CGSize(width: 116, height: 33),
        owningPID: pid_t? = nil
    ) -> MarkerPairResolver.Marker {
        MarkerPairResolver.Marker(
            windowID: windowID,
            size: size,
            title: title,
            owningPID: owningPID
        )
    }

    /// Always-fails lookups, used by tests where neither path should
    /// resolve.
    private let neverResolve: (pid_t) -> String? = { _ in nil }
    private let neverResolveByBundle: (String) -> pid_t? = { _ in nil }

    // MARK: - Resolve

    /// The canonical observed shape: one unresolved icon with a
    /// generic "Item-0" title, one same-size marker with the agent
    /// bundle identifier as title, and the bundle-ID-to-PID lookup
    /// returning the agent's PID. The icon resolves via the title-
    /// lookup path because the marker's CG owner is Control Center
    /// (the macOS 26 reparenting case).
    func testAgentSceneResolvesViaTitleLookup() {
        let icons = [icon(windowID: 11_379, title: "Item-0")]
        let markers = [
            marker(
                windowID: 61_456,
                title: "at.obdev.littlesnitch.agent",
                owningPID: 39_187 // Control Center
            ),
        ]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 39_187 { return self.ccBundleID }
                if pid == 13_496 { return "at.obdev.littlesnitch.agent" }
                return nil
            },
            bundleIDToPID: { bundleID in
                bundleID == "at.obdev.littlesnitch.agent" ? 13_496 : nil
            }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.iconWindowID, 11_379)
        XCTAssertEqual(result.first?.resolvedPID, 13_496)
        XCTAssertEqual(result.first?.markerWindowID, 61_456)
        XCTAssertEqual(result.first?.markerTitle, "at.obdev.littlesnitch.agent")
    }

    /// Marker's CG owner is the widget's real app (not CC, not Thaw):
    /// the owning-PID path resolves directly without falling through
    /// to the title lookup. The bundleIDToPID closure must NOT be
    /// invoked in this case.
    func testOwningPIDPathPreferredOverTitleLookup() {
        var bundleLookupCalled = false
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 555)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                pid == 555 ? "com.example.widget" : nil
            },
            bundleIDToPID: { _ in
                bundleLookupCalled = true
                return nil
            }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.resolvedPID, 555)
        XCTAssertFalse(bundleLookupCalled,
                       "title-lookup path must not run when owning-PID path succeeds")
    }

    /// Marker's CG owner resolves to Control Center: the owning-PID
    /// path is rejected and the title lookup runs.
    func testCCOwnerFallsThroughToTitleLookup() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 200)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 200 { return self.ccBundleID }
                if pid == 777 { return "com.example.widget" }
                return nil
            },
            bundleIDToPID: { bundleID in
                bundleID == "com.example.widget" ? 777 : nil
            }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.resolvedPID, 777)
    }

    /// Marker's CG owner resolves to Thaw itself: rejected, falls
    /// through to title lookup. The title-lookup result must also
    /// be checked for Thaw self-attribution (see the next test).
    func testThawOwnerFallsThroughToTitleLookup() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 100)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 100 { return self.thawBundleID }
                if pid == 777 { return "com.example.widget" }
                return nil
            },
            bundleIDToPID: { bundleID in
                bundleID == "com.example.widget" ? 777 : nil
            }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.resolvedPID, 777)
    }

    /// Both paths resolve to Thaw: no resolution emitted. Defensive
    /// guarantee that Thaw's own PID is never attributed to a
    /// third-party widget regardless of where the lookup happens to
    /// land.
    func testBothPathsResolveToThawProducesNoResult() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 100)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in self.thawBundleID },
            bundleIDToPID: { _ in 100 }
        )
        XCTAssertEqual(result, [])
    }

    /// Two unresolved icons share the same size and there are two
    /// markers of that size: the ambiguity is unresolvable, so no
    /// pairings emit. Prevents the cross-attribution where an icon
    /// gets paired with the wrong marker.
    func testMultiMatchSkipped() {
        let icons = [
            icon(windowID: 1, title: "Item-0"),
            icon(windowID: 2, title: "Item-0"),
        ]
        let markers = [
            marker(windowID: 10, title: "com.a.app", owningPID: 100),
            marker(windowID: 11, title: "com.b.app", owningPID: 200),
        ]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 100 { return "com.a.app" }
                if pid == 200 { return "com.b.app" }
                return nil
            },
            bundleIDToPID: { _ in nil }
        )
        XCTAssertEqual(result, [])
    }

    /// Icon whose own title is bundle-ID-shaped is not a candidate:
    /// it's a marker, not an icon. This prevents two markers from
    /// pairing with each other. The generic-titled icon resolves
    /// normally; the bundle-ID-titled "icon" is silently skipped.
    func testBundleIDShapedIconTitleIsSkipped() {
        // Two unrelated widgets at different sizes so neither
        // multi-matches; both have a generic-titled candidate icon
        // in the unresolved set, plus the bundle-ID-shaped "icon"
        // entry that the helper should skip.
        let icons = [
            icon(
                windowID: 1,
                title: "com.example.widget", // bundle-ID-shaped, should be skipped
                size: CGSize(width: 40, height: 33)
            ),
            icon(
                windowID: 2,
                title: "Item-0",
                size: CGSize(width: 116, height: 33)
            ),
        ]
        let markers = [
            // Same-size marker for windowID 1, but the icon itself
            // is filtered out by the bundle-ID-title check, so this
            // marker has nothing to pair with anyway.
            marker(
                windowID: 100,
                title: "com.example.widget",
                size: CGSize(width: 40, height: 33),
                owningPID: 100
            ),
            // Same-size marker for windowID 2.
            marker(
                windowID: 200,
                title: "com.another.widget",
                size: CGSize(width: 116, height: 33),
                owningPID: 200
            ),
        ]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 100 { return "com.example.widget" }
                if pid == 200 { return "com.another.widget" }
                return nil
            },
            bundleIDToPID: { bundleID in
                if bundleID == "com.example.widget" { return 100 }
                if bundleID == "com.another.widget" { return 200 }
                return nil
            }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.iconWindowID, 2,
                       "only the generic-titled icon should resolve; bundle-ID-titled icons are markers, not candidates")
    }

    /// Marker's windowID equals the icon's windowID (self-pair): the
    /// `windowID != icon.windowID` filter rejects self-pairings even
    /// though the size matches.
    func testSelfPairingRejected() {
        // Same windowID for icon and marker — pathological input that
        // shouldn't occur, but the filter must hold.
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 1, title: "com.example.widget", owningPID: 100)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in "com.example.widget" },
            bundleIDToPID: { _ in 100 }
        )
        XCTAssertEqual(result, [])
    }

    /// Size mismatch: no pairing. The marker's width differs from the
    /// icon's by 1 point, so they should not be considered the same
    /// widget.
    func testSizeMismatchProducesNoResult() {
        let icons = [icon(windowID: 1, title: "Item-0", size: CGSize(width: 116, height: 33))]
        let markers = [marker(
            windowID: 2,
            title: "com.example.widget",
            size: CGSize(width: 117, height: 33),
            owningPID: 100
        )]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in "com.example.widget" },
            bundleIDToPID: { _ in 100 }
        )
        XCTAssertEqual(result, [])
    }

    /// Neither owning-PID nor title-lookup resolves: no result. The
    /// algorithm bails cleanly when no resolution path succeeds.
    func testNeitherPathResolvesProducesNoResult() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: nil)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: neverResolve,
            bundleIDToPID: neverResolveByBundle
        )
        XCTAssertEqual(result, [])
    }

    /// Empty inputs: empty output. Trivial guard.
    func testEmptyInputsProduceEmptyOutput() {
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: [],
            markers: [],
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: neverResolve,
            bundleIDToPID: neverResolveByBundle
        )
        XCTAssertEqual(result, [])
    }

    // MARK: - extractMarkers

    /// Non-dot titles are filtered out as non-markers.
    func testExtractMarkersExcludesGenericTitles() {
        let windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)] = [
            (1, "Item-0", CGSize(width: 116, height: 33), nil), // generic title
            (2, "", CGSize(width: 42, height: 33), nil), // empty
            (3, nil, CGSize(width: 22, height: 22), nil), // nil
            (4, "com.example.widget", CGSize(width: 116, height: 33), 100), // valid marker
        ]
        let markers = MarkerPairResolver.extractMarkers(
            from: windows,
            thawControlItemPrefix: thawControlItemPrefix,
            thawBundleID: thawBundleID
        )
        XCTAssertEqual(markers.map(\.windowID), [4])
    }

    /// Thaw control items are excluded by the Thaw.ControlItem.
    /// prefix even though their titles contain dots.
    func testExtractMarkersExcludesThawControlItems() {
        let windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)] = [
            (1, "Thaw.ControlItem.Hidden", CGSize(width: 5016, height: 33), nil),
            (2, "Thaw.ControlItem.AlwaysHidden", CGSize(width: 5016, height: 33), nil),
            (3, "com.example.widget", CGSize(width: 24, height: 24), nil),
        ]
        let markers = MarkerPairResolver.extractMarkers(
            from: windows,
            thawControlItemPrefix: thawControlItemPrefix,
            thawBundleID: thawBundleID
        )
        XCTAssertEqual(markers.map(\.windowID), [3])
    }

    /// The Thaw self-registration window (title equals the Thaw bundle
    /// identifier) is excluded so Thaw's own PID can never be
    /// attributed to a third-party widget via the title-lookup path.
    func testExtractMarkersExcludesThawSelfRegistration() {
        let windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)] = [
            (1, "com.stonerl.Thaw", CGSize(width: 33, height: 33), nil), // Thaw self
            (2, "com.example.widget", CGSize(width: 24, height: 24), nil),
        ]
        let markers = MarkerPairResolver.extractMarkers(
            from: windows,
            thawControlItemPrefix: thawControlItemPrefix,
            thawBundleID: thawBundleID
        )
        XCTAssertEqual(markers.map(\.windowID), [2])
    }
}
