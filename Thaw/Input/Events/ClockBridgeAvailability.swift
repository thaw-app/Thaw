//
//  ClockBridgeAvailability.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation

/// Whether the Clock and Notification Center bridge taps can ever be needed.
enum ClockBridgeAvailability {
    /// The bridge releases the restriction the Standard method holds. Native hiding holds none,
    /// so with it the taps would sit on every left press and drag in the system for nothing.
    nonisolated static func isPossible(engineIsOperational: Bool, nativeHidingActive: Bool) -> Bool {
        engineIsOperational && !nativeHidingActive
    }

    /// Whether the shortcut tap should be up. A key still held keeps it up, so its release is not lost.
    nonisolated static func wantsHotkeyTap(canBridge: Bool, hasHotkeys: Bool, hasHeldKeys: Bool) -> Bool {
        (canBridge && hasHotkeys) || hasHeldKeys
    }
}

extension HIDEventManager {
    /// A subscription that brings the bridge taps up or down when Native hiding starts or stops.
    func nativeHidingFollower() -> Set<AnyCancellable> {
        guard let appState else { return [] }
        let experiment = appState.menuBarManager.nativeAppHidingExperiment
        let task = Task { @MainActor [weak self] in
            for await _ in Observations({ experiment.isActive }) {
                guard let self else { return }
                synchronizeClockActivationTap()
                synchronizeNotificationCenterHotkeyTap()
            }
        }
        return [AnyCancellable { task.cancel() }]
    }

    /// Keeps the shortcut last read, which includes the system's default Fn-N, and logs a change.
    func updateNotificationCenterHotkeys(_ hotkeys: [SystemNotificationCenterHotkey]) {
        if hotkeys != notificationCenterHotkeys {
            Self.diagLog.info("Notification Center shortcut bindings updated: \(hotkeys.count) enabled")
        }
        notificationCenterHotkeys = hotkeys
    }
}
