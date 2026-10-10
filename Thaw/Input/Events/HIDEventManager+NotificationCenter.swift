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
        await notificationCenterActivation.replay(
            begin: {
                guard controller.shouldBridgeClockActivation else { return .notRequired }
                let cover = appState.menuBarManager.clockBridgeCover
                cover.show()
                guard controller.beginClockActivationBridge(scope: .global) else {
                    cover.hide(immediately: true)
                    Self.diagLog.warning("Notification Center activation could not release concealment")
                    return .unavailable
                }
                appState.itemManager.beginNotificationCenterLayoutSuspension()
                return .acquired
            },
            restore: {
                controller.endClockActivationBridge()
                appState.itemManager.endNotificationCenterLayoutSuspension()
                appState.menuBarManager.clockBridgeCover.hide()
            },
            send: {
                for event in events {
                    event.post(tap: .cghidEventTap)
                }
                Self.diagLog.debug("Notification Center activation replayed without capture")
            }
        )
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
