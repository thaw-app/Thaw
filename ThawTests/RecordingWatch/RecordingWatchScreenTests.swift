//
//  RecordingWatchScreenTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The recording watch's announcement-target rules: the storage round trip
/// and the pure resolution that decides which display a banner lands on.
/// The caller reads the live screen list; everything decided here is value
/// math, see RecordingWatchScreen.
@Suite("Recording watch announcement screen")
struct RecordingWatchScreenTests {
    private static let primary: (uuid: String, displayID: CGDirectDisplayID) = (
        "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", 1
    )
    private static let external: (uuid: String, displayID: CGDirectDisplayID) = (
        "11111111-2222-3333-4444-555555555555", 2
    )

    private var connectedDisplays: [(uuid: String, displayID: CGDirectDisplayID)] {
        [Self.primary, Self.external]
    }

    // MARK: Storage

    @Test("Storage keys round-trip for every case")
    func storageRoundTrip() {
        let cases: [RecordingWatchScreen] = [
            .screenWithPointer,
            .mainDisplay,
            .display(uuid: "11111111-2222-3333-4444-555555555555"),
        ]
        for choice in cases {
            #expect(RecordingWatchScreen.from(storageKey: choice.storageKey) == choice)
        }
    }

    @Test("A display's storage key carries the UUID, not the display ID")
    func storageKeyEncodesUUID() {
        let key = RecordingWatchScreen.display(uuid: Self.external.uuid).storageKey
        // Display IDs are transient across reboots; nothing persisted may
        // depend on them. The prefix names the case, the tail is the UUID.
        #expect(key.hasPrefix("display:"))
        #expect(key.hasSuffix(Self.external.uuid))
        #expect(!key.contains("displayID"))
    }

    @Test("Unrecognizable storage parses to nothing, not to a default")
    func garbageStorageRejected() {
        #expect(RecordingWatchScreen.from(storageKey: "") == nil)
        #expect(RecordingWatchScreen.from(storageKey: "cheapTrick") == nil)
        // The prefix alone is not a display; the UUID must be present.
        #expect(RecordingWatchScreen.from(storageKey: "display") == nil)
        #expect(RecordingWatchScreen.from(storageKey: "display:") == nil)
    }

    // MARK: Resolution

    @Test("Screen with pointer follows the pointer, then the primary")
    func pointerScreen() {
        let choice = RecordingWatchScreen.screenWithPointer
        #expect(choice.resolve(
            pointerDisplayID: Self.external.displayID,
            primaryDisplayID: Self.primary.displayID,
            connectedDisplays: connectedDisplays
        ) == Self.external.displayID)

        // A pointer over a display Thaw cannot identify (or no pointer at
        // all, e.g. an announcement fired by automation) still lands
        // somewhere readable rather than nowhere.
        #expect(choice.resolve(
            pointerDisplayID: nil,
            primaryDisplayID: Self.primary.displayID,
            connectedDisplays: connectedDisplays
        ) == Self.primary.displayID)
    }

    @Test("Main display ignores the pointer entirely")
    func mainDisplay() {
        let choice = RecordingWatchScreen.mainDisplay
        #expect(choice.resolve(
            pointerDisplayID: Self.external.displayID,
            primaryDisplayID: Self.primary.displayID,
            connectedDisplays: connectedDisplays
        ) == Self.primary.displayID)
    }

    @Test("A connected chosen display wins; a missing one falls back to primary")
    func chosenDisplay() {
        let choice = RecordingWatchScreen.display(uuid: Self.external.uuid)
        #expect(choice.resolve(
            pointerDisplayID: Self.primary.displayID,
            primaryDisplayID: Self.primary.displayID,
            connectedDisplays: connectedDisplays
        ) == Self.external.displayID)

        // The display was unplugged: the announcement must not vanish, and
        // the primary display is the predictable place for it.
        #expect(choice.resolve(
            pointerDisplayID: Self.primary.displayID,
            primaryDisplayID: Self.primary.displayID,
            connectedDisplays: [Self.primary]
        ) == Self.primary.displayID)
    }

    @Test("With no screens at all there is nowhere to show")
    func noScreens() {
        for choice in [RecordingWatchScreen.screenWithPointer, .mainDisplay] {
            #expect(choice.resolve(
                pointerDisplayID: nil,
                primaryDisplayID: nil,
                connectedDisplays: []
            ) == nil)
        }
    }
}
