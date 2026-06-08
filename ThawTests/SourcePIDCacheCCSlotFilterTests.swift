//
//  SourcePIDCacheCCSlotFilterTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Tests for `MarkerPairResolver.isCCHostedGenericSlot`, the guard used by
/// `SourcePIDCache`'s strict AX spatial scan to skip attributing a CC-hosted,
/// generically-titled menu bar window to Control Center's own PID.
///
/// On macOS 26, third-party widgets whose `NSStatusItem` is hosted by Control
/// Center (Little Snitch's agent, WireGuard, etc.) appear in CC's AX extras
/// tree at the exact position of the CG window. Without this guard, the spatial
/// scan would write CC's PID into the cache, tagging the item as a transient CC
/// widget (`isTransientControlCenterItem=true`, `canBeHidden=false`) and hiding
/// it from profile management and `VirtualDisplayProvoker`'s orphan scan. The
/// guard identifies these "anonymous slots" by the combination of CC's bundle ID
/// and a generic `Item-N` window title, leaving them in `unresolvedWindows` so
/// the marker-pair pass can supply the correct owner PID.
final class SourcePIDCacheCCSlotFilterTests: XCTestCase {
    private let ccBundleID = "com.apple.controlcenter"

    // MARK: - True: CC-hosted generic slots

    /// `Item-0` is the canonical slot title observed for Little Snitch on
    /// macOS 26. The guard must trigger and leave the window unresolved so
    /// marker-pair can supply the correct PID.
    func testItemZeroWithCCBundleIDIsGenericSlot() {
        XCTAssertTrue(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "Item-0",
                ccBundleID: ccBundleID
            )
        )
    }

    /// Higher slot indices (`Item-1`, `Item-23`) follow the same pattern.
    func testItemOneWithCCBundleIDIsGenericSlot() {
        XCTAssertTrue(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "Item-1",
                ccBundleID: ccBundleID
            )
        )
    }

    func testLargeItemIndexWithCCBundleIDIsGenericSlot() {
        XCTAssertTrue(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "Item-23",
                ccBundleID: ccBundleID
            )
        )
    }

    // MARK: - False: named CC items (must resolve to CC's PID normally)

    /// CC items with recognisable names (BentoBox-0, Clock, WiFi, NowPlaying,
    /// …) carry non-generic titles and do identify a specific CC widget. The
    /// guard must NOT fire for them; they should resolve to CC's PID as usual.
    func testBentoBoxIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "BentoBox-0",
                ccBundleID: ccBundleID
            )
        )
    }

    func testClockIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "Clock",
                ccBundleID: ccBundleID
            )
        )
    }

    func testWiFiIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "WiFi",
                ccBundleID: ccBundleID
            )
        )
    }

    func testNowPlayingIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "NowPlaying",
                ccBundleID: ccBundleID
            )
        )
    }

    /// `Item-` without digits does not match `/Item-\d+/` and must not be
    /// treated as a generic slot.
    func testItemWithoutDigitsIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: "Item-",
                ccBundleID: ccBundleID
            )
        )
    }

    // MARK: - False: non-CC matched app

    /// When the spatial match finds a third-party app's AX child (not CC),
    /// the window should be attributed to that app regardless of the window
    /// title. `Item-0` from a non-CC app is just a coincidentally named window.
    func testThirdPartyAppWithItemTitleIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: "at.obdev.littlesnitch.agent",
                windowTitle: "Item-0",
                ccBundleID: ccBundleID
            )
        )
    }

    func testThawBundleIDWithItemTitleIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: "com.stonerl.Thaw",
                windowTitle: "Item-0",
                ccBundleID: ccBundleID
            )
        )
    }

    // MARK: - False: nil / missing values

    /// A nil bundle ID means the matched app has no known bundle; it cannot
    /// be CC, so the guard must not fire.
    func testNilBundleIDIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: nil,
                windowTitle: "Item-0",
                ccBundleID: ccBundleID
            )
        )
    }

    /// A nil window title cannot match the regex; must return false even when
    /// the bundle ID is CC.
    func testCCBundleIDWithNilTitleIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: ccBundleID,
                windowTitle: nil,
                ccBundleID: ccBundleID
            )
        )
    }

    /// Both nil: trivially false.
    func testBothNilIsNotGenericSlot() {
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(
                matchedBundleID: nil,
                windowTitle: nil,
                ccBundleID: ccBundleID
            )
        )
    }
}
