//
//  MenuBarItemTrigger.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreLocation
import Foundation

// MARK: - ThermalLevel

/// A user-selectable thermal-pressure threshold, mapped to
/// `ProcessInfo.ThermalState` raw values (nominal = 0).
enum ThermalLevel: Int, Codable, Hashable, CaseIterable, Identifiable {
    case fair = 1
    case serious = 2
    case critical = 3

    var id: Int {
        rawValue
    }

    var displayString: String {
        switch self {
        case .fair: "Fair or higher"
        case .serious: "Serious or higher"
        case .critical: "Critical"
        }
    }
}

// MARK: - EnergyModeMatch

/// A user-selectable Energy Mode predicate.
///
/// macOS reports three mutually exclusive modes (``EnergyMode``), but the
/// question worth asking is often "not Low Power", which covers the two
/// remaining modes at once. The predicate set is therefore deliberately
/// wider than the state set.
enum EnergyModeMatch: String, Codable, Hashable, CaseIterable, Identifiable {
    case low
    case notLow
    case automatic
    case high

    var id: String {
        rawValue
    }

    var displayString: String {
        switch self {
        case .low: "Low Power"
        case .notLow: "Not Low Power"
        case .automatic: "Automatic"
        case .high: "High Power"
        }
    }

    /// A short human-readable summary, used to build a default trigger name.
    var summary: String {
        switch self {
        case .low: "Low Power Mode is on"
        case .notLow: "Low Power Mode is off"
        case .automatic: "Energy Mode is Automatic"
        case .high: "Energy Mode is High Power"
        }
    }

    /// Whether the given mode satisfies this predicate.
    func matches(_ mode: EnergyMode) -> Bool {
        switch self {
        case .low: mode == .low
        case .notLow: mode != .low
        case .automatic: mode == .automatic
        case .high: mode == .high
        }
    }

    /// The predicates offered in the settings picker.
    ///
    /// ``high`` is dropped on Macs that don't offer High Power Mode, where
    /// it could never be satisfied. An existing selection is not filtered
    /// here — the editor keeps a trigger's own current value visible the
    /// same way it does for a disabled feature flag.
    static func selectableCases(highPowerModeSupported: Bool) -> [EnergyModeMatch] {
        allCases.filter { $0 != .high || highPowerModeSupported }
    }
}

// MARK: - ScheduleWeekday

/// A calendar weekday, using the same numeric values as
/// `Calendar.Component.weekday` (Sunday = 1).
enum ScheduleWeekday: Int, Codable, Hashable, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int {
        rawValue
    }

    var shortTitle: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    var previous: ScheduleWeekday {
        ScheduleWeekday(rawValue: rawValue == Self.sunday.rawValue ? Self.saturday.rawValue : rawValue - 1) ?? .sunday
    }

    static var everyDay: Set<ScheduleWeekday> {
        Set(allCases)
    }

    static func weekday(for date: Date, calendar: Calendar = .current) -> ScheduleWeekday {
        let value = calendar.component(.weekday, from: date)
        return ScheduleWeekday(rawValue: value) ?? .sunday
    }
}

// MARK: - TriggerCondition

/// A condition that decides whether a ``MenuBarItemTrigger`` is currently
/// satisfied, evaluated against a ``SystemState`` snapshot.
///
/// New condition kinds can be added as cases without changing the
/// surrounding trigger plumbing; each is independently gated by a
/// ``TriggerFeature`` flag (battery/power conditions are always available).
enum TriggerCondition: Codable, Hashable {
    // Power
    case batteryBelow(percentage: Double)
    case batteryAtOrAbove(percentage: Double)
    case onACPower
    case onBatteryPower
    case charging

    // Applications
    case frontmostApp(bundleID: String)
    case appRunning(bundleID: String)

    // Network
    case networkConnected
    case vpnActive
    case wifiSSID(name: String)

    // Devices
    case bluetoothConnected(name: String)
    case audioOutput(contains: String)
    case externalDisplayConnected

    // Time / Focus
    case schedule(startMinutes: Int, endMinutes: Int)
    case weeklySchedule(startMinutes: Int, endMinutes: Int, weekdays: Set<ScheduleWeekday>)
    case focusActive
    case focusMode(name: String)

    /// Location
    case nearLocation(latitude: Double, longitude: Double, radiusMeters: Double, label: String)

    /// System load
    case energyMode(EnergyModeMatch)
    /// Legacy spelling of `.energyMode(.low)`, kept so triggers saved before
    /// Energy Mode grew its Automatic and High Power options keep decoding.
    case lowPowerMode
    case thermalPressure(atLeast: ThermalLevel)

    // Recording devices
    case cameraInUse
    case microphoneInUse

