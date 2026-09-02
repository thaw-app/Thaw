//
//  EnergyModeMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SystemConfiguration

// MARK: - EnergyModeMonitor

/// Reads the current ``EnergyMode`` and observes changes to it.
///
/// macOS publishes the settings in force for the active power source under
/// `State:/IOKit/PowerManagement/CurrentSettings` in the dynamic store,
/// which is where the `HighPowerMode` flag — the one mode with no API — can
/// be read. Because that entry already switches contents when the machine
/// moves between battery and AC, the value read here is the effective mode
/// rather than a per-source preference.
///
/// Low Power Mode is taken from `ProcessInfo` rather than the same
/// dictionary: it is the documented source, and it changes through a
/// notification the state monitor already observes.
@MainActor
final class EnergyModeMonitor {
    /// The dynamic store entry holding the settings in force for the active
    /// power source.
    private static let currentSettingsKey = "State:/IOKit/PowerManagement/CurrentSettings" as CFString

    /// The key carrying High Power Mode within that entry. Present only on
    /// Macs that offer the mode, which is what ``isHighPowerModeSupported``
    /// keys off.
    private static let highPowerModeKey = "HighPowerMode"

    /// Whether this Mac offers High Power Mode.
    ///
    /// Read once: it is a property of the hardware, so it cannot change while
    /// the app runs.
    ///
    /// Presence of the key is the signal. That it is *absent* on Macs without
    /// the mode is inferred from `pmset`, which prints `powermode` only on
    /// machines that have it and `lowpowermode` elsewhere — it has been
    /// confirmed present on hardware that offers the mode, not confirmed
    /// absent on hardware that doesn't. If that inference is wrong the
    /// failure is benign: the picker offers High Power on a Mac that cannot
    /// enter it, and the condition simply never matches.
    static let isHighPowerModeSupported: Bool = currentSettings()?[highPowerModeKey] != nil

    private var store: SCDynamicStore?

    /// `nonisolated(unsafe)` so `deinit` can unregister it, matching
    /// ``PowerSourceMonitor``. Only ever touched on the main actor.
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?

    private var changeHandler: (() -> Void)?

    private let diagLog = DiagLog(category: "EnergyModeMonitor")

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    /// Reads the mode currently in effect.
    static func read() -> EnergyMode {
        // Low Power wins when both flags are set: macOS does not offer the
        // combination, but a stale High Power flag left behind by a mode
        // switch shouldn't outrank the documented reading.
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return .low
        }
        if (currentSettings()?[highPowerModeKey] as? NSNumber)?.intValue == 1 {
            return .high
        }
        return .automatic
    }

    /// Begins observing power management setting changes, invoking `handler`
    /// on the main run loop whenever they change. Safe to call more than
    /// once; a later call replaces the handler without re-registering.
    func start(onChange handler: @escaping () -> Void) {
        changeHandler = handler

        guard runLoopSource == nil else { return }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<EnergyModeMonitor>.fromOpaque(info).takeUnretainedValue()
            // Delivered on the run loop it was registered on (the main run
            // loop), but hop explicitly to keep the isolation contract clear.
            Task { @MainActor in
                monitor.changeHandler?()
            }
        }

        guard
            let store = SCDynamicStoreCreate(
                nil,
                "com.stonerl.Thaw.energyMode" as CFString,
                callback,
                &context
            )
        else {
            diagLog.warning("Failed to create dynamic store session for Energy Mode")
            return
        }

        guard
            SCDynamicStoreSetNotificationKeys(store, [Self.currentSettingsKey] as CFArray, nil),
            let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        else {
            diagLog.warning("Failed to observe power management settings for Energy Mode")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.store = store
        runLoopSource = source
    }

    /// Stops observing power management setting changes.
    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        store = nil
        changeHandler = nil
    }

    /// The session used for one-shot reads.
    ///
    /// Held rather than created per call: ``read`` runs on every power-state
    /// and thermal notification, and a dynamic store session is a port pair,
    /// not a free struct. Callback-free, so it is only ever polled.
    private static let readStore: SCDynamicStore? = SCDynamicStoreCreate(
        nil,
        "com.stonerl.Thaw.energyModeRead" as CFString,
        nil,
        nil
    )

    /// Copies the settings in force for the active power source.
    private static func currentSettings() -> [String: Any]? {
        guard let readStore else { return nil }
        return SCDynamicStoreCopyValue(readStore, currentSettingsKey) as? [String: Any]
    }
}
