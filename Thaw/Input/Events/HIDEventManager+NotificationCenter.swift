//
//  HIDEventManager+NotificationCenter.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import MenuBarModel

extension HIDEventManager {
    func enqueueNotificationCenterActivation(_ request: NotificationCenterActivation.Request) {
        appState?.menuBarManager.noteUserRevealOwnership()
        notificationCenterActivation.enqueue(request)
    }

    func performNotificationCenterActivation(_ request: NotificationCenterActivation.Request) async {
        guard let appState else { return }
        let controller = appState.menuBarManager.sectionController
        let events = switch request {
        case let .clock(point): NotificationCenterEventReplay.clockClick(at: point)
        case let .shortcut(hotkey): NotificationCenterEventReplay.shortcut(hotkey)
        }
        guard !events.isEmpty else { return }
        guard let lease = notificationCenterLease() else { return }
        await notificationCenterActivation.replay(
            begin: {
                guard controller.shouldBridgeClockActivation else { return .notRequired }
                let acquired = lease.begin()
                if acquired == .unavailable {
                    Self.diagLog.warning("Notification Center activation could not release concealment")
                }
                return acquired
            },
            restore: lease.restore,
            send: {
                for event in events {
                    event.post(tap: .cghidEventTap)
                }
                Self.diagLog.debug("Notification Center activation replayed without capture")
            }
        )
    }

    /// A release that ran to its bound is logged as a warning.
    func makeNotificationCenterActivation() -> NotificationCenterActivation {
        NotificationCenterActivation(
            activate: { [weak self] request in
                await self?.performNotificationCenterActivation(request)
            },
            report: { outcome in
                switch outcome {
                case .panelOpened, .panelClosed:
                    Self.diagLog.debug("Notification Center release ended: \(String(describing: outcome))")
                case .panelNeverOpened, .panelDidNotClose:
                    Self.diagLog.warning("Notification Center release ran to its bound: \(String(describing: outcome))")
                }
            }
        )
    }

    /// The one way concealment is released for an activation and put back:
    /// cover the bar, lift the restriction, and hold layout still meanwhile.
    private func notificationCenterLease() -> (begin: () -> NotificationCenterActivation.Lease, restore: () -> Void)? {
        guard let appState else { return nil }
        let controller = appState.menuBarManager.sectionController
        return (
            begin: {
                let cover = appState.menuBarManager.clockBridgeCover
                cover.show()
                guard controller.beginClockActivationBridge(scope: .global) else {
                    cover.hide(immediately: true)
                    return .unavailable
                }
                appState.itemManager.beginNotificationCenterLayoutSuspension()
                return .acquired
            },
            restore: {
                controller.endClockActivationBridge()
                appState.itemManager.endNotificationCenterLayoutSuspension()
                appState.menuBarManager.clockBridgeCover.hide()
            }
        )
    }

    /// Claims a physical Clock click while the restriction is held: the pair is
    /// consumed here and the activation replayed once concealment is released.
    func handleClockActivation(_ event: CGEvent) -> CGEvent? {
        guard !NotificationCenterEventReplay.isReplay(event) else { return event }

        if event.type == .leftMouseDragged, notificationCenterInput.hasClockPress {
            notificationCenterInput.dragClockPress(to: event.location)
            return nil
        }
        if event.type == .leftMouseUp, notificationCenterInput.hasClockPress {
            if let point = notificationCenterInput.endClockPress(at: event.location) {
                enqueueNotificationCenterActivation(.clock(point))
            }
            return nil
        }
        guard event.type == .leftMouseDown else { return event }
        notificationCenterInput.discardClockPress()
        guard isEnabled, let appState else { return event }
        let controller = appState.menuBarManager.sectionController
        guard controller.shouldBridgeClockActivation || notificationCenterActivation.isBusy else { return event }
        // No AX walk, display query, or capture runs in this synchronous tap.
        guard let clock = Self.systemClockItem(
            at: event.location,
            in: (onScreenItems?.items ?? []) + appState.itemManager.managedItems,
            menuBarBands: clockMenuBarBands
        ), controller.section(for: clock) == .visible, let lease = notificationCenterLease() else { return event }
        notificationCenterInput.beginClockPress(at: event.location, bounds: clock.bounds)
        // Release at mouse-down so the completed click replays with no added settle.
        notificationCenterActivation.prepareLease(begin: lease.begin, restore: lease.restore)
        return nil
    }

    /// Bridges the Notification Center shortcut while the assertion is held; other input passes through.
    func handleNotificationCenterHotkey(_ event: CGEvent) -> CGEvent? {
        if NotificationCenterEventReplay.isReplay(event) {
            return event
        }

        let hotkey = notificationCenterHotkeys.first { $0.matches(event) }
        let needsBridge = appState?.menuBarManager.sectionController.shouldBridgeClockActivation == true
            || notificationCenterActivation.isBusy
        let disposition = notificationCenterInput.key(
            type: event.type,
            code: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            matches: hotkey != nil,
            shouldBridge: isEnabled && needsBridge
        )
        switch disposition {
        case .passThrough:
            return event
        case .consume:
            return nil
        case .activate:
            if let hotkey {
                enqueueNotificationCenterActivation(.shortcut(hotkey))
            }
            return nil
        }
    }
}