    /// Script
    case scriptResult(path: String, expectedOutput: String)

    /// Image comparison
    case imageChanged(itemIdentifier: String, referenceHash: UInt64?)

    /// Returns whether the condition is satisfied by the given state at the
    /// given time.
    func isSatisfied(state: SystemState, now: Date = Date()) -> Bool {
        switch self {
        case let .batteryBelow(percentage):
            guard let level = state.power.batteryPercentage else { return false }
            return level < percentage
        case let .batteryAtOrAbove(percentage):
            guard let level = state.power.batteryPercentage else { return false }
            return level >= percentage
        case .onACPower:
            return state.power.isOnACPower
        case .onBatteryPower:
            return !state.power.isOnACPower
        case .charging:
            return state.power.isCharging
        case let .frontmostApp(bundleID):
            return !bundleID.isEmpty && state.frontmostAppBundleID == bundleID
        case let .appRunning(bundleID):
            return !bundleID.isEmpty && state.runningAppBundleIDs.contains(bundleID)
        case .networkConnected:
            return state.isNetworkConnected
        case .vpnActive:
            return state.isVPNActive
        case let .wifiSSID(name):
            return !name.isEmpty && state.wifiSSID?.caseInsensitiveCompare(name) == .orderedSame
        case let .bluetoothConnected(name):
            return !name.isEmpty && state.connectedBluetoothDeviceNames.contains {
                $0.localizedCaseInsensitiveContains(name)
            }
        case let .audioOutput(substring):
            return !substring.isEmpty && (state.audioOutputDeviceName?.localizedCaseInsensitiveContains(substring) ?? false)
        case .externalDisplayConnected:
            return state.externalDisplayConnected
        case let .schedule(start, end):
            return Self.isWithinSchedule(now: now, startMinutes: start, endMinutes: end)
        case let .weeklySchedule(start, end, weekdays):
            return Self.isWithinSchedule(now: now, startMinutes: start, endMinutes: end, weekdays: weekdays)
        case .focusActive:
            return state.isFocusActive
        case let .focusMode(name):
            return !name.isEmpty
                && state.activeFocusModeName?.caseInsensitiveCompare(name) == .orderedSame
        case let .nearLocation(latitude, longitude, radiusMeters, _):
            guard
                let currentLat = state.currentLatitude,
                let currentLon = state.currentLongitude,
                radiusMeters > 0
            else {
                return false
            }
            let here = CLLocation(latitude: currentLat, longitude: currentLon)
            let target = CLLocation(latitude: latitude, longitude: longitude)
            return here.distance(from: target) <= radiusMeters
        case let .energyMode(match):
            return match.matches(state.energyMode)
        case .lowPowerMode:
            return state.energyMode == .low
        case let .thermalPressure(level):
            return state.thermalState.rawValue >= level.rawValue
        case .cameraInUse:
            return state.isCameraInUse
        case .microphoneInUse:
            return state.isMicrophoneInUse
        case let .scriptResult(path, expectedOutput):
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let outcome = state.scriptOutcomes[normalizedPath] else { return false }
            if expectedOutput.isEmpty {
                return outcome.exitCode == 0
            }
            return outcome.matchedExpectedOutputs.contains(expectedOutput) ||
                outcome.output.localizedCaseInsensitiveContains(expectedOutput)
        case let .imageChanged(itemIdentifier, referenceHash):
            guard let referenceHash, let current = state.imageHashes[itemIdentifier] else { return false }
            return ImageHashing.hammingDistance(current, referenceHash) > ImageHashing.changeThreshold
        }
    }

