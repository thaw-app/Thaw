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

/// Says out loud what the system says with a 6pt dot.
///
/// Shows a capsule naming the app when the camera or mic starts, plus a line
/// in the control item menu while it lasts.
///
/// Kept off MenuBarManager so the experiment is removable by deleting one
/// directory and one line in AppState.
///
/// Only the microphone can be attributed; see RecordingDeviceProbe.
@MainActor
@Observable
final class RecordingWatchManager {
    private nonisolated let diagLog = DiagLog(category: "RecordingWatchManager")

    /// How often the devices are sampled while the experiment is on.
    ///
    /// Polled: CoreAudio listeners would need one re-registered subscription
    /// per process to save under a second.
    static let pollInterval: Duration = .seconds(1)

    private weak var appState: AppState?

    /// The settings slice this manager observes, injected at setup so the
    /// flag reads do not reach through the whole app state.
    private var advancedSettings: AdvancedSettings?
    private var cancellables = Set<AnyCancellable>()

    /// The most recent reading, or an empty one while the experiment is off.
    ///
    /// Empty when off, so the menu never consults the flag separately.
    private(set) var activity = RecordingActivity()

    private var pollTask: Task<Void, Never>?

    /// Whether the Lab flag is on. Read straight off the settings model so the
    /// pane's binding, a thaw:// flip and a profile apply all agree.
    var isEnabled: Bool {
        advancedSettings?.enableRecordingWatch ?? false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        advancedSettings = appState.settings.advanced
        cancellables = [observeSettingFlips()]
        if isEnabled {
            start()
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

                if let previous {
                    for announcement in RecordingWatchPolicy.announcements(from: previous, to: sample) {
                        self.announce(announcement)
                    }
                }
                previous = sample
                // The sample is usually identical to the last one; skipping
                // the write keeps the observation registrar quiet at 1 Hz.
                if self.activity != sample {
                    self.activity = sample
                }

                // Presenter mode: collapse the bar while the camera or mic is
                // in use, restore it when they idle. The reason set means this
                // and screen-sharing zen coexist without cancelling each other.
                if self.advancedSettings?.zenModeWhileRecording == true {
                    self.appState?.menuBarManager.setAutomaticZenMode(!sample.isIdle, reason: .recording)
                }

                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func stop() {
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

    // MARK: Flag

    /// Starts and stops the poller with the Lab flag. Observes the property,
    /// not defaults, so pane, thaw:// and profile changes all land.
    private func observeSettingFlips() -> AnyCancellable {
        guard let advanced = advancedSettings else { return AnyCancellable {} }
        let flagTask = advanced.observe(\.enableRecordingWatch) { [weak self] enabled in
            if enabled {
                self?.start()
            } else {
                self?.stop()
            }
        }
        // The poll loop never sees the flag's falling edge, so release any
        // held collapse here.
        let zenTask = advanced.observe(\.zenModeWhileRecording) { [weak self] enabled in
            guard !enabled else { return }
            self?.appState?.menuBarManager.setAutomaticZenMode(false, reason: .recording)
        }
        return AnyCancellable {
            flagTask.cancel()
            zenTask.cancel()
        }
    }
}
