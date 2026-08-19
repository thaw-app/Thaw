//
//  TriggerFeatureFlags.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import SwiftUI

// MARK: - TriggerFeature

/// An individually toggleable menu bar item trigger capability.
///
/// Each feature gates both (a) whether its condition kind appears in the
/// trigger editor and (b) whether its backing monitor runs. Features are
/// independent of one another, so they can be enabled and debugged one at a
/// time from the Developer settings pane. Battery/power conditions are
/// always available and are intentionally not represented here.
enum TriggerFeature: String, CaseIterable, Identifiable {
    case frontmostApp
    case appRunning
    case network
    case vpn
    case wifiSSID
    case bluetooth
    case audioOutput
    case display
    case schedule
    case focusMode
    case location
    case lowPowerMode
    case thermalPressure
    case recordingDevices
    case scriptResult
    case imageComparison
    case compoundConditions
    case advancedOptions
    case invertAction

    var id: String {
        rawValue
    }

    /// A short title for the Developer pane.
    var title: String {
        switch self {
        case .frontmostApp: "Frontmost app"
        case .appRunning: "App running"
        case .network: "Network connectivity"
        case .vpn: "VPN active"
        case .wifiSSID: "Wi-Fi network (SSID)"
        case .bluetooth: "Bluetooth device"
        case .audioOutput: "Audio output device"
        case .display: "External display"
        case .schedule: "Time schedule"
        case .focusMode: "Focus / Do Not Disturb"
        case .location: "Location"
        case .lowPowerMode: "Low Power Mode"
        case .thermalPressure: "Thermal pressure"
        case .recordingDevices: "Camera / microphone in use"
        case .scriptResult: "Script result"
        case .imageComparison: "Menu bar icon changed"
        case .compoundConditions: "Combine conditions (AND / OR)"
        case .advancedOptions: "Advanced per-trigger options"
        case .invertAction: "Invert action (hide when met)"
        }
    }

    /// A one-line description for the Developer pane.
    var detail: String {
        switch self {
        case .frontmostApp: "Reveal an item only while a chosen app is frontmost."
        case .appRunning: "Reveal an item while a chosen app is running."
        case .network: "Reveal an item based on network connectivity."
        case .vpn: "Reveal an item while a VPN tunnel is active."
        case .wifiSSID: "Reveal an item while connected to a specific Wi-Fi network."
        case .bluetooth: "Reveal an item while a Bluetooth device is connected."
        case .audioOutput: "Reveal an item based on the current audio output device."
        case .display: "Reveal an item while an external display is connected."
        case .schedule: "Reveal an item during a time-of-day window."
        case .focusMode: "Reveal an item while a macOS Focus is active."
        case .location: "Reveal an item while you're near a saved place (uses Location)."
        case .lowPowerMode: "Reveal an item while macOS Low Power Mode is on."
        case .thermalPressure: "Reveal an item when the system is under thermal pressure."
        case .recordingDevices: "Reveal an item while the camera or microphone is in use."
        case .scriptResult: "Reveal an item based on a script's exit code or output (runs your script periodically)."
        case .imageComparison: "Reveal an item when a watched menu bar icon changes from a captured reference (uses screen capture)."
        case .compoundConditions: "Let a trigger combine several conditions with AND / OR."
        case .advancedOptions: "Show per-trigger options: a notification when it reveals and a custom delay."
        case .invertAction: "Allow triggers to hide (instead of reveal) when the condition is met."
        }
    }

    /// A status badge for features that need extra caution while testing.
    var statusBadge: String? {
        switch self {
        case .vpn, .audioOutput: "Untested"
        case .wifiSSID, .focusMode, .location, .scriptResult, .imageComparison: "Experimental"
        default: nil
        }
    }
}

// MARK: - TriggerFeatureFlagsManager

/// Persists and publishes the set of enabled ``TriggerFeature`` values.
///
/// Stored as a list of raw values under a single Defaults key so new
/// features can be added without a migration. Everything defaults to off
/// except battery/power, which is not a flag.
@MainActor
@Observable
final class TriggerFeatureFlagsManager {
    /// Invoked whenever the enabled feature set changes, so the triggers
    /// manager can re-evaluate. Replaces the Combine `objectWillChange`
    /// subscription this used before the settings layer moved to the
    /// `@Observable` macro.
    @ObservationIgnored
    private var changeHandlers = [() -> Void]()

    /// Registers a handler invoked whenever the enabled feature set changes.
    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    private var enabledRawValues: Set<String> {
        didSet {
            guard !suppressPersist else { return }
            persist()
            for handler in changeHandlers { handler() }
        }
    }

    /// Whether the emergency "All Trigger Features Off" item is shown in the
    /// menu bar dropdown. Defaults off so the dropdown stays uncluttered until
    /// the developer explicitly opts into the emergency escape hatch.
    var showsAllOffInMenuBarMenu = Defaults.bool(forKey: .showTriggerFeatureFlagsAllOffMenuItem) {
        didSet {
            Defaults.set(showsAllOffInMenuBarMenu, forKey: .showTriggerFeatureFlagsAllOffMenuItem)
        }
    }

    @ObservationIgnored
    private var suppressPersist = false

    init() {
        suppressPersist = true
        enabledRawValues = Self.load()
        suppressPersist = false
    }

    /// Returns whether the given feature is enabled.
    func isEnabled(_ feature: TriggerFeature) -> Bool {
        enabledRawValues.contains(feature.rawValue)
    }

    /// Whether any trigger feature flag is currently enabled.
    var hasEnabledFlags: Bool {
        !enabledRawValues.isEmpty
    }

    /// Enables or disables the given feature.
    func setEnabled(_ feature: TriggerFeature, _ isOn: Bool) {
        if isOn {
            enabledRawValues.insert(feature.rawValue)
        } else {
            enabledRawValues.remove(feature.rawValue)
        }
    }

    /// Disables every trigger feature flag.
    func disableAll() {
        enabledRawValues.removeAll()
    }

    /// A binding suitable for a SwiftUI toggle.
    func binding(for feature: TriggerFeature) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled(feature) ?? false },
            set: { [weak self] newValue in self?.setEnabled(feature, newValue) }
        )
    }

    private func persist() {
        Defaults.set(Array(enabledRawValues), forKey: .triggerFeatureFlags)
    }

    private static func load() -> Set<String> {
        let raw = Defaults.stringArray(forKey: .triggerFeatureFlags) ?? []
        return Set(raw)
    }
}
