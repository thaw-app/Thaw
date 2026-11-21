//
//  ClockBridgeAvailability.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation

/// Whether the Clock and Notification Center bridge taps can ever be needed, and on which displays.
enum ClockBridgeAvailability {
    /// The bridge releases the restriction the Standard method holds. Native hiding holds none,
    /// so with it the taps would sit on every left press and drag in the system for nothing.
    nonisolated static func isPossible(engineIsOperational: Bool, nativeHidingActive: Bool) -> Bool {
        engineIsOperational && !nativeHidingActive
    }

    /// Whether a display gets a Clock band. A fullscreen Space on a display without a notch
    /// gets none: the app owns the top of the screen there, and the clock's last frame would
    /// take its clicks. With a notch the app sits below the camera housing, so the strip beside
    /// it only ever holds the menu bar when it drops down. Without a band there, a Clock click on
    /// the dropped-down bar reaches macOS while the restriction is held and cannot open the panel.
    nonisolated static func hasClockBand(showsFullscreenSpace: Bool, hasNotch: Bool) -> Bool {
        !showsFullscreenSpace || hasNotch
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
