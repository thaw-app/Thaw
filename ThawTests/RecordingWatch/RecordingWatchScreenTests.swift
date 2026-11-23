//
//  RecordingWatchScreenTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

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
        // Display IDs change across reboots, so nothing saved may depend on them.
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

        // No pointer, as for an announcement fired by automation, still lands somewhere.
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

        // The chosen display was unplugged.
        #expect(choice.resolve(
            pointerDisplayID: Self.primary.displayID,
            primaryDisplayID: Self.primary.displayID,
            connectedDisplays: [Self.primary]
        ) == Self.primary.displayID)
    }

    @Test("Each screen choice has its own label")
    func labels() {
        let pointer = RecordingWatchScreen.screenWithPointer.localized
        let main = RecordingWatchScreen.mainDisplay.localized
        let chosen = RecordingWatchScreen.display(uuid: "A").localized
        #expect(pointer != main && main != chosen && pointer != chosen)
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
