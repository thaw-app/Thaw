//
//  SpaceLabelsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// Two displays: on the left a default desktop, a full screen Space, a desktop and an
/// unknown type; on the right two desktops.
private let fixture = Bridging.managedSpaces(fromDisplays: [
    [
        "Display Identifier": "LEFT",
        "Spaces": [
            ["id64": 1, "type": 0, "uuid": ""],
            ["id64": 5, "type": 4, "uuid": "FULL-1", "pid": 412],
            ["id64": 6, "type": 0, "uuid": "DESK-2"],
            ["id64": 9, "type": 7, "uuid": "ODD-1"],
        ] as [[String: Any]],
    ],
    [
        "Display Identifier": "RIGHT",
        "Spaces": [
            ["id64": 2, "type": 0, "uuid": "DESK-R1"],
            ["id64": 3, "type": 4, "uuid": "FULL-R"],
            ["id64": 4, "type": 0, "uuid": "DESK-R2"],
        ] as [[String: Any]],
    ],
])

@Suite("Space labels")
struct SpaceLabelsTests {
    private static let names: [pid_t: String] = [412: "Safari", 77: "Keynote"]

    @Test("Desktops are numbered per display and skip full screen Spaces")
    func numbering() {
        let numbers = SpaceLabels.desktopNumbers(fixture)
        #expect(numbers == [1: 1, 6: 2, 2: 1, 4: 2])
    }

    @Test("Groups follow the displays, label full screen Spaces by app and mark the menu bar display")
    func grouping() {
        let groups = SpaceLabels.groups(
            fixture,
            displayNames: ["LEFT": "Built-in Display"],
            menuBarDisplay: "RIGHT",
            ownerName: { Self.names[$0] }
        )
        #expect(groups.map(\.id) == ["LEFT", "RIGHT"])
        #expect(groups.map(\.displayName) == ["Built-in Display", "Display"])
        #expect(groups.map(\.hasMenuBar) == [false, true])
        #expect(groups[0].spaces.map(\.label) == ["Desktop 1", "Safari", "Desktop 2", "Other Space"])
        #expect(groups[0].spaces.map(\.id) == ["display:LEFT#default", "FULL-1", "DESK-2", "ODD-1"])
        #expect(groups[1].spaces.map(\.label) == ["Desktop 1", "Full Screen App", "Desktop 2"])
        #expect(groups[0].spaces[1].ownerPID == 412)
    }

    @Test("A single display counts as having the menu bar when the identifiers differ")
    func singleDisplay() {
        let main = Bridging.managedSpaces(fromDisplays: [["Display Identifier": "Main", "Spaces": [["id64": 1]] as [[String: Any]]]])
        let groups = SpaceLabels.groups(main, displayNames: [:], menuBarDisplay: "UUID", ownerName: { _ in nil })
        #expect(groups.map(\.hasMenuBar) == [true])
        #expect(SpaceLabels.groups(main, displayNames: [:], menuBarDisplay: nil, ownerName: { _ in nil }).map(\.hasMenuBar) == [false])
    }

    @Test("A mapped Space that is gone is listed once as missing, with its stored name")
    func missing() {
        let missing = SpaceLabels.missing(
            mapped: [(key: "GONE", name: "Desktop 4"), (key: "DESK-2", name: "Desktop 2"), (key: "GONE", name: "Desktop 4"), (key: "OLD", name: nil)],
            present: fixture
        )
        #expect(missing.map(\.id) == ["GONE", "OLD"])
        #expect(missing.map(\.label) == ["Desktop 4", "A Space"])
        let allMissing = missing.allSatisfy(\.isMissing)
        #expect(allMissing)
    }

    @Test("A full screen Space without an owner takes the first app with a window on it")
    func ownersFromWindows() {
        let spaces = SpaceLabels.resolvingOwners(
            fixture,
            windows: [(pid: 10, windowID: 100), (pid: 77, windowID: 101), (pid: 78, windowID: 102)],
            spacesOfWindow: { [100: [1], 101: [3], 102: [3, 5]][$0] ?? [] }
        )
        #expect(spaces.first { $0.spaceID == 3 }?.ownerPID == 77)
        #expect(spaces.first { $0.spaceID == 5 }?.ownerPID == 412)
        #expect(spaces.first { $0.spaceID == 1 }?.ownerPID == nil)
        #expect(SpaceLabels.label(ofSpaceID: 3, in: spaces, ownerName: { Self.names[$0] }) == "Keynote")
        #expect(SpaceLabels.label(ofSpaceID: 4, in: spaces, ownerName: { _ in nil }) == "Desktop 2")
        #expect(SpaceLabels.label(ofSpaceID: 99, in: spaces, ownerName: { _ in nil }) == nil)
    }

    @Test("Owners are left alone when every full screen Space has one")
    func ownersUntouched() {
        let owned = fixture.filter { $0.spaceID != 3 }
        #expect(SpaceLabels.resolvingOwners(owned, windows: [(pid: 1, windowID: 1)], spacesOfWindow: { _ in [5] }) == owned)
    }
}

@MainActor
@Suite("Space picker", .serialized)
struct SpaceChoicePickerTests {
    @Test("The picker draws its groups, and a missing Space changes it")
    func draws() async throws {
        let groups = SpaceLabels.groups(fixture, displayNames: [:], menuBarDisplay: "LEFT", ownerName: { _ in "Safari" })
        let missing = SpaceLabels.missing(mapped: [(key: "GONE", name: "Desktop 9")], present: fixture)
        let plain = OffscreenRender(
            SpaceChoicePicker(groups: groups, missing: [], selection: .constant("FULL-1"), appIcon: { _ in NSImage(systemSymbolName: "safari", accessibilityDescription: nil) })
                .frame(width: 520, height: 80),
            size: CGSize(width: 520, height: 80)
        )
        let withMissing = OffscreenRender(
            SpaceChoicePicker(groups: groups, missing: missing, selection: .constant("GONE")).frame(width: 520, height: 80),
            size: CGSize(width: 520, height: 80)
        )
        await plain.settle { (try? plain.pixels())?.contains { $0 != 0 } == true }
        await withMissing.settle { (try? withMissing.pixels())?.contains { $0 != 0 } == true }
        let plainPixels = try plain.pixels()
        let missingPixels = try withMissing.pixels()
        #expect(plainPixels != missingPixels)
    }

    @Test("Headers and missing Spaces say so")
    func labels() {
        let group = SpaceDisplayGroup(id: "D", displayName: "Studio Display", hasMenuBar: true, spaces: [])
        #expect(SpaceChoicePicker.header(for: group) == "Studio Display · Has the menu bar")
        #expect(SpaceChoicePicker.header(for: SpaceDisplayGroup(id: "E", displayName: "Left", hasMenuBar: false, spaces: [])) == "Left")
        let gone = SpaceChoice(id: "K", label: "Desktop 3", kind: .desktop, ownerPID: nil, isMissing: true)
        #expect(SpaceChoicePicker.label(for: gone) == "Desktop 3 · Missing")
    }
}
