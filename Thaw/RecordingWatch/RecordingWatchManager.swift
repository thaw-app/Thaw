//
//  RecordingWatchManager.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation
import ThawUI

/// Reads the camera and microphone while Zen Mode or the alerts need them.
///
/// Turns Zen Mode on while either is in use, and, when the alerts are on, names the app that started.
/// Only the microphone can be attributed; see RecordingDeviceProbe.
@MainActor
@Observable
final class RecordingWatchManager {
    private nonisolated let diagLog = DiagLog(category: "RecordingWatchManager")

    /// How often the devices are sampled while they are read.
    ///
    /// Polled: CoreAudio listeners would need one re-registered subscription
    /// per process to save under a second.
    static let pollInterval: Duration = .seconds(1)

    private weak var appState: AppState?

    /// The settings slice this manager observes, injected at setup so the
    /// flag reads do not reach through the whole app state.
    private var advancedSettings: AdvancedSettings?
    private var cancellables = Set<AnyCancellable>()

    /// The most recent reading, or an empty one while the alerts are off.
    ///
    /// Empty when off, so the menu never consults the flag separately.
    var activity = RecordingActivity()

    private var pollTask: Task<Void, Never>?

    /// Whether the alerts run. Read straight off the settings model so a
    /// thaw:// flip and a profile apply agree with it.
    var areAlertsOn: Bool {
        RecordingWatchPolicy.alertsOn(saved: advancedSettings?.enableRecordingWatch ?? false)
    }

    private var isZenModeOn: Bool {
        advancedSettings?.zenModeWhileRecording ?? false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        advancedSettings = appState.settings.advanced
        cancellables = [observeSettingFlips()]
        refresh()
    }

    /// Reads the devices while the alerts or Zen Mode need them, and stops
    /// once neither does.
    private func refresh() {
        if RecordingWatchPolicy.shouldSample(alerts: areAlertsOn, zenMode: isZenModeOn) {
            start()
        } else {
            stop()
        }
    }

    // MARK: Polling

    private func start() {
        guard pollTask == nil else {
            return
        }
        diagLog.info("recording watch on, sampling every \(Self.pollInterval)")

        pollTask = Task { @MainActor [weak self] in
            // The first sample seeds the baseline, so a call already running
            // is not announced.
            var previous: RecordingActivity?

            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let sample = await Self.sample()
                guard !Task.isCancelled else {
                    return
                }

                // Without the alerts the reading only drives Zen Mode, so the
                // menu lists nothing and no banner shows.
                let alerts = self.areAlertsOn
                if alerts, let previous {
                    for announcement in RecordingWatchPolicy.announcements(from: previous, to: sample) {
                        self.announce(announcement)
                    }
                }
                previous = sample
                // The sample is usually identical to the last one; skipping
                // the write keeps the observation registrar quiet at 1 Hz.
                let shown = alerts ? sample : RecordingActivity()
                if self.activity != shown {
                    self.activity = shown
                }

                // Zen Mode while recording: collapse the bar while the camera or mic is
                // in use, restore it when they idle. The reason set means this
                // and screen-sharing zen coexist without cancelling each other.
                if self.isZenModeOn {
                    self.appState?.menuBarManager.setAutomaticZenMode(!sample.isIdle, reason: .recording)
                }

                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func stop() {
        guard pollTask != nil else { return }
        pollTask?.cancel()
        pollTask = nil
        activity = RecordingActivity()
        // The poller will no longer drive zen down as recordings end, so
        // withdraw any collapse it is currently holding.
        appState?.menuBarManager.setAutomaticZenMode(false, reason: .recording)
        diagLog.info("recording watch off")
    }

    /// One reading of both devices.
    ///
    /// Reads off main (synchronous IPC); names on main (NSRunningApplication).
    private static func sample() async -> RecordingActivity {
        let reading = await Task.detached(priority: .utility) {
            (
                inputs: RecordingDeviceProbe.microphoneInputs(),
                isCameraInUse: RecordingDeviceProbe.isCameraInUse()
            )
        }.value

        return RecordingActivity(
            microphoneUsers: reading.inputs.map(named),
            isCameraInUse: reading.isCameraInUse
        )
    }

    /// Puts a display name on a raw input.
    ///
    /// Falls back to bundle ID, then PID: a daemon named badly beats one
    /// dropped from a security readout.
    private static func named(_ input: RecordingDeviceProbe.Input) -> MicrophoneUser {
        let name = NSRunningApplication(processIdentifier: input.processIdentifier)?.localizedName
            ?? input.bundleIdentifier
            ?? String(localized: "pid \(input.processIdentifier)")

        return MicrophoneUser(
            processIdentifier: input.processIdentifier,
            bundleIdentifier: input.bundleIdentifier,
            name: name
        )
    }

    // MARK: Announcing

    private func announce(_ announcement: RecordingWatchAnnouncement) {
        // Resolved per announcement so a picker change applies immediately.
        let screen = announcementScreen()
        let placement = advancedSettings?.recordingWatchPlacement ?? .center
        switch announcement {
        case let .microphoneOn(app):
            diagLog.info("microphone input started: \(app)")
            ThawHUD.show(
                symbol: "mic.fill",
                text: "Microphone on: \(app)",
                on: screen,
                placement: placement
            )
        case .cameraOn:
            diagLog.info("camera started; macOS names no owner")
            ThawHUD.show(
                symbol: "video.fill",
                text: "Camera on",
                on: screen,
                placement: placement
            )
        }
    }

    /// The screen the next announcement lands on. Live reads happen here; the
    /// decision is the pure RecordingWatchScreen.resolve.
    private func announcementScreen() -> NSScreen? {
        let choice = advancedSettings?.recordingWatchScreen ?? .screenWithPointer
        let connectedDisplays: [(uuid: String, displayID: CGDirectDisplayID)] = NSScreen.screens.compactMap { screen in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            return (uuid, screen.displayID)
        }
        let displayID = choice.resolve(
            pointerDisplayID: NSScreen.screenWithMouse?.displayID,
            primaryDisplayID: NSScreen.screens.first?.displayID,
            connectedDisplays: connectedDisplays
        )
        return displayID.flatMap(NSScreen.screen(for:))
    }

    // MARK: Flags

    /// Starts and stops the poller with the two flags. Observes the
    /// properties, not defaults, so pane, thaw:// and profile changes all land.
    private func observeSettingFlips() -> AnyCancellable {
        guard let advanced = advancedSettings else { return AnyCancellable { /* Nothing was observed, so there is nothing to cancel. */ } }
        let flagTask = advanced.observe(\.enableRecordingWatch) { [weak self] _ in
            self?.refresh()
        }
        // The poll loop never sees the flag's falling edge, so release any
        // held collapse here.
        let zenTask = advanced.observe(\.zenModeWhileRecording) { [weak self] enabled in
            if !enabled {
                self?.appState?.menuBarManager.setAutomaticZenMode(false, reason: .recording)
            }
            self?.refresh()
        }
        return AnyCancellable {
            flagTask.cancel()
            zenTask.cancel()
        }
    }
}
