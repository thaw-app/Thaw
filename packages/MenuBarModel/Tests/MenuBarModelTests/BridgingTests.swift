//
//  BridgingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// The degenerate-size gate in Bridging.captureWindowsImageSCK: a window server that has not laid
/// the bar out answers a sliver, which must fail so callers fall back rather than cache it.
@Suite("Capture size gate")
struct BridgingCaptureSizeTests {
    @Test("Slivers, empty and single-pixel captures are rejected", arguments: [
        (1470, 1), (2940, 1), (0, 0), (1, 40), (40, 1),
    ] as [(Int, Int)])
    func rejectsDegenerateSizes(width: Int, height: Int) {
        #expect(!Bridging.isPlausibleCaptureSize(width: width, height: height))
    }

    @Test("A real menu bar capture is accepted")
    func acceptsMenuBarCapture() {
        #expect(Bridging.isPlausibleCaptureSize(width: 2940, height: 66))
        #expect(Bridging.isPlausibleCaptureSize(width: 2, height: 2))
    }
}

/// A CF value that is not an array must never reach the array bridge, which aborts on it;
/// the guards have to answer nil instead.
@Suite("CF type guards")
struct BridgingTypeGuardTests {
    @Test("An array reads as an array, and nothing else does")
    func arrayValue() {
        #expect(Bridging.arrayValue(of: ["one", "two"] as CFArray) as? [String] == ["one", "two"])
        #expect(Bridging.arrayValue(of: "text" as CFString) == nil)
        #expect(Bridging.arrayValue(of: 7 as CFNumber) == nil)
        #expect(Bridging.arrayValue(of: ["k": 1] as CFDictionary) == nil)
        #expect(Bridging.arrayValue(of: nil) == nil)
    }

    @Test("A dictionary reads as a dictionary, and nothing else does")
    func dictionaryValue() {
        let entries: [String: Any]? = Bridging.dictionaryValue(of: ["key": 42] as CFDictionary)
        let fromString: [String: Any]? = Bridging.dictionaryValue(of: "text" as CFString)
        let fromArray: [String: Any]? = Bridging.dictionaryValue(of: ["one"] as CFArray)
        let fromNil: [String: Any]? = Bridging.dictionaryValue(of: nil)
        #expect(entries?["key"] as? Int == 42)
        #expect(fromString == nil)
        #expect(fromArray == nil)
        #expect(fromNil == nil)
    }
}

@Suite("Managed Spaces parsing")
struct ManagedSpacesParsingTests {
    /// Entries shaped like CGSCopyManagedDisplaySpaces output on two displays.
    private static var displays: [[String: Any]] {
        [
            [
                "Display Identifier": "LEFT",
                "Spaces": [
                    ["id64": 1, "ManagedSpaceID": 1, "type": 0, "uuid": ""],
                    ["id64": 5, "ManagedSpaceID": 5, "type": 4, "uuid": "FULL-1", "pid": 412],
                    ["id64": 6, "ManagedSpaceID": 6, "type": 0, "uuid": "DESK-2"],
                    ["id64": 9, "ManagedSpaceID": 9, "type": 7, "uuid": "ODD-1"],
                ] as [[String: Any]],
            ],
            [
                "Display Identifier": "RIGHT",
                "Spaces": [
                    ["id64": 2, "ManagedSpaceID": 2, "type": 0, "uuid": "DESK-R1"],
                    ["id64": 3, "ManagedSpaceID": 3, "uuid": "DESK-R2"],
                ] as [[String: Any]],
            ],
            ["Display Identifier": "DETACHED"],
        ]
    }

    @Test("Each display's Spaces keep their order, kind and key")
    func parsesFixture() {
        let spaces = Bridging.managedSpaces(fromDisplays: Self.displays)
        #expect(spaces.map(\.spaceID) == [1, 5, 6, 9, 2, 3])
        #expect(spaces.map(\.persistentKey) == ["display:LEFT#default", "FULL-1", "DESK-2", "ODD-1", "DESK-R1", "DESK-R2"])
        #expect(spaces.map(\.kind) == [.desktop, .fullscreen, .desktop, .other(7), .desktop, .desktop])
        #expect(spaces.map(\.ordinal) == [1, 2, 3, 4, 1, 2])
        #expect(spaces[1].ownerPID == 412)
        #expect(spaces[0].ownerPID == nil)
    }

    @Test("A Space without an id is skipped, and a desktop never carries an owner")
    func skipsBrokenEntries() {
        let display: [String: Any] = ["Display Identifier": "D", "Spaces": [["uuid": "NO-ID"], ["id64": 4, "type": 0, "pid": 9]] as [[String: Any]]]
        let spaces = Bridging.managedSpaces(fromDisplays: [display])
        #expect(spaces.map(\.spaceID) == [4])
        #expect(spaces[0].ownerPID == nil)
        #expect(Bridging.managedSpaces(fromDisplays: [["Spaces": [["id64": 8]] as [[String: Any]]]])[0].displayIdentifier == "unknown")
    }
}

@Suite("Window server Space events")
struct WindowServerSpaceEventTests {
    @Test("Each registered id maps to its event, and window membership and unknown ids are ignored", arguments: [
        (UInt32(1329), WindowServerSpaceEvent?.some(.activeSpaceChanged)),
        (1401, .activeSpaceChanged),
        (818, .spacesChanged),
        (828, .spacesChanged),
        (1322, .spacesChanged),
        (0, nil), (1325, nil), (1326, nil), (1327, nil), (1328, nil), (9999, nil),
    ])
    func mapsEventIDs(id: UInt32, event: WindowServerSpaceEvent?) {
        #expect(WindowServerSpaceEvent(eventID: id) == event)
    }

    @Test("Only the ids that map to an event are registered")
    func registeredIDs() {
        #expect(WindowServerSpaceEvent.registeredEventIDs.sorted() == [818, 828, 1322, 1329, 1401])
    }
}