    /// A short human-readable summary of the condition, used to build a
    /// smart default trigger name (e.g. "Battery is below 20%").
    var summary: String {
        switch self {
        case let .batteryBelow(percentage):
            return "Battery is below \(Int(percentage.rounded()))%"
        case let .batteryAtOrAbove(percentage):
            return "Battery is at or above \(Int(percentage.rounded()))%"
        case .onACPower:
            return "Connected to power"
        case .onBatteryPower:
            return "Running on battery"
        case .charging:
            return "Battery is charging"
        case let .frontmostApp(bundleID):
            return bundleID.isEmpty ? "An app is frontmost" : "\(Self.appDisplayName(bundleID)) is frontmost"
        case let .appRunning(bundleID):
            return bundleID.isEmpty ? "An app is running" : "\(Self.appDisplayName(bundleID)) is running"
        case .networkConnected:
            return "Network is connected"
        case .vpnActive:
            return "VPN is active"
        case let .wifiSSID(name):
            return name.isEmpty ? "On a Wi-Fi network" : "On Wi-Fi “\(name)”"
        case let .bluetoothConnected(name):
            return name.isEmpty ? "A Bluetooth device is connected" : "“\(name)” is connected"
        case let .audioOutput(substring):
            return substring.isEmpty ? "Audio output device" : "Audio output is “\(substring)”"
        case .externalDisplayConnected:
            return "External display is connected"
        case let .schedule(start, end):
            return "Between \(Self.clockString(start)) and \(Self.clockString(end))"
        case let .weeklySchedule(start, end, weekdays):
            let window = "Between \(Self.clockString(start)) and \(Self.clockString(end))"
            let days = Self.weekdaySummary(weekdays)
            return days == "every day" ? window : "\(window) on \(days)"
        case .focusActive:
            return "A Focus is active"
        case let .focusMode(name):
            return name.isEmpty ? "A Focus mode is active" : "Focus Filter profile is “\(name)”"
        case let .nearLocation(_, _, radiusMeters, label):
            let place = label.isEmpty ? "a saved location" : "“\(label)”"
            return "Within \(Int(radiusMeters))m of \(place)"
        case let .energyMode(match):
            return match.summary
        case .lowPowerMode:
            return EnergyModeMatch.low.summary
        case let .thermalPressure(level):
            return "Thermal pressure is \(level.displayString.lowercased())"
        case .cameraInUse:
            return "Camera is in use"
        case .microphoneInUse:
            return "Microphone is in use"
        case let .scriptResult(path, expectedOutput):
            let name = path.isEmpty ? "a script" : ((path as NSString).lastPathComponent)
            return expectedOutput.isEmpty ? "\(name) exits 0" : "\(name) outputs “\(expectedOutput)”"
        case let .imageChanged(_, referenceHash):
            return referenceHash == nil ? "An icon changed (capture a reference)" : "A watched icon changed"
        }
    }

    /// Best-effort friendly app name from a bundle id (falls back to the
    /// bundle id when the app can't be located).
    private static func appDisplayName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = url.deletingPathExtension().lastPathComponent
            if !name.isEmpty { return name }
        }
        return bundleID
    }

    /// Formats minutes-from-midnight as a short clock string (e.g. "9:00 AM").
    private static func clockString(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Whether `now` falls within the daily window `[start, end)`, handling
    /// windows that wrap past midnight.
    static func isWithinSchedule(now: Date, startMinutes: Int, endMinutes: Int) -> Bool {
        isWithinSchedule(now: now, startMinutes: startMinutes, endMinutes: endMinutes, weekdays: ScheduleWeekday.everyDay)
    }

    /// Whether `now` falls within a weekly schedule. For windows that wrap
    /// past midnight, the selected weekday is the day the window starts.
    static func isWithinSchedule(
        now: Date,
        startMinutes: Int,
        endMinutes: Int,
        weekdays: Set<ScheduleWeekday>
    ) -> Bool {
        guard startMinutes != endMinutes else { return false }
        guard !weekdays.isEmpty else { return false }

        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let weekday = ScheduleWeekday.weekday(for: now)

        if startMinutes < endMinutes {
            return weekdays.contains(weekday) && current >= startMinutes && current < endMinutes
        }

        // Window wraps midnight (e.g. 22:00–06:00).
        if current >= startMinutes {
            return weekdays.contains(weekday)
        }
        if current < endMinutes {
            return weekdays.contains(weekday.previous)
        }
        return false
    }

    private static func weekdaySummary(_ weekdays: Set<ScheduleWeekday>) -> String {
        if weekdays == ScheduleWeekday.everyDay { return "every day" }
        if weekdays.isEmpty { return "no days" }
        return ScheduleWeekday.allCases
            .filter { weekdays.contains($0) }
            .map(\.shortTitle)
            .joined(separator: ", ")
    }
}

// MARK: - TriggerConditionKind

/// The user-selectable kind of a ``TriggerCondition``, used to drive the
/// settings UI independently of any value the condition carries.
enum TriggerConditionKind: String, CaseIterable, Identifiable {
    case batteryBelow
    case batteryAtOrAbove
    case onACPower
    case onBatteryPower
    case charging
    case frontmostApp
    case appRunning
    case networkConnected
    case vpnActive
    case wifiSSID
    case bluetoothConnected
    case audioOutput
    case externalDisplay
    case schedule
    case focusActive
    case focusModeNamed
    case nearLocation
    case energyMode
    case thermalPressure
    case cameraInUse
    case microphoneInUse
    case scriptResult
    case imageChanged

    var id: String {
        rawValue
    }

