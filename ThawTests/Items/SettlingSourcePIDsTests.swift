//
//  SettlingSourcePIDsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// The startup settle waits only for live items to resolve a source PID.
@Suite("Settling source PIDs")
struct SettlingSourcePIDsTests {
    private static func item(_ bundle: String, ownerPID: pid_t, sourcePID: pid_t?) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: "Item-0", instanceIndex: 0),
            windowID: 1, ownerPID: ownerPID, sourcePID: sourcePID,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24), title: nil, isOnScreen: true
        )
    }

    /// A concealed item brought back from its saved snapshot, as the kit builds it: no process this boot.
    private static func snapshot(_ bundle: String) -> MenuBarItem {
        item(bundle, ownerPID: 0, sourcePID: nil)
    }

    @Test("Snapshots of concealed items are never waited for, so two of them do not hold the settle to its deadline")
    func snapshotsAreNotUnresolved() {
        let items = [
            Self.item("com.example.live", ownerPID: 100, sourcePID: 100),
            Self.snapshot("com.example.quit"),
            Self.snapshot("com.example.other"),
        ]
        #expect(SettlingSourcePIDs.unresolvedCount(in: items) == 0)
    }

    @Test("A live item still missing its source PID is waited for")
    func liveItemWithoutSourcePIDIsUnresolved() {
        let items = [
            Self.item("com.example.live", ownerPID: 100, sourcePID: nil),
            Self.snapshot("com.example.quit"),
        ]
        #expect(SettlingSourcePIDs.unresolvedCount(in: items) == 1)
    }

    @Test("Resolved live items count nothing")
    func resolvedItemsCountNothing() {
        #expect(SettlingSourcePIDs.unresolvedCount(in: [Self.item("com.example.live", ownerPID: 100, sourcePID: 200)]) == 0)
    }
}
