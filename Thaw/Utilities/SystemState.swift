//
//  SystemState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ScriptOutcome

/// The result of running a user script for a script-result trigger.
struct ScriptOutcome: Equatable {
    var exitCode: Int32
    var output: String
    /// Expected script-result tokens detected while output was streamed. This
    /// preserves condition semantics even when diagnostic output is capped.
    var matchedExpectedOutputs: Set<String> = []
}

// MARK: - SystemState

/// A snapshot of the system signals that menu bar item triggers evaluate
/// against. Every field is cheap to compare so the monitor can publish only
/// on real changes.
struct SystemState: Equatable {
    /// Battery / power source state.
    var power: PowerState

    /// Bundle identifier of the frontmost application, if any.
    var frontmostAppBundleID: String?

    /// Bundle identifiers of all running (regular) applications.
    var runningAppBundleIDs: Set<String>

    /// Whether the machine has general network connectivity.
    var isNetworkConnected: Bool

    /// Whether a VPN tunnel appears to be active.
    var isVPNActive: Bool

    /// The current Wi-Fi network name, if available (best-effort).
    var wifiSSID: String?

    /// Names of currently connected Bluetooth devices.
    var connectedBluetoothDeviceNames: Set<String>

    /// The name of the current default audio output device.
    var audioOutputDeviceName: String?

    /// The number of active displays.
    var screenCount: Int

    /// Whether at least one external (non-built-in) display is connected.
    var externalDisplayConnected: Bool

    /// Whether a macOS Focus / Do Not Disturb appears to be active
    /// (best-effort).
    var isFocusActive: Bool

    /// The active Thaw profile name requested by ``ThawFocusFilter``, or
    /// `nil` when no Thaw Focus Filter is currently applied. macOS does not
    /// expose the enclosing Focus's user-visible name through this API.
    var activeFocusModeName: String?

    /// The current latitude / longitude, when location updates are running.
    var currentLatitude: Double?
    var currentLongitude: Double?

    /// The macOS Energy Mode currently in effect.
    var energyMode: EnergyMode

    /// Whether macOS Low Power Mode is enabled.
    ///
    /// Read-only on purpose. A setter would have to invent a mode for
    /// `false`, and picking `.automatic` would silently destroy `.high` —
    /// assign ``energyMode`` instead.
    var isLowPowerMode: Bool {
        energyMode == .low
    }

    /// The current system thermal pressure.
    var thermalState: ProcessInfo.ThermalState

    /// Whether any camera is currently in use by some process.
    var isCameraInUse: Bool

    /// Whether any microphone is currently in use by some process.
    var isMicrophoneInUse: Bool

    /// Results of user scripts for script-result conditions, keyed by path.
    /// Populated by the triggers manager (not the monitor) before evaluation.
    var scriptOutcomes: [String: ScriptOutcome]

    /// Current perceptual image hashes of watched items for image-comparison
    /// conditions, keyed by item tag identifier. Populated by the manager.
    var imageHashes: [String: UInt64]

    /// Exact pixel hashes captured in the same pass as ``imageHashes``.
    var exactImageHashes: [String: UInt64]

    /// Identifiers of items currently blinking for attention.
    var itemsSeekingAttention: Set<String>

    init(
        power: PowerState = PowerState(batteryPercentage: nil, isOnACPower: true, isCharging: false),
        frontmostAppBundleID: String? = nil,
        runningAppBundleIDs: Set<String> = [],
        isNetworkConnected: Bool = true,
        isVPNActive: Bool = false,
        wifiSSID: String? = nil,
        connectedBluetoothDeviceNames: Set<String> = [],
        audioOutputDeviceName: String? = nil,
        screenCount: Int = 1,
        externalDisplayConnected: Bool = false,
        isFocusActive: Bool = false,
        activeFocusModeName: String? = nil,
        currentLatitude: Double? = nil,
        currentLongitude: Double? = nil,
        energyMode: EnergyMode = .automatic,
        thermalState: ProcessInfo.ThermalState = .nominal,
        isCameraInUse: Bool = false,
        isMicrophoneInUse: Bool = false,
        scriptOutcomes: [String: ScriptOutcome] = [:],
        imageHashes: [String: UInt64] = [:],
        exactImageHashes: [String: UInt64] = [:],
        itemsSeekingAttention: Set<String> = []
    ) {
        self.power = power
        self.frontmostAppBundleID = frontmostAppBundleID
        self.runningAppBundleIDs = runningAppBundleIDs
        self.isNetworkConnected = isNetworkConnected
        self.isVPNActive = isVPNActive
        self.wifiSSID = wifiSSID
        self.connectedBluetoothDeviceNames = connectedBluetoothDeviceNames
        self.audioOutputDeviceName = audioOutputDeviceName
        self.screenCount = screenCount
        self.externalDisplayConnected = externalDisplayConnected
        self.isFocusActive = isFocusActive
        self.activeFocusModeName = activeFocusModeName
        self.currentLatitude = currentLatitude
        self.currentLongitude = currentLongitude
        self.energyMode = energyMode
        self.thermalState = thermalState
        self.isCameraInUse = isCameraInUse
        self.isMicrophoneInUse = isMicrophoneInUse
        self.scriptOutcomes = scriptOutcomes
        self.imageHashes = imageHashes
        self.exactImageHashes = exactImageHashes
        self.itemsSeekingAttention = itemsSeekingAttention
    }
}
