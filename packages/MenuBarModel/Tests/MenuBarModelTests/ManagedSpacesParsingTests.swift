//
//  ManagedSpacesParsingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// Entries shaped like CGSCopyManagedDisplaySpaces output on two displays.
enum ManagedSpaceFixtures {
    static var displays: [[String: Any]] {
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
}

struct ManagedSpacesParsingTests {
    @Test("Each display's Spaces keep their order, kind and key")
    func parsesFixture() {
        let spaces = Bridging.managedSpaces(fromDisplays: ManagedSpaceFixtures.displays)
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
