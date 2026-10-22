//
//  MenuBarItemManager+ConcealedClick.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import MenuBarModel

// MARK: - Concealed Item Click

extension MenuBarItemManager {
    /// Opens a concealed item without lending it a seat beside Thaw's icon:
    /// every method presses or reveals the item where it sits. Apps answer
    /// different methods, so they are tried cheapest-first and the one that
    /// worked is remembered. Electron tray items take an AX press.
    /// Returns .completed or .activationFailed; callers that only want the click can ignore it.
    @MainActor
    @discardableResult
    func clickConcealedItem(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        on displayID: CGDirectDisplayID
    ) async -> MenuBarItemActivationOutcome {
        repairs.interruptAutomaticWork(by: .userClickedItem)
        guard let controller = appState?.menuBarManager.sectionController else { return .activationFailed }

        // Opening an item on another display activates it; the repair pass must
        // not read that as a topology change.
        if displayID != (Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()) {
            noteSelfInflictedDisplayChange()
        }

        // A visible-authored item can still be concealed by the automatic-overflow
        // set, which hides it through the same assertion the hidden sections use.
        let section = controller.section(for: item)
        let isEffectivelyConcealed = controller.isEffectivelyConcealed(item)
        // A visible item macOS is not drawing cannot be clicked where its
        // frame says it is; that seat belongs to something else.
        let isNotShown = itemsNotShownOnBarTags.contains(item.tag)
        guard section != .visible || isEffectivelyConcealed || isNotShown else {
            // Electron/Chromium tray items ignore a synthetic click wherever they
            // sit and take an AX press; other apps' normal click preserves their toggle.
            if mouseButton == .left, isElectronItem(item), await pressItemViaAccessibility(item) {
                MenuBarItemManager.diagLog.info(
                    "clickConcealedItem: opened visible \(item.logString) via AX press"
                )
                // The press landed; nothing here watches what the owner did with it.
                return .completed(reactionObserved: false)
            }
            guard let reaction = try? await click(item: item, with: mouseButton) else {
                return .activationFailed
            }
            return .completed(reactionObserved: reaction.didReact)
        }

        // Closing an open menu removes a window, which reads as no reaction;
        // without this the fallbacks would reopen it.
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
        let menusBefore = ownerMenuWindowIDs(item)
        if mouseButton == .left, let opened = menusOpenedByClick[key], !opened.isDisjoint(with: menusBefore) {
            menusOpenedByClick[key] = nil
            let reacted = await pressConcealedItemInPlace(item)
            MenuBarItemManager.diagLog.info(
                "clickConcealedItem: \(item.logString) had its menu open; pressed once to close it"
            )
            return .completed(reactionObserved: reacted)
        }

        // Apps answer different methods, so try them cheapest first, stop at
        // the first one the owner reacts to, and start there next time.
        let identity = openMethodIdentity(for: item)
        let learned = LearnedOpenMethods.standard.method(for: identity)
        let showInMenuBar = appState?.settings.general.openHiddenItemsInMenuBar ?? false
        for method in ConcealedItemOpenMethod.openMethodOrder(for: mouseButton, learned: learned, showInMenuBar: showInMenuBar) {
            let opened = switch method {
            case .pressInPlace, .showMenuInPlace:
                await revealAndPressConcealedItem(item, method: method, controller: controller)
            case .revealInPlace:
                await revealInPlaceAndClick(item: item, with: mouseButton, on: displayID, controller: controller)
            }
            if opened {
                MenuBarItemManager.diagLog.info(
                    "clickConcealedItem: opened \(item.logString) via \(method.rawValue)"
                )
                menusOpenedByClick[key] = ownerMenuWindowIDs(item).subtracting(menusBefore)
                LearnedOpenMethods.standard.record(method, for: identity, clickedWith: mouseButton)
                return .completed(reactionObserved: true)
            }
            MenuBarItemManager.diagLog.debug(
                "clickConcealedItem: \(method.rawValue) did not open \(item.logString); trying the next method"
            )
        }

        // Nothing opened it. Leave it in the bar for the temporary-show
        // interval so the user can click the real icon.
        LearnedOpenMethods.standard.record(nil, for: identity, clickedWith: mouseButton)
        MenuBarItemManager.diagLog.warning(
            "clickConcealedItem: no method opened \(item.logString); leaving it shown in the menu bar"
        )
        controller.revealItemTemporarily(item.uniqueIdentifier)
        controller.scheduleTemporaryItemConcealUnlessHeld(item.uniqueIdentifier)
        return .activationFailed
    }

