//
//  WindowServerSpaceEventTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

struct WindowServerSpaceEventTests {
    @Test("Both active Space ids mean the active Space changed")
    func activeSpaceIDs() {
        #expect(WindowServerSpaceEvent(eventID: 1329) == .activeSpaceChanged)
        #expect(WindowServerSpaceEvent(eventID: 1401) == .activeSpaceChanged)
    }

    @Test("Creating or deleting a Space maps to one event")
    func spaceListIDs() {
        for id: UInt32 in [818, 828, 1322] {
            #expect(WindowServerSpaceEvent(eventID: id) == .spacesChanged)
        }
    }

    @Test("Window membership and unknown ids are ignored")
    func ignoredIDs() {
        for id: UInt32 in [0, 1325, 1326, 1327, 1328, 9999] {
            #expect(WindowServerSpaceEvent(eventID: id) == nil)
        }
        #expect(WindowServerSpaceEvent.registeredEventIDs.sorted() == [818, 828, 1322, 1329, 1401])
    }
}
