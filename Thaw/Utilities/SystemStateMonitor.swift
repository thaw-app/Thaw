//
//  SystemStateMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import CoreAudio
import CoreLocation
import CoreMediaIO
import CoreWLAN
import Foundation
import Intents
import IOBluetooth
import Network
import SystemConfiguration

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

    /// The active app-defined Focus mode name (from ``ThawFocusFilter``),
    /// or `nil` when no Thaw Focus Filter is currently applied.
    var activeFocusModeName: String?

    /// The current latitude / longitude, when location updates are running.
    var currentLatitude: Double?
    var currentLongitude: Double?

    /// Whether macOS Low Power Mode is enabled.
    var isLowPowerMode: Bool

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
        isLowPowerMode: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal,
        isCameraInUse: Bool = false,
        isMicrophoneInUse: Bool = false,
        scriptOutcomes: [String: ScriptOutcome] = [:],
        imageHashes: [String: UInt64] = [:]
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
        self.isLowPowerMode = isLowPowerMode
        self.thermalState = thermalState
        self.isCameraInUse = isCameraInUse
        self.isMicrophoneInUse = isMicrophoneInUse
        self.scriptOutcomes = scriptOutcomes
        self.imageHashes = imageHashes
    }
}

// MARK: - SystemStateMonitor

/// Aggregates several system signals into a single published
/// ``SystemState``, starting only the monitors whose feature flag is
/// enabled so disabled sources cost nothing.
///
/// Event-driven sources (power, frontmost/running app, display, network)
/// update the state immediately. App-running also gets a lightweight polling
/// fallback because workspace launch/terminate notifications are not perfectly
/// reliable. Heavier sources (audio output, Bluetooth, VPN, Wi-Fi SSID, Focus)
/// are sampled on a single low-frequency poll while their flag is enabled.
/// Trigger evaluation already debounces, so the poll latency is not user-visible.
@MainActor
final class SystemStateMonitor: ObservableObject {
    @Published private(set) var state = SystemState()

    private weak var flags: TriggerFeatureFlagsManager?

    private let powerMonitor = PowerSourceMonitor()

    private var cancellables = Set<AnyCancellable>()

    // Event-driven source handles.
    private var workspaceObservers = [NSObjectProtocol]()
    private var screenObserver: NSObjectProtocol?
    private var systemLoadObservers = [NSObjectProtocol]()
    private var pathMonitor: NWPathMonitor?

    /// Poll timer for the sampled sources.
    private var pollTimer: Timer?

    /// Poll timer for app-running state, used as a fallback for missed
    /// workspace launch/terminate notifications.
    private var appRefreshTimer: Timer?

    /// Provides Location authorization (needed for Wi-Fi SSID) and the
    /// current coordinate (needed for the location condition). Created lazily
    /// so the prompt only appears when a location-using feature is enabled.
    private var locationProvider: LocationProvider?

    private let diagLog = DiagLog(category: "SystemStateMonitor")

    // MARK: Lifecycle

    /// Starts monitoring, observing the given feature flags so monitors can
    /// be (de)activated as flags change.
    func start(flags: TriggerFeatureFlagsManager) {
        self.flags = flags

        powerMonitor.start()
        powerMonitor.$state
            .removeDuplicates()
            .sink { [weak self] power in
                self?.update { $0.power = power }
            }
            .store(in: &cancellables)

        flags.addChangeHandler { [weak self] in
            // Reconfigure after the flag set has actually mutated.
            DispatchQueue.main.async { self?.reconfigure() }
        }

        // Seed the static portions of the state up front.
        update {
            $0.power = self.powerMonitor.state
            $0.screenCount = NSScreen.screens.count
            $0.externalDisplayConnected = Self.hasExternalDisplay()
        }

        reconfigure()
    }

    /// Starts or stops individual monitors to match the current flags.
    private func reconfigure() {
        guard let flags else { return }

        setFrontmostAppMonitoring(flags.isEnabled(.frontmostApp) || flags.isEnabled(.appRunning))
        setAppRefreshPolling(flags.isEnabled(.appRunning))
        setDisplayMonitoring(flags.isEnabled(.display))
        setNetworkMonitoring(flags.isEnabled(.network) || flags.isEnabled(.vpn))
        setSystemLoadMonitoring(flags.isEnabled(.lowPowerMode) || flags.isEnabled(.thermalPressure))

        // Both Wi-Fi SSID and the location condition need Location access.
        if flags.isEnabled(.wifiSSID) || flags.isEnabled(.location) {
            ensureLocationAuthorization()
        }
        // The location condition additionally needs live coordinate updates.
        if flags.isEnabled(.location) {
            locationProvider?.startUpdating()
        } else {
            locationProvider?.stopUpdating()
        }
        if flags.isEnabled(.focusMode) {
            ensureFocusAuthorization()
        }

        let needsPoll = flags.isEnabled(.audioOutput)
            || flags.isEnabled(.bluetooth)
            || flags.isEnabled(.vpn)
            || flags.isEnabled(.wifiSSID)
            || flags.isEnabled(.focusMode)
            || flags.isEnabled(.location)
            || flags.isEnabled(.recordingDevices)
        setPolling(needsPoll)

        // Run one immediate sample so newly enabled sources populate now.
        samplePolledSources()
    }