    /// A human-readable description for the settings interface.
    var displayString: String {
        switch self {
        case .batteryBelow: "Battery is below"
        case .batteryAtOrAbove: "Battery is at or above"
        case .onACPower: "Connected to power"
        case .onBatteryPower: "Running on battery"
        case .charging: "Battery is charging"
        case .frontmostApp: "App is frontmost"
        case .appRunning: "App is running"
        case .networkConnected: "Network is connected"
        case .vpnActive: "VPN is active"
        case .wifiSSID: "Connected to Wi-Fi network"
        case .bluetoothConnected: "Bluetooth device is connected"
        case .audioOutput: "Audio output device"
        case .externalDisplay: "External display is connected"
        case .schedule: "During time window"
        case .focusActive: "Any Focus is active"
        case .focusModeNamed: "Focus Filter profile is"
        case .nearLocation: "Near a location"
        case .energyMode: "Energy Mode is"
        case .thermalPressure: "Thermal pressure"
        case .cameraInUse: "Camera is in use"
        case .microphoneInUse: "Microphone is in use"
        case .scriptResult: "Script result"
        case .imageChanged: "Menu bar icon changed"
        }
    }

    /// Whether this kind carries a battery percentage threshold.
    var usesPercentage: Bool {
        self == .batteryBelow || self == .batteryAtOrAbove
    }

    /// How long a flipped condition of this kind must hold before its item
    /// is moved. Battery percentage thresholds use a long settle to absorb
    /// readings that jitter around the threshold; discrete sources (app
    /// focus, network, etc.) use a short settle so they feel responsive
    /// while still coalescing rapid transients like quick app switching.
    var settleInterval: Duration {
        switch self {
        case .batteryBelow, .batteryAtOrAbove: .seconds(6)
        case .frontmostApp: .milliseconds(1500)
        case .appRunning: .milliseconds(500)
        case .scriptResult, .imageChanged: .seconds(2)
        default: .seconds(1)
        }
    }

    /// The editor UI this kind needs.
    var editor: TriggerConditionEditor {
        switch self {
        case .batteryBelow, .batteryAtOrAbove: .percentage
        case .frontmostApp, .appRunning: .appPicker
        case .wifiSSID: .text(prompt: "Network name")
        case .bluetoothConnected: .bluetoothPicker
        case .audioOutput: .text(prompt: "Device name contains")
        case .focusModeNamed: .text(prompt: "Thaw profile name (e.g. Work Layout)")
        case .schedule: .timeRange
        case .nearLocation: .location
        case .energyMode: .energyMode
        case .thermalPressure: .thermalLevel
        case .scriptResult: .script
        case .imageChanged: .imageComparison
        case .onACPower, .onBatteryPower, .charging, .networkConnected,
             .vpnActive, .externalDisplay, .focusActive,
             .cameraInUse, .microphoneInUse:
            .none
        }
    }

    /// The feature flag that must be enabled for this kind to be available,
    /// or `nil` for always-available power conditions.
    var requiredFeature: TriggerFeature? {
        switch self {
        case .batteryBelow, .batteryAtOrAbove, .onACPower, .onBatteryPower, .charging:
            nil
        case .frontmostApp: .frontmostApp
        case .appRunning: .appRunning
        case .networkConnected: .network
        case .vpnActive: .vpn
        case .wifiSSID: .wifiSSID
        case .bluetoothConnected: .bluetooth
        case .audioOutput: .audioOutput
        case .externalDisplay: .display
        case .schedule: .schedule
        case .focusActive: .focusMode
        case .focusModeNamed: .focusMode
        case .nearLocation: .location
        case .energyMode: .energyMode
        case .thermalPressure: .thermalPressure
        case .cameraInUse: .recordingDevices
        case .microphoneInUse: .recordingDevices
        case .scriptResult: .scriptResult
        case .imageChanged: .imageComparison
        }
    }
}

/// The kind of inline editor a condition needs in the settings UI.
enum TriggerConditionEditor: Equatable {
    case none
    case percentage
    case appPicker
    case text(prompt: String)
    case timeRange
    case location
    case bluetoothPicker
    case energyMode
    case thermalLevel
    case script
    case imageComparison
}

// MARK: - TriggerCondition <-> Kind

extension TriggerCondition {
    /// The kind of this condition.
    var kind: TriggerConditionKind {
        switch self {
        case .batteryBelow: .batteryBelow
        case .batteryAtOrAbove: .batteryAtOrAbove
        case .onACPower: .onACPower
        case .onBatteryPower: .onBatteryPower
        case .charging: .charging
        case .frontmostApp: .frontmostApp
        case .appRunning: .appRunning
        case .networkConnected: .networkConnected
        case .vpnActive: .vpnActive
        case .wifiSSID: .wifiSSID
        case .bluetoothConnected: .bluetoothConnected
        case .audioOutput: .audioOutput
        case .externalDisplayConnected: .externalDisplay
        case .schedule, .weeklySchedule: .schedule
        case .focusActive: .focusActive
        case .focusMode: .focusModeNamed
        case .nearLocation: .nearLocation
        case .energyMode, .lowPowerMode: .energyMode
        case .thermalPressure: .thermalPressure
        case .cameraInUse: .cameraInUse
        case .microphoneInUse: .microphoneInUse
        case .scriptResult: .scriptResult
        case .imageChanged: .imageChanged
        }
    }

