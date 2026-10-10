//
//  SectionOrderRecordingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Section order recording")
struct SectionOrderRecordingTests {
    @Test("Recording consecutive completed drops does not schedule another layout")
    func completedDropsOnlyRecordOrder() {
        let manager = MenuBarItemManager()
        let afterDroppy = ["app:A", "iordv.Droppy:DroppyMenuBar", "com.ethanbills.DockDoor:Item-0"]
        manager.mirrorSectionOrderNow(afterDroppy, for: .visible)
        #expect(manager.savedSectionOrder[MenuBarSectionName.visible.rawValue] == afterDroppy)
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)

        let afterDockDoor = ["app:A", "com.ethanbills.DockDoor:Item-0", "iordv.Droppy:DroppyMenuBar"]
        manager.mirrorSectionOrderNow(afterDockDoor, for: .visible)
        #expect(manager.savedSectionOrder[MenuBarSectionName.visible.rawValue] == afterDockDoor)
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)
    }

    @Test("Unfulfilled visible intent still explicitly schedules physical application")
    func explicitApplyIsSeparateFromRecording() {
        let manager = MenuBarItemManager()
        manager.mirrorSectionOrderNow(["app:A", "app:B"], for: .visible)
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)
        manager.scheduleSectionOrderApply(for: .visible)
        #expect(manager.authoredVisibleOrderPendingPhysicalApply)

        // A newer completed move supersedes that old whole-section request.
        manager.mirrorSectionOrderNow(["app:B", "app:A"], for: .visible)
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)
    }

    @Test("An empty record does not request a physical layout")
    func emptyOrderDoesNotApply() {
        let manager = MenuBarItemManager()
        manager.scheduleSectionOrderApply(for: .visible)
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)
    }

    @Test("A new user move cancels an older section request")
    func userMoveSupersedesOldApply() {
        let manager = MenuBarItemManager()
        manager.mirrorSectionOrderNow(["app:A", "app:B"], for: .visible)
        manager.scheduleSectionOrderApply(for: .visible)
        manager.cancelPendingSectionOrderApply()
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)
    }

    @Test("A stale pane must not persist Droppy's old position after moving DockDoor")
    func recordsObservedPeersInsteadOfStalePaneOrder() throws {
        let a = Self.item("A", x: 10)
        let droppy = Self.item("Droppy", x: 40)
        let dockDoor = Self.item("DockDoor", x: 70)
        let b = Self.item("B", x: 100)
        let stalePane = [a, dockDoor, b, droppy]
        let result = try #require(MenuBarItemManager.sectionOrderAfterCompletedMove(
            of: dockDoor,
            proposedOrder: stalePane,
            liveItems: [b, dockDoor, a, droppy]
        ))
        #expect(result.map(\.uniqueIdentifier) == [a, droppy, dockDoor, b].map(\.uniqueIdentifier))
    }

    @Test("A member absent from AX keeps its slot when live members are recorded")
    func preservesUnobservedMember() throws {
        let a = Self.item("A", x: 10)
        let absent = Self.item("Absent", x: 40)
        let b = Self.item("B", x: 70)
        let result = try #require(MenuBarItemManager.sectionOrderAfterCompletedMove(
            of: b,
            proposedOrder: [b, absent, a],
            liveItems: [a, b]
        ))
        #expect(result.map(\.uniqueIdentifier) == [a, absent, b].map(\.uniqueIdentifier))
    }

    @Test("A missing mover cannot commit the pane's unverified order")
    func missingMoverDoesNotCommit() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        #expect(MenuBarItemManager.sectionOrderAfterCompletedMove(
            of: b, proposedOrder: [b, a], liveItems: [a]
        ) == nil)
    }

    @Test("Ordinary user moves do not schedule a structural replay")
    func singleItemMoveDoesNotNormalizeStructure() {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        #expect(!MenuBarItemManager.shouldNormalizeStructureAfterMove(
            item: b, destination: .leftOfItem(a), isUserInitiated: true
        ))
        #expect(MenuBarItemManager.shouldNormalizeStructureAfterMove(
            item: b, destination: .leftOfItem(a), isUserInitiated: false
        ))
    }

    @Test("Control-item and boundary edits retain structural normalization")
    func structuralEditsStillNormalize() {
        let a = Self.item("A", x: 10)
        let control = MenuBarItem(
            tag: ControlItemIdentifier.hidden.tag,
            windowID: 999,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: 70, y: 0, width: 24, height: 24),
            title: ControlItemIdentifier.hidden.rawValue,
            isOnScreen: true
        )
        #expect(MenuBarItemManager.shouldNormalizeStructureAfterMove(
            item: a, destination: .leftOfItem(control), isUserInitiated: true
        ))
        #expect(MenuBarItemManager.shouldNormalizeStructureAfterMove(
            item: control, destination: .leftOfItem(a), isUserInitiated: true
        ))
    }

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("Recording concealed order leaves physical application to reveal", arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func concealedOrderDoesNotScheduleVisibleApply(section: MenuBarSectionName) {
        let manager = MenuBarItemManager()
        manager.mirrorSectionOrderNow(["app:A", "app:B"], for: section)
        #expect(manager.savedSectionOrder[section.rawValue] == ["app:A", "app:B"])
        manager.scheduleSectionOrderApply(for: section)
        #expect(!manager.authoredVisibleOrderPendingPhysicalApply)
    }
}