    // MARK: State update

    /// Applies a mutation and republishes only when the state changed.
    private func update(_ mutate: (inout SystemState) -> Void) {
        var copy = state
        mutate(&copy)
        if copy != state {
            state = copy
        }
    }

    // MARK: Frontmost / running apps

    private func setFrontmostAppMonitoring(_ enabled: Bool) {
        let isRunning = !workspaceObservers.isEmpty
        guard enabled != isRunning else {
            if enabled { refreshApps() }
            return
        }

        if enabled {
            let center = NSWorkspace.shared.notificationCenter
            let names: [NSNotification.Name] = [
                NSWorkspace.didActivateApplicationNotification,
                NSWorkspace.didLaunchApplicationNotification,
                NSWorkspace.didTerminateApplicationNotification,
            ]
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshApps() }
                }
                workspaceObservers.append(token)
            }
            refreshApps()
        } else {
            for token in workspaceObservers {
                NSWorkspace.shared.notificationCenter.removeObserver(token)
            }
            workspaceObservers.removeAll()
        }
    }

    private func refreshApps() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let running = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
        )
        let changed = state.frontmostAppBundleID != frontmost || state.runningAppBundleIDs != running
        update {
            $0.frontmostAppBundleID = frontmost
            $0.runningAppBundleIDs = running
        }
        if changed {
            diagLog.debug("App state refreshed: frontmost=\(frontmost ?? "nil"), running=\(running.count)")
        }
    }

    private func setAppRefreshPolling(_ enabled: Bool) {
        if enabled, appRefreshTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshApps() }
            }
            RunLoop.main.add(timer, forMode: .common)
            appRefreshTimer = timer
        } else if !enabled {
            appRefreshTimer?.invalidate()
            appRefreshTimer = nil
        }
    }

    // MARK: Display

    private func setDisplayMonitoring(_ enabled: Bool) {
        if enabled, screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDisplays() }
            }
            refreshDisplays()
        } else if !enabled, let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    private func refreshDisplays() {
        let count = NSScreen.screens.count
        let external = Self.hasExternalDisplay()
        update {
            $0.screenCount = count
            $0.externalDisplayConnected = external
        }
    }

    private static func hasExternalDisplay() -> Bool {
        // The built-in display reports a builtin flag via its device
        // description; any screen without it is treated as external.
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(displayID) == 0 {
                return true
            }
        }
        return false
    }

    // MARK: Location (for Wi-Fi SSID)

    /// Requests Location authorization for reading the Wi-Fi SSID, creating
    /// the authorizer on first use. Without authorization,
    /// `CWWiFiClient.ssid()` returns `nil` on modern macOS even though the
    /// call succeeds. The authorizer sets a delegate, which is required for
    /// the system prompt to actually appear.
    func ensureLocationAuthorization() {
        let provider = locationProvider ?? LocationProvider()
        locationProvider = provider
        provider.requestIfNeeded()
    }

    /// The current Location authorization status (used by the Developer pane
    /// to explain why the Wi-Fi SSID / location is unavailable).
    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationProvider?.status ?? CLLocationManager().authorizationStatus
    }

    /// The most recent coordinate, if location updates are running.
    var currentCoordinate: (latitude: Double, longitude: Double)? {
        guard let coordinate = locationProvider?.currentLocation?.coordinate else { return nil }
        return (coordinate.latitude, coordinate.longitude)
    }

    /// Requests Focus authorization the first time the Focus feature is
    /// enabled, so `INFocusStatusCenter` can report the focus status.
    private func ensureFocusAuthorization() {
        if INFocusStatusCenter.default.authorizationStatus == .notDetermined {
            INFocusStatusCenter.default.requestAuthorization { _ in }
        }
    }

    // MARK: System load (Low Power Mode / thermal)

    private func setSystemLoadMonitoring(_ enabled: Bool) {
        let isRunning = !systemLoadObservers.isEmpty
        guard enabled != isRunning else {
            if enabled { refreshSystemLoad() }
            return
        }
        if enabled {
            let center = NotificationCenter.default
            let names: [NSNotification.Name] = [
                .NSProcessInfoPowerStateDidChange,
                ProcessInfo.thermalStateDidChangeNotification,
            ]
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshSystemLoad() }
                }
                systemLoadObservers.append(token)
            }
            refreshSystemLoad()
        } else {
            for token in systemLoadObservers {
                NotificationCenter.default.removeObserver(token)
            }
            systemLoadObservers.removeAll()
        }
    }

    private func refreshSystemLoad() {
        let info = ProcessInfo.processInfo
        let lowPower = info.isLowPowerModeEnabled
        let thermal = info.thermalState
        update {
            $0.isLowPowerMode = lowPower
            $0.thermalState = thermal
        }
    }

    // MARK: Network

    private func setNetworkMonitoring(_ enabled: Bool) {
        if enabled, pathMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let connected = path.status == .satisfied
                Task { @MainActor in
                    self?.update { $0.isNetworkConnected = connected }
                }
            }
            monitor.start(queue: DispatchQueue(label: "com.stonerl.Thaw.networkMonitor"))
            pathMonitor = monitor
        } else if !enabled, let monitor = pathMonitor {
            monitor.cancel()
            pathMonitor = nil
        }
    }

    // MARK: Polled sources

    private func setPolling(_ enabled: Bool) {
        if enabled, pollTimer == nil {
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.samplePolledSources() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !enabled {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func samplePolledSources() {
        guard let flags else { return }

        let audio = flags.isEnabled(.audioOutput) ? Self.defaultAudioOutputDeviceName() : nil
        let bluetooth = flags.isEnabled(.bluetooth) ? Self.connectedBluetoothDeviceNames() : []
        let vpn = flags.isEnabled(.vpn) ? Self.isVPNActive() : false
        let ssid = flags.isEnabled(.wifiSSID) ? Self.currentWiFiSSID() : nil
        let focus = flags.isEnabled(.focusMode) ? Self.isFocusActive() : false
        // The Focus mode is the profile requested by Thaw's Focus Filter,
        // which the filter itself sets on activation and clears on
        // deactivation (see ThawFocusModeStore).
        let focusMode = flags.isEnabled(.focusMode) ? ThawFocusModeStore.activeMode : nil
        let coordinate = flags.isEnabled(.location) ? currentCoordinate : nil
        let cameraInUse = flags.isEnabled(.recordingDevices) ? Self.isCameraInUse() : false
        let micInUse = flags.isEnabled(.recordingDevices) ? Self.isMicrophoneInUse() : false

        update {
            if flags.isEnabled(.audioOutput) { $0.audioOutputDeviceName = audio }
            if flags.isEnabled(.bluetooth) { $0.connectedBluetoothDeviceNames = bluetooth }
            if flags.isEnabled(.vpn) { $0.isVPNActive = vpn }
            if flags.isEnabled(.wifiSSID) { $0.wifiSSID = ssid }
            if flags.isEnabled(.recordingDevices) {
                $0.isCameraInUse = cameraInUse
                $0.isMicrophoneInUse = micInUse
            }
            if flags.isEnabled(.focusMode) {
                $0.isFocusActive = focus
                $0.activeFocusModeName = focusMode
            }
            if flags.isEnabled(.location) {
                $0.currentLatitude = coordinate?.latitude
                $0.currentLongitude = coordinate?.longitude
            }
        }
    }

    /// Samples sources directly for the Developer pane's live readout.
    ///
    /// Non-privacy-sensitive sources are always sampled so the readout shows
    /// ground truth regardless of flags. Privacy-sensitive sources
    /// (Bluetooth, Wi-Fi SSID) are only sampled when their flag is enabled,
    /// so merely opening the Developer pane never triggers a Bluetooth or
    /// Location permission prompt for a feature the user hasn't opted into.
    @MainActor
    static func fullSnapshot(flags: TriggerFeatureFlagsManager) -> SystemState {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let running = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
        )
        return SystemState(
            power: PowerSourceMonitor.readCurrentState(),
            frontmostAppBundleID: frontmost,
            runningAppBundleIDs: running,
            isNetworkConnected: isNetworkReachable(),
            isVPNActive: isVPNActive(),
            wifiSSID: flags.isEnabled(.wifiSSID) ? currentWiFiSSID() : nil,
            connectedBluetoothDeviceNames: flags.isEnabled(.bluetooth) ? connectedBluetoothDeviceNames() : [],
            audioOutputDeviceName: defaultAudioOutputDeviceName(),
            screenCount: NSScreen.screens.count,
            externalDisplayConnected: hasExternalDisplay(),
            isFocusActive: isFocusActive(),
            activeFocusModeName: ThawFocusModeStore.activeMode,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState,
            isCameraInUse: flags.isEnabled(.recordingDevices) ? isCameraInUse() : false,
            isMicrophoneInUse: flags.isEnabled(.recordingDevices) ? isMicrophoneInUse() : false
        )
    }

    // MARK: Sampling helpers

    /// Synchronously checks general internet reachability (used by the
    /// Developer snapshot; live monitoring uses NWPathMonitor instead).
    static func isNetworkReachable() -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard let reachability = withUnsafePointer(to: &address, { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else { return false }
        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }

    /// Returns the name of the current default audio output device.
    static func defaultAudioOutputDeviceName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameStatus = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
        guard nameStatus == noErr, let cfName = name?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    /// Returns the names of all currently connected Bluetooth devices.
    static func connectedBluetoothDeviceNames() -> Set<String> {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        var names = Set<String>()
        for device in devices where device.isConnected() {
            if let name = device.name, !name.isEmpty {
                names.insert(name)
            }
        }
        return names
    }

    /// Whether any camera is currently in use by some process. Reads the
    /// CoreMediaIO "running somewhere" hardware property, which does not
    /// require camera permission (no capture is performed).
    static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(0)
        )
        var dataSize: UInt32 = 0
        let systemObject = CMIOObjectID(kCMIOObjectSystemObject)
        guard
            CMIOObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr,
            dataSize > 0
        else {
            return false
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(systemObject, &address, 0, nil, dataSize, &used, &devices) == noErr else {
            return false
        }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, size, &size, &isRunning) == noErr, isRunning != 0 {
                return true
            }
        }
        return false
    }

    /// Whether any microphone is currently in use by some process. Reads the
    /// CoreAudio "running somewhere" hardware property on input devices,
    /// which does not require microphone permission.
    static func isMicrophoneInUse() -> Bool {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard
            AudioObjectGetPropertyDataSize(systemObject, &listAddress, 0, nil, &dataSize) == noErr,
            dataSize > 0
        else {
            return false
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &listAddress, 0, nil, &dataSize, &devices) == noErr else {
            return false
        }

        for device in devices {
            // Only input-capable devices can be a microphone in use.
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamsSize: UInt32 = 0
            guard
                AudioObjectGetPropertyDataSize(device, &streamsAddress, 0, nil, &streamsSize) == noErr,
                streamsSize > 0
            else {
                continue
            }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &isRunning) == noErr, isRunning != 0 {
                return true
            }
        }
        return false
    }

    /// Heuristically detects an active VPN by inspecting the scoped system
    /// proxy settings for tunnel interface names.
    static func isVPNActive() -> Bool {
        guard
            let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
            let scoped = settings["__SCOPED__"] as? [String: Any]
        else {
            return false
        }
        let tunnelPrefixes = ["tap", "tun", "ppp", "ipsec", "utun"]
        for key in scoped.keys where tunnelPrefixes.contains(where: { key.contains($0) }) {
            return true
        }
        return false
    }

    /// Returns the current Wi-Fi SSID, if available. Requires Location
    /// permission on recent macOS; returns `nil` otherwise (best-effort).
    static func currentWiFiSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    /// Detects an active Focus / Do Not Disturb.
    ///
    /// Prefers the official `INFocusStatusCenter`, which reports whether a
    /// Focus is currently silencing notifications (requires authorization,
    /// requested when the Focus feature is enabled). Falls back to reading
    /// the Do Not Disturb assertions store when the status is unavailable
    /// (e.g. authorization not yet granted).
    static func isFocusActive() -> Bool {
        // Only touch focusStatus when authorized: reading protected data
        // without authorization (and without the usage description) risks a
        // privacy abort, and returns nil anyway. Fall back to the file.
        if INFocusStatusCenter.default.authorizationStatus == .authorized,
           let focused = INFocusStatusCenter.default.focusStatus.isFocused
        {
            return focused
        }
        return isFocusActiveFromAssertions()
    }

    /// File-based fallback: reads the Do Not Disturb assertions store and
    /// returns whether any focus assertion is currently active.
    static func isFocusActiveFromAssertions() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let records = json["data"] as? [[String: Any]],
            let first = records.first,
            let assertions = first["storeAssertionRecords"] as? [[String: Any]]
        else {
            return false
        }
        return !assertions.isEmpty
    }
}

// MARK: - LocationProvider

/// Owns a `CLLocationManager` to supply Location authorization (required by
/// CoreWLAN to read the Wi-Fi SSID) and, when started, the current
/// coordinate (for the location trigger condition).
///
/// A delegate is set in `init` — this is required for the authorization
/// prompt to appear reliably. The manager is created on the main thread, so
/// its delegate callbacks arrive on the main run loop and `currentLocation`
/// is only ever touched there.
private final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var currentLocation: CLLocation?
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var status: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startUpdating() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
        currentLocation = nil
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let isAuthorized: Bool
        #if os(macOS)
            isAuthorized = status == .authorized || status == .authorizedAlways
        #else
            isAuthorized = status == .authorized || status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
        if isUpdating, isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        // Ignore transient errors; the next update refreshes the location.
    }
}
