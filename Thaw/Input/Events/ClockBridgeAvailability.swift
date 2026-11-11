//
//  ClockBridgeAvailability.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
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
}