    /// The battery percentage threshold, when this condition carries one.
    var percentage: Double? {
        switch self {
        case let .batteryBelow(percentage), let .batteryAtOrAbove(percentage): percentage
        default: nil
        }
    }

    /// The bundle identifier, for application conditions.
    var bundleID: String? {
        switch self {
        case let .frontmostApp(bundleID), let .appRunning(bundleID): bundleID
        default: nil
        }
    }

    /// The free-text value, for text conditions.
    var text: String? {
        switch self {
        case let .wifiSSID(name), let .bluetoothConnected(name), let .audioOutput(name), let .focusMode(name): name
        default: nil
        }
    }

    /// The schedule window in minutes-from-midnight, for schedule conditions.
    var scheduleWindow: (start: Int, end: Int)? {
        switch self {
        case let .schedule(start, end): (start, end)
        case let .weeklySchedule(start, end, _): (start, end)
        default: nil
        }
    }

    /// The selected weekdays for schedule conditions.
    var scheduleWeekdays: Set<ScheduleWeekday>? {
        switch self {
        case .schedule:
            ScheduleWeekday.everyDay
        case let .weeklySchedule(_, _, weekdays):
            weekdays
        default:
            nil
        }
    }

    /// The saved location, for the location condition.
    var locationValue: (latitude: Double, longitude: Double, radiusMeters: Double, label: String)? {
        switch self {
        case let .nearLocation(latitude, longitude, radiusMeters, label):
            (latitude, longitude, radiusMeters, label)
        default:
            nil
        }
    }

    /// The Energy Mode predicate, for the energy-mode condition.
    var energyModeMatch: EnergyModeMatch? {
        switch self {
        case let .energyMode(match): match
        case .lowPowerMode: .low
        default: nil
        }
    }

    /// The thermal threshold, for the thermal-pressure condition.
    var thermalLevel: ThermalLevel? {
        switch self {
        case let .thermalPressure(level): level
        default: nil
        }
    }

    /// The script path and expected output, for the script-result condition.
    var scriptValue: (path: String, expectedOutput: String)? {
        switch self {
        case let .scriptResult(path, expectedOutput): (path, expectedOutput)
        default: nil
        }
    }

    /// The watched item and reference hash, for the image-comparison condition.
    var imageValue: (itemIdentifier: String, referenceHash: UInt64?)? {
        switch self {
        case let .imageChanged(itemIdentifier, referenceHash): (itemIdentifier, referenceHash)
        default: nil
        }
    }

    /// Builds the default condition for the given kind.
    static func defaultCondition(for kind: TriggerConditionKind) -> TriggerCondition {
        switch kind {
        case .batteryBelow: .batteryBelow(percentage: 20)
        case .batteryAtOrAbove: .batteryAtOrAbove(percentage: 80)
        case .onACPower: .onACPower
        case .onBatteryPower: .onBatteryPower
        case .charging: .charging
        case .frontmostApp: .frontmostApp(bundleID: "")
        case .appRunning: .appRunning(bundleID: "")
        case .networkConnected: .networkConnected
        case .vpnActive: .vpnActive
        case .wifiSSID: .wifiSSID(name: "")
        case .bluetoothConnected: .bluetoothConnected(name: "")
        case .audioOutput: .audioOutput(contains: "")
        case .externalDisplay: .externalDisplayConnected
        case .schedule: .weeklySchedule(startMinutes: 9 * 60, endMinutes: 17 * 60, weekdays: ScheduleWeekday.everyDay)
        case .focusActive: .focusActive
        case .focusModeNamed: .focusMode(name: "")
        case .nearLocation: .nearLocation(latitude: 0, longitude: 0, radiusMeters: 150, label: "")
        case .energyMode: .energyMode(.low)
        case .thermalPressure: .thermalPressure(atLeast: .serious)
        case .cameraInUse: .cameraInUse
        case .microphoneInUse: .microphoneInUse
        case .scriptResult: .scriptResult(path: "", expectedOutput: "")
        case .imageChanged: .imageChanged(itemIdentifier: "", referenceHash: nil)
        }
    }