    /// The owner's windows on screen at pop-up menu level. Not the status bar
    /// level, which also holds the owner's own icons.
    private func ownerMenuWindowIDs(_ item: MenuBarItem) -> Set<CGWindowID> {
        let pids = item.reactionPIDs
        let windows = WindowInfo.createWindows(from: Bridging.getWindowList(option: .onScreen)).filter { window in
            pids.contains(window.ownerPID) && WindowLevelPredicates.isPopUpMenu(layer: window.layer)
        }
        return Set(windows.map(\.windowID))
    }

    /// Shows a concealed item where it sits, presses it once the bar draws it and returns whether
    /// the owner reacted. A press on an item the bar does not draw leaves MenuBarAgent holding a
    /// selection that keeps the bar on screen whenever it should hide, also later in a
    /// full-screen app, until MenuBarAgent restarts. The reveal is handed back like
    /// revealInPlaceAndClick's. A right click's menu is still opened where the item is parked.
    private func revealAndPressConcealedItem(_ item: MenuBarItem, method: ConcealedItemOpenMethod, controller: any MenuBarSectionControlling) async -> Bool {
        guard method == .pressInPlace else {
            return await pressConcealedItemInPlace(item, method: method)
        }
        let identifier = item.uniqueIdentifier
        // The menu-open check takes what it sees on its first look as already there; look before the menu opens.
        _ = await menuOpenMonitor.isAnyMenuOpen()
        controller.revealItemTemporarily(identifier)
        // The runtime drops a reveal that undoes a recent conceal as a flap; this one answers a click.
        controller.refresh(forceRestrictionPulse: false, forceReapply: true)
        await eventSleep(for: Constants.MenuBarTuning.thawBarRevealSettle)
        // No press until the bar draws it: an undrawn press is the one that strands the bar. With the
        // bar slid away there is nothing to press; with it on screen an item still undrawn has no room
        // on the bar, and the press it always had is the only way to open it.
        let drawn = await MenuBarAXQueries.waitForDrawnStatusItem(pid: resolvedPID(for: item), timeout: Constants.MenuBarTuning.thawBarRevealAXWait)
        let barDisplay = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        guard drawn || MenuBarItemImageCache.isMenuBarOnScreen(displayID: barDisplay), await pressConcealedItemInPlace(item) else {
            controller.concealTemporarilyRevealedItem(identifier)
            return false
        }
        // Let the menu open before the conceal starts waiting for it to close.
        await eventSleep(for: Constants.MenuBarTuning.thawBarPostClickSettle)
        controller.scheduleTemporaryItemConceal(identifier)
        return true
    }

    /// Presses the item's AX element without revealing it. Returns whether the
    /// owner reacted. The extras-bar press is frame-matched, so it goes first;
    /// the hosted press covers MenuBarAgent's parked, frameless elements.
    private func pressConcealedItemInPlace(_ item: MenuBarItem, method: ConcealedItemOpenMethod = .pressInPlace) async -> Bool {
        if method == .showMenuInPlace {
            return await InPlaceMenuOpener.showMenu(for: item, pid: resolvedPID(for: item))
        }
        let snapshot = ClickReactionVerifier.snapshot(for: item)
        let ownPress = await pressItemViaAccessibility(item)
        var pressed = ownPress
        if !pressed {
            pressed = await MenuBarAXQueries.pressHostedItem(sourcePID: resolvedPID(for: item))
        }
        guard pressed else {
            MenuBarItemManager.diagLog.debug(
                "pressInPlace: no press landed for \(item.logString) pid=\(resolvedPID(for: item)) owner=\(item.ownerPID) bounds=\(item.bounds)"
            )
            return false
        }
        let reaction = await ClickReactionVerifier.verifyAllowingLateOpen(against: snapshot)
        MenuBarItemManager.diagLog.debug(
            "pressInPlace: pressed \(item.logString) via \(ownPress ? "own bar" : "hosted"); reacted=\(reaction.didReact)"
        )
        return reaction.didReact
    }
}
