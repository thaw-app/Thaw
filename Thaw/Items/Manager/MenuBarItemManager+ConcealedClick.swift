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
        guard let controller = appState?.menuBarManager.sectionController else {
            return .activationFailed
        }

        // Opening an item on another display activates it; the repair pass must
        // not read that as a topology change.
        if displayID != (Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()) {
            noteSelfInflictedDisplayChange()
        }

        // A visible-authored item can still be concealed by the automatic-overflow
        // set, which hides it through the same assertion the hidden sections use.
        let section = controller.section(for: item)
        let isEffectivelyConcealed = controller.effectivelyConcealedIdentifiers.contains(
            MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
        )
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
        let learned = learnedOpenMethod(for: identity)
        let showInMenuBar = appState?.settings.general.openHiddenItemsInMenuBar ?? false
        for method in Self.openMethodOrder(for: mouseButton, learned: learned, showInMenuBar: showInMenuBar) {
            let opened = switch method {
            case .pressInPlace:
                await pressConcealedItemInPlace(item)
            case .revealInPlace:
                await revealInPlaceAndClick(item: item, with: mouseButton, on: displayID, controller: controller)
            }
            if opened {
                MenuBarItemManager.diagLog.info(
                    "clickConcealedItem: opened \(item.logString) via \(method.rawValue)"
                )
                menusOpenedByClick[key] = ownerMenuWindowIDs(item).subtracting(menusBefore)
                rememberOpenMethod(method, for: identity)
                return .completed(reactionObserved: true)
            }
            MenuBarItemManager.diagLog.debug(
                "clickConcealedItem: \(method.rawValue) did not open \(item.logString); trying the next method"
            )
        }

        // Nothing opened it. Leave it in the bar for the temporary-show
        // interval so the user can click the real icon.
        forgetOpenMethod(for: identity)
        MenuBarItemManager.diagLog.warning(
            "clickConcealedItem: no method opened \(item.logString); leaving it shown in the menu bar"
        )
        controller.revealItemTemporarily(item.uniqueIdentifier)
        controller.scheduleTemporaryItemConceal(item.uniqueIdentifier)
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

    /// Presses the item's AX element without revealing it. Returns whether the
    /// owner reacted. The extras-bar press is frame-matched, so it goes first;
    /// the hosted press covers MenuBarAgent's parked, frameless elements.
    private func pressConcealedItemInPlace(_ item: MenuBarItem) async -> Bool {
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
        let reaction = await ClickReactionVerifier.verify(against: snapshot)
        MenuBarItemManager.diagLog.debug(
            "pressInPlace: pressed \(item.logString) via \(ownPress ? "own bar" : "hosted"); reacted=\(reaction.didReact)"
        )
        return reaction.didReact
    }
}