    /// Converts to the given kind, preserving a compatible carried value
    /// (percentage, bundle id, text, or schedule) where possible.
    static func make(kind: TriggerConditionKind, preserving old: TriggerCondition) -> TriggerCondition {
        switch kind {
        case .batteryBelow: .batteryBelow(percentage: old.percentage ?? 20)
        case .batteryAtOrAbove: .batteryAtOrAbove(percentage: old.percentage ?? 80)
        case .frontmostApp: .frontmostApp(bundleID: old.bundleID ?? "")
        case .appRunning: .appRunning(bundleID: old.bundleID ?? "")
        case .wifiSSID: .wifiSSID(name: old.text ?? "")
        case .bluetoothConnected: .bluetoothConnected(name: old.text ?? "")
        case .audioOutput: .audioOutput(contains: old.text ?? "")
        case .focusModeNamed: .focusMode(name: old.text ?? "")
        case .schedule:
            if let window = old.scheduleWindow {
                .weeklySchedule(
                    startMinutes: window.start,
                    endMinutes: window.end,
                    weekdays: old.scheduleWeekdays ?? ScheduleWeekday.everyDay
                )
            } else {
                .weeklySchedule(startMinutes: 9 * 60, endMinutes: 17 * 60, weekdays: ScheduleWeekday.everyDay)
            }
        case .energyMode: .energyMode(old.energyModeMatch ?? .low)
        case .thermalPressure: .thermalPressure(atLeast: old.thermalLevel ?? .serious)
        case .scriptResult:
            old.scriptValue.map { TriggerCondition.scriptResult(path: $0.path, expectedOutput: $0.expectedOutput) }
                ?? .scriptResult(path: "", expectedOutput: "")
        case .imageChanged:
            old.imageValue.map { TriggerCondition.imageChanged(itemIdentifier: $0.itemIdentifier, referenceHash: $0.referenceHash) }
                ?? .imageChanged(itemIdentifier: "", referenceHash: nil)
        case .onACPower, .onBatteryPower, .charging, .networkConnected,
             .vpnActive, .externalDisplay, .focusActive, .nearLocation,
             .cameraInUse, .microphoneInUse:
            defaultCondition(for: kind)
        }
    }

    /// Returns a copy with the battery percentage replaced.
    func withPercentage(_ value: Double) -> TriggerCondition {
        switch self {
        case .batteryBelow: .batteryBelow(percentage: value)
        case .batteryAtOrAbove: .batteryAtOrAbove(percentage: value)
        default: self
        }
    }

    /// Returns a copy with the bundle identifier replaced.
    func withBundleID(_ value: String) -> TriggerCondition {
        switch self {
        case .frontmostApp: .frontmostApp(bundleID: value)
        case .appRunning: .appRunning(bundleID: value)
        default: self
        }
    }

    /// Returns a copy with the free-text value replaced.
    func withText(_ value: String) -> TriggerCondition {
        switch self {
        case .wifiSSID: .wifiSSID(name: value)
        case .bluetoothConnected: .bluetoothConnected(name: value)
        case .audioOutput: .audioOutput(contains: value)
        case .focusMode: .focusMode(name: value)
        default: self
        }
    }

    /// Returns a copy with the schedule window replaced.
    func withSchedule(start: Int, end: Int) -> TriggerCondition {
        switch self {
        case .schedule:
            .weeklySchedule(startMinutes: start, endMinutes: end, weekdays: ScheduleWeekday.everyDay)
        case let .weeklySchedule(_, _, weekdays):
            .weeklySchedule(startMinutes: start, endMinutes: end, weekdays: weekdays)
        default: self
        }
    }

    /// Returns a copy with the selected schedule weekdays replaced.
    func withScheduleWeekdays(_ weekdays: Set<ScheduleWeekday>) -> TriggerCondition {
        switch self {
        case let .schedule(start, end):
            .weeklySchedule(startMinutes: start, endMinutes: end, weekdays: weekdays)
        case let .weeklySchedule(start, end, _):
            .weeklySchedule(startMinutes: start, endMinutes: end, weekdays: weekdays)
        default:
            self
        }
    }

    /// Returns a copy of the script condition with the path replaced.
    func withScriptPath(_ path: String) -> TriggerCondition {
        guard case let .scriptResult(_, expectedOutput) = self else { return self }
        return .scriptResult(path: path, expectedOutput: expectedOutput)
    }

    /// Returns a copy of the script condition with the expected output replaced.
    func withScriptExpectedOutput(_ expectedOutput: String) -> TriggerCondition {
        guard case let .scriptResult(path, _) = self else { return self }
        return .scriptResult(path: path, expectedOutput: expectedOutput)
    }

    /// Returns a copy of the image condition with the watched item replaced
    /// (clearing the reference hash, since it no longer applies).
    func withImageItem(_ itemIdentifier: String) -> TriggerCondition {
        guard case .imageChanged = self else { return self }
        return .imageChanged(itemIdentifier: itemIdentifier, referenceHash: nil)
    }

