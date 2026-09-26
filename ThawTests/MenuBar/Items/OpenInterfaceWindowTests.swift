//
//  OpenInterfaceWindowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/windowIsOpenInterface(ownerPID:layer:height:interfacePIDs:)``,
/// the last-resort check for whether a temporarily shown item's menu is still
/// open when no window was captured at click time.
///
/// Items shown from the search panel land here; a negative reading rehides the
/// item and closes the menu the user just opened (#924).
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

    @Test("A menu owned by the item's own process counts")
    func menuFromItemOwnerCounts() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: popUpLevel, interfacePIDs: [itemOwner]))
    }

    /// On macOS 26 Control Center owns the item's window while the app draws the
    /// menu, so matching on the window owner alone never finds the open menu.
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

    /// Another app's open menu says nothing about this item; counting it would
    /// strand the item visible while any menu on the Mac is down.
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

    /// A context with neither PID resolved must not fall back to matching everything.
    @Test("An empty PID set matches nothing")
    func emptyPIDSetMatchesNothing() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: popUpLevel, interfacePIDs: []))
    }

    // MARK: Which window levels count

    /// Some menus sit a level below pop-up; ``WindowInfo/isMenuRelated`` allows the same slack.
    @Test("A window one level below pop-up counts")
    func oneLevelBelowPopUpCounts() {
        #expect(isOpenInterface(ownerPID: itemOwner, layer: popUpLevel - 1, interfacePIDs: [itemOwner]))
    }

    /// A pop-up level window is a menu at any size, so the status-level height rule does not apply.
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

    /// The status item lives at status level; counting it would keep the item from ever going home.
    @Test("The status item itself does not count as its own menu")
    func menuBarSizedStatusWindowDoesNotCount() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: statusLevel, height: 22, interfacePIDs: [itemOwner]))
    }

    /// A liberal "anything above normal" match would take the app's floating panel for a menu.
    @Test("A floating window does not count")
    func floatingWindowDoesNotCount() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: floatingLevel, interfacePIDs: [itemOwner]))
    }

    @Test("A normal window does not count")
    func normalWindowDoesNotCount() {
        #expect(!isOpenInterface(ownerPID: itemOwner, layer: normalLevel, interfacePIDs: [itemOwner]))
    }
}

/// Covers ``MenuBarItemManager/interfaceWindowToTrack(among:interfacePIDs:)``,
/// which picks the window a temporarily shown item's rehide check watches.
///
/// A tracked window skips the grace period and the `unknown` budget, so tracking
/// a window that is not the menu drags the item home with the menu still open (#924).
@Suite("Interface window to track")
struct InterfaceWindowToTrackTests {
    private let itemOwner: pid_t = 501
    private let menuOwner: pid_t = 502
    private let unrelated: pid_t = 900

    private let popUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
    private let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    private let floatingLevel = Int(CGWindowLevelForKey(.floatingWindow))

    private func window(
        id: CGWindowID,
        ownerPID: pid_t,
        layer: Int,
        height: CGFloat
    ) -> WindowInfo {
        WindowInfo(
            windowID: id,
            ownerPID: ownerPID,
            bounds: CGRect(x: 0, y: 0, width: 200, height: height),
            layer: layer
        )
    }

    private func tracked(_ candidates: [WindowInfo], pids: Set<pid_t>) -> CGWindowID? {
        MenuBarItemManager.interfaceWindowToTrack(among: candidates, interfacePIDs: pids)?.windowID
    }

    @Test("A menu from the item's own process is tracked")
    func menuFromItemOwnerIsTracked() {
        let menu = window(id: 1, ownerPID: itemOwner, layer: popUpLevel, height: 300)
        #expect(tracked([menu], pids: [itemOwner]) == 1)
    }

    /// Control Center-hosted items have their window and menu in different processes.
    @Test("A menu from the item's source process is tracked")
    func menuFromSourceProcessIsTracked() {
        let menu = window(id: 1, ownerPID: menuOwner, layer: popUpLevel, height: 300)
        #expect(tracked([menu], pids: [itemOwner, menuOwner]) == 1)
    }

    @Test("A window from an unrelated process is never tracked")
    func unrelatedProcessIsNotTracked() {
        let other = window(id: 1, ownerPID: unrelated, layer: popUpLevel, height: 300)
        #expect(tracked([other], pids: [itemOwner, menuOwner]) == nil)
    }

    /// Control Center is in the PID set for every hosted item and opens item-sized
    /// windows of its own around a click; tracking one declares the menu closed
    /// about a second after it opened.
    @Test("An item-sized window from a hosting process is not tracked")
    func itemSizedWindowIsNotTracked() {
        let incidental = window(id: 1, ownerPID: itemOwner, layer: statusLevel, height: 22)
        #expect(tracked([incidental], pids: [itemOwner, menuOwner]) == nil)
    }

    /// Tracking nothing leaves the reading `unknown`, which the grace period and
    /// bounded re-checks handle; better than answering from a non-menu window.
    @Test("Nothing worth tracking tracks nothing")
    func nothingQualifyingTracksNothing() {
        #expect(tracked([], pids: [itemOwner]) == nil)
    }

    /// Window list order says nothing about which is the menu, so the menu must be preferred.
    @Test("A menu is preferred over an incidental window that opened with it")
    func menuIsPreferredOverIncidentalWindow() {
        let incidental = window(id: 1, ownerPID: itemOwner, layer: statusLevel, height: 22)
        let menu = window(id: 2, ownerPID: menuOwner, layer: popUpLevel, height: 300)
        #expect(tracked([incidental, menu], pids: [itemOwner, menuOwner]) == 2)
    }

    /// Electron menus and agent-app popovers open at levels no menu rule matches;
    /// a window too tall to be a status item is tracked when no menu-level one appeared.
    @Test("A tall window at an unrecognized level is tracked as a last resort")
    func tallWindowIsTrackedAsLastResort() {
        let popover = window(id: 1, ownerPID: itemOwner, layer: floatingLevel, height: 300)
        #expect(tracked([popover], pids: [itemOwner]) == 1)
    }

    /// The same window at menu bar height is the item, not something it opened.
    @Test("A short window at an unrecognized level is not tracked")
    func shortWindowAtUnrecognizedLevelIsNotTracked() {
        let sliver = window(id: 1, ownerPID: itemOwner, layer: floatingLevel, height: 22)
        #expect(tracked([sliver], pids: [itemOwner]) == nil)
    }
}
