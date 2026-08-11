//
//  OpenInterfaceWindowTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/windowIsOpenInterface(ownerPID:layer:height:interfacePIDs:)``,
/// the last-resort reading of whether a temporarily shown item's menu is still
/// open once the window captured at click time is gone or was never captured.
///
/// #924's search-panel path lands here: activating an item from the search
/// panel shows it, opens its menu, and the rehide check runs against a context
/// whose interface was never identified. A negative reading rehides — dragging
/// the item off the bar and closing the menu the user just opened, two to three
/// seconds in.
@Suite("Open interface window")
struct OpenInterfaceWindowTests {
    private let itemOwner: pid_t = 501
    private let menuOwner: pid_t = 502
    private let unrelated: pid_t = 900

    private let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
    private let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    private let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    private let floatingLevel = Int(CGWindowLevelForKey(.floatingWindow))
    private let normalLevel = Int(CGWindowLevelForKey(.normalWindow))

    private func isOpenInterface(
        ownerPID: pid_t,
        layer: Int,
        height: CGFloat = 300,
        interfacePIDs: Set<pid_t>
    ) -> Bool {
        MenuBarItemManager.windowIsOpenInterface(
            ownerPID: ownerPID,
            layer: layer,
            height: height,
            interfacePIDs: interfacePIDs
        )
    }

    // MARK: Which processes count

    /// The ordinary case: one app owns both the status item and its menu.
    @Test("A menu owned by the item's own process counts")
    func menuFromItemOwnerCounts() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: popUpLevel, interfacePIDs: [itemOwner]))
    }

    /// The regression. On macOS 26 the item's window is owned by Control
    /// Center while the app draws the menu, so a check keyed on the window's
    /// owner alone never finds the open menu and the rehide proceeds.
    @Test("A menu owned by the item's source process counts")
    func menuFromSourceProcessCounts() {
        #expect(
            isOpenInterface(
                ownerPID: menuOwner,
                layer: popUpLevel,
                interfacePIDs: [itemOwner, menuOwner]
            )
        )
    }

    /// The breadth is not unlimited — some other app's menu being open says
    /// nothing about this item, and treating it as evidence would strand the
    /// item in the visible section for as long as anything on the Mac had a
    /// menu down.
    @Test("A menu owned by an unrelated process does not count")
    func menuFromUnrelatedProcessDoesNotCount() {
        #expect(
            !isOpenInterface(
                ownerPID: unrelated,
                layer: popUpLevel,
                interfacePIDs: [itemOwner, menuOwner]
            )
        )
    }

    /// A context that resolved neither PID has nothing to match against, and
    /// must not fall back to matching everything.
    @Test("An empty PID set matches nothing")
    func emptyPIDSetMatchesNothing() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: popUpLevel, interfacePIDs: []))
    }

    // MARK: Which window levels count

    /// Some menus sit a level below the pop-up level; ``WindowInfo/isMenuRelated``
    /// allows the same slack.
    @Test("A window one level below pop-up counts")
    func oneLevelBelowPopUpCounts() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: popUpLevel - 1, interfacePIDs: [itemOwner]))
    }

    /// A pop-up level window is a menu whatever its size, so the height rule
    /// that guards the status levels must not apply here.
    @Test("Height is not consulted at pop-up level")
    func popUpLevelIgnoresHeight() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: popUpLevel, height: 22, interfacePIDs: [itemOwner]))
    }

    @Test("A tall status-level window counts")
    func tallStatusWindowCounts() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: statusLevel, height: 300, interfacePIDs: [itemOwner]))
    }

    @Test("A tall main-menu-level window counts")
    func tallMainMenuWindowCounts() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: mainMenuLevel, height: 300, interfacePIDs: [itemOwner]))
    }

    /// The status item itself lives at status level in the menu bar. Counting
    /// it would mean the interface always reads as showing and the item never
    /// goes home.
    @Test("The status item itself does not count as its own menu")
    func menuBarSizedStatusWindowDoesNotCount() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: statusLevel, height: 22, interfacePIDs: [itemOwner]))
    }

    /// The far side of the same trade: a liberal "anything above normal" match
    /// would take an ordinary floating panel of the app as an open menu.
    @Test("A floating window does not count")
    func floatingWindowDoesNotCount() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: floatingLevel, interfacePIDs: [itemOwner]))
    }

    @Test("A normal window does not count")
    func normalWindowDoesNotCount() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: normalLevel, interfacePIDs: [itemOwner]))
    }
}