    /// Returns a copy of the image condition with the reference hash replaced.
    func withImageReferenceHash(_ referenceHash: UInt64) -> TriggerCondition {
        guard case let .imageChanged(itemIdentifier, _) = self else { return self }
        return .imageChanged(itemIdentifier: itemIdentifier, referenceHash: referenceHash)
    }

    /// Returns a copy with the Energy Mode predicate replaced.
    func withEnergyMode(_ match: EnergyModeMatch) -> TriggerCondition {
        switch self {
        case .energyMode, .lowPowerMode: .energyMode(match)
        default: self
        }
    }

    /// Returns a copy with the thermal threshold replaced.
    func withThermalLevel(_ level: ThermalLevel) -> TriggerCondition {
        switch self {
        case .thermalPressure: .thermalPressure(atLeast: level)
        default: self
        }
    }

    /// Returns a copy of the location condition with selected fields replaced.
    func withLocation(
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double? = nil,
        label: String? = nil
    ) -> TriggerCondition {
        guard case let .nearLocation(lat, lon, radius, currentLabel) = self else { return self }
        return .nearLocation(
            latitude: latitude ?? lat,
            longitude: longitude ?? lon,
            radiusMeters: radiusMeters ?? radius,
            label: label ?? currentLabel
        )
    }
}

// MARK: - TriggerTargetItem

/// An additional menu bar item moved by a trigger alongside its primary item.
struct TriggerTargetItem: Codable, Hashable {
    var identifier: String
    var displayName: String
    /// Stable namespace/title identity captured from the selected live tag.
    /// Lets a trigger safely follow an instance-index change without parsing
    /// a free-form title string.
    var baseIdentifier: String?

    init(identifier: String = "", displayName: String = "", baseIdentifier: String? = nil) {
        self.identifier = identifier
        self.displayName = displayName
        self.baseIdentifier = baseIdentifier
    }
}

// MARK: - TriggerCombinator

/// How a trigger's multiple conditions are combined.
enum TriggerCombinator: String, Codable, Hashable, CaseIterable, Identifiable {
    case all
    case any
    /// Satisfied only when no condition is. Spelled `noneOf` rather than
    /// `none` so it can never be confused with `Optional.none` at a use site;
    /// the raw value stays `"none"` for readability in stored triggers.
    case noneOf = "none"

    var id: String {
        rawValue
    }

    var displayString: String {
        switch self {
        case .all: "All of"
        case .any: "Any of"
        case .noneOf: "None of"
        }
    }

    /// Prefix for a joined multi-condition summary, where the joiner alone
    /// would describe the wrong relationship.
    var summaryPrefix: String {
        switch self {
        case .all, .any: ""
        case .noneOf: "None of: "
        }
    }

    /// The phrase used to join condition summaries.
    var joiner: String {
        switch self {
        case .all: " and "
        case .any, .noneOf: " or "
        }
    }
}

// MARK: - MenuBarItemTrigger

