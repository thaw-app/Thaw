//
//  DeveloperSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreLocation
import SwiftUI

// MARK: - DeveloperSettingsPane

/// Developer settings: per-source feature flags for menu bar item triggers
/// and a live readout of the aggregated system state, so each trigger
/// source can be enabled and debugged in isolation.
struct DeveloperSettingsPane: View {
    @Bindable private var flags: TriggerFeatureFlagsManager

    /// Plain reference (not observed): used to read Location authorization
    /// status and to (re)request it for the Wi-Fi SSID diagnostic.
    private let systemMonitor: SystemStateMonitor

    /// A direct, flag-independent snapshot of the system, refreshed on a
    /// timer while the pane is visible so the readout always shows ground
    /// truth (the trigger monitors themselves remain gated by the flags).
    @State private var liveState = SystemState()
    @State private var isRefreshingLiveState = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(manager: MenuBarItemTriggersManager) {
        flags = manager.featureFlags
        systemMonitor = manager.systemMonitor
    }

    var body: some View {
        IceForm {
            introSection
            flagsSection
            liveStateSection
        }
        .onAppear {
            refreshLiveState()
            // While the window is focused, nudge the Location prompt so the
            // Wi-Fi SSID or coordinate source can resolve (no-op once decided).
            if flags.isEnabled(.wifiSSID) || flags.isEnabled(.location) {
                systemMonitor.ensureLocationAuthorization()
            }
        }
        .onReceive(refreshTimer) { _ in
            refreshLiveState()
        }
        .onChange(of: flags.isEnabled(.wifiSSID) || flags.isEnabled(.location)) { _, enabled in
            if enabled {
                systemMonitor.ensureLocationAuthorization()
            }
            refreshLiveState()
        }
    }

    private func refreshLiveState() {
        guard !isRefreshingLiveState else { return }
        isRefreshingLiveState = true
        Task { @MainActor in
            liveState = await SystemStateMonitor.fullSnapshot(flags: flags)
            isRefreshingLiveState = false
        }
    }

    // MARK: Intro

    private var introSection: some View {
        IceSection() {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Dev Mode Flags")
                        .font(.headline)
                    Spacer()
                    Button {
                        flags.disableAll()
                    } label: {
                        Label("All Off", systemImage: "power")
                    }
                    .disabled(!flags.hasEnabledFlags)
                }
                Text("Enable experimental trigger sources one at a time. Each flag turns on its condition in the Triggers pane and starts its background monitor. Battery and power conditions are always available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                    .padding(.vertical, 4)
                Toggle(isOn: $flags.showsAllOffInMenuBarMenu) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show All Off in menu bar dropdown")
                        Text("Adds the emergency trigger-feature shutoff to the three-dot menu. Keep this off unless a trigger source is disrupting normal computer use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: Flags

    private var flagsSection: some View {
        IceSection() {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(TriggerFeature.allCases.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 {
                        Divider()
                    }
                    flagRow(feature)
                        .padding(.vertical, 8)
                }
            }
            .padding(8)
        }
    }

    private func flagRow(_ feature: TriggerFeature) -> some View {
        Toggle(isOn: flags.binding(for: feature)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.title)
                    if let badge = feature.statusBadge {
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                    }
                }
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Live state

    private var liveStateSection: some View {
        IceSection("Live System State") {
            VStack(alignment: .leading, spacing: 6) {
                let state = liveState
                stateRow("Battery", batteryString(state.power))
                stateRow("Power source", state.power.isOnACPower ? "AC power" : "Battery")
                stateRow("Charging", state.power.isCharging ? "Yes" : "No")
                stateRow("Frontmost app", state.frontmostAppBundleID ?? "—")
                stateRow("Running apps", "\(state.runningAppBundleIDs.count)")
                stateRow("Network", state.isNetworkConnected ? "Connected" : "Offline")
                stateRow("VPN", state.isVPNActive ? "Active" : "Inactive")
                stateRow("Wi-Fi SSID", wifiSSIDValue(state))
                stateRow("Bluetooth", flags.isEnabled(.bluetooth) ? state.connectedBluetoothDeviceNames.sorted().joined(separator: ", ").orDash : "Enable flag to read")
                stateRow("Audio output", state.audioOutputDeviceName ?? "—")
                stateRow("Energy Mode", energyModeString(state.energyMode))
                stateRow("Thermal state", thermalString(state.thermalState))
                stateRow("Camera in use", flags.isEnabled(.recordingDevices) ? (state.isCameraInUse ? "Yes" : "No") : "Enable flag to read")
                stateRow("Microphone in use", flags.isEnabled(.recordingDevices) ? (state.isMicrophoneInUse ? "Yes" : "No") : "Enable flag to read")
                stateRow("Displays", "\(state.screenCount)\(state.externalDisplayConnected ? " (external connected)" : "")")
                stateRow("Focus active", state.isFocusActive ? "Yes" : "No")
                stateRow("Focus Filter profile", state.activeFocusModeName ?? "—")
                stateRow("Location", locationValue())
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stateRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func batteryString(_ power: PowerState) -> String {
        guard let percentage = power.batteryPercentage else { return "No battery" }
        return "\(Int(percentage.rounded()))%"
    }

    /// Describes the current Energy Mode, noting when High Power Mode isn't
    /// offered by this Mac so a trigger that can never fire is obvious here.
    private func energyModeString(_ mode: EnergyMode) -> String {
        EnergyModeMonitor.isHighPowerModeSupported
            ? mode.displayString
            : "\(mode.displayString) (no High Power Mode on this Mac)"
    }

    private func thermalString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    /// Current coordinate when the Location flag is on, otherwise a hint.
    private func locationValue() -> String {
        guard flags.isEnabled(.location) else { return "Enable flag to read" }
        if let coordinate = systemMonitor.currentCoordinate {
            return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
        switch systemMonitor.locationAuthorizationStatus {
        case .notDetermined:
            return "Awaiting Location permission…"
        case .denied, .restricted:
            return "Location denied — enable in System Settings"
        default:
            return "Locating…"
        }
    }

    /// Wi-Fi SSID value or, when unavailable, the reason — usually the
    /// Location authorization state, since CoreWLAN needs it to read SSIDs.
    private func wifiSSIDValue(_ state: SystemState) -> String {
        guard flags.isEnabled(.wifiSSID) else { return "Enable flag to read" }
        if let ssid = state.wifiSSID, !ssid.isEmpty { return ssid }
        switch systemMonitor.locationAuthorizationStatus {
        case .notDetermined:
            return "Awaiting Location permission…"
        case .denied, .restricted:
            return "Location denied — enable in System Settings ▸ Privacy & Security ▸ Location Services"
        case .authorized, .authorizedAlways:
            return "No Wi-Fi network (or Wi-Fi off)"
        @unknown default:
            return "Unavailable"
        }
    }
}

private extension String {
    /// Returns an em dash when the string is empty.
    var orDash: String {
        isEmpty ? "—" : self
    }
}