/// A user-defined rule that conditionally reveals or hides a single menu
/// bar item based on a ``TriggerCondition``.
///
/// When the condition becomes satisfied, the target item is moved into
/// ``revealSection``; when it is no longer satisfied, the item is returned
/// to ``hideSection``. When ``invert`` is `true`, the reveal/hide roles
/// swap, so the item is hidden while the condition is met.
struct MenuBarItemTrigger: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var itemIdentifier: String
    var itemDisplayName: String
    /// Stable namespace/title identity captured with the primary target.
    /// Older persisted triggers decode this as nil and remain exact-match only
    /// until the user selects the item again.
    var itemBaseIdentifier: String?

    /// Additional items moved alongside the primary item (advanced option).
    var additionalItems: [TriggerTargetItem]

    var revealSection: MenuBarSection.Name
    var hideSection: MenuBarSection.Name
    var condition: TriggerCondition

    /// Extra conditions combined with ``condition`` via ``combinator``.
    /// Gated by the `compoundConditions` feature flag in the UI.
    var additionalConditions: [TriggerCondition]

    /// How ``condition`` and ``additionalConditions`` are combined.
    var combinator: TriggerCombinator

    /// When `true`, the item is hidden (not revealed) while the conditions
    /// are satisfied. Gated by the `invertAction` feature flag in the UI.
    var invert: Bool

    /// When `true`, posts a notification when this trigger reveals its item.
    var notifyOnReveal: Bool

    /// Overrides the debounce settle (seconds) before a flip is applied.
    /// `nil` uses the per-condition default.
    var settleSecondsOverride: Double?

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        itemIdentifier: String = "",
        itemDisplayName: String = "",
        itemBaseIdentifier: String? = nil,
        additionalItems: [TriggerTargetItem] = [],
        revealSection: MenuBarSection.Name = .visible,
        hideSection: MenuBarSection.Name = .hidden,
        condition: TriggerCondition = .batteryBelow(percentage: 20),
        additionalConditions: [TriggerCondition] = [],
        combinator: TriggerCombinator = .all,
        invert: Bool = false,
        notifyOnReveal: Bool = false,
        settleSecondsOverride: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.itemIdentifier = itemIdentifier
        self.itemDisplayName = itemDisplayName
        self.itemBaseIdentifier = itemBaseIdentifier
        self.additionalItems = additionalItems
        self.revealSection = revealSection
        self.hideSection = hideSection
        self.condition = condition
        self.additionalConditions = additionalConditions
        self.combinator = combinator
        self.invert = invert
        self.notifyOnReveal = notifyOnReveal
        self.settleSecondsOverride = settleSecondsOverride
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, itemIdentifier, itemDisplayName, itemBaseIdentifier
        case revealSection, hideSection, condition, invert
        case additionalConditions, combinator
        case notifyOnReveal, settleSecondsOverride
        case additionalItems
    }

    /// Forward-compatible decoding: `invert`, `additionalConditions`, and
    /// `combinator` were added after earlier releases and are absent from
    /// triggers persisted before then.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        itemIdentifier = try container.decode(String.self, forKey: .itemIdentifier)
        itemDisplayName = try container.decode(String.self, forKey: .itemDisplayName)
        itemBaseIdentifier = try container.decodeIfPresent(String.self, forKey: .itemBaseIdentifier)
        revealSection = try container.decode(MenuBarSection.Name.self, forKey: .revealSection)
        hideSection = try container.decode(MenuBarSection.Name.self, forKey: .hideSection)
        condition = try container.decode(TriggerCondition.self, forKey: .condition)
        additionalConditions = try container.decodeIfPresent([TriggerCondition].self, forKey: .additionalConditions) ?? []
        combinator = try container.decodeIfPresent(TriggerCombinator.self, forKey: .combinator) ?? .all
        invert = try container.decodeIfPresent(Bool.self, forKey: .invert) ?? false
        notifyOnReveal = try container.decodeIfPresent(Bool.self, forKey: .notifyOnReveal) ?? false
        settleSecondsOverride = try container.decodeIfPresent(Double.self, forKey: .settleSecondsOverride)
        additionalItems = try container.decodeIfPresent([TriggerTargetItem].self, forKey: .additionalItems) ?? []
    }

    /// All target item identifiers (primary first), excluding empties.
    var allItemIdentifiers: [String] {
        ([itemIdentifier] + additionalItems.map(\.identifier)).filter { !$0.isEmpty }
    }

    /// Target identifiers paired with the base identity captured at selection
    /// time. The primary target remains first for priority ordering.
    var allTargetItems: [TriggerTargetItem] {
        [
            TriggerTargetItem(
                identifier: itemIdentifier,
                displayName: itemDisplayName,
                baseIdentifier: itemBaseIdentifier
            ),
        ] + additionalItems.filter { !$0.identifier.isEmpty }
    }

    /// All conditions, primary first.
    var allConditions: [TriggerCondition] {
        [condition] + additionalConditions
    }

    /// Evaluates whether the target item should be revealed, combining all
    /// conditions per ``combinator`` and accounting for the invert flag.
    func shouldReveal(state: SystemState, now: Date = Date()) -> Bool {
        let conditions = allConditions
        let satisfied: Bool = switch combinator {
        case .all: conditions.allSatisfy { $0.isSatisfied(state: state, now: now) }
        case .any: conditions.contains { $0.isSatisfied(state: state, now: now) }
        case .noneOf: !conditions.contains { $0.isSatisfied(state: state, now: now) }
        }
        return invert ? !satisfied : satisfied
    }

    /// A combined, human-readable summary of all conditions.
    var conditionSummary: String {
        let parts = allConditions.map(\.summary)
        guard parts.count > 1 else {
            guard let only = parts.first else { return "" }
            return combinator == .noneOf ? "Not: \(only)" : only
        }
        return combinator.summaryPrefix + parts.joined(separator: combinator.joiner)
    }

    /// A smart, auto-generated title combining the target item and the
    /// condition(s), e.g. "Battery: Battery is below 20%". Used as the
    /// default display name and the name-field placeholder.
    var autoTitle: String {
        let summary = conditionSummary
        if itemDisplayName.isEmpty { return summary }
        return "\(itemDisplayName): \(summary)"
    }

    /// A name suitable for display: the user's custom name if set, otherwise
    /// the smart auto-generated title.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return autoTitle
    }
}
