//
//  RecordingWatchSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawUI

/// Camera and microphone alerts, from the menu bar's recording indicator.
/// Hidden for now: see RecordingWatchPolicy.alertsAvailable.
struct RecordingWatchSection: View {
    @Bindable var settings: AdvancedSettings

    /// Bumped on display-configuration changes so the announcement-screen
    /// picker re-reads the live display list. Read in the body through
    /// announcementScreenChoices.
    @State private var screenGeneration = 0

    var body: some View {
        ThawSection("Camera and microphone") {
            enableRecordingWatch
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenGeneration += 1
        }
    }

    /// The switch and, while it is on, the options. macOS attributes only the microphone to an app, not the camera.
    @ViewBuilder
    private var enableRecordingWatch: some View {
        Toggle(isOn: $settings.enableRecordingWatch) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Tell me when the camera or microphone turns on")
                ThawBadge.alpha
            }
        }
        .annotation {
            Text(
                """
                \(Constants.displayName) already watches the menu bar's recording indicator, so it \
                can tell you when something starts listening or watching. A banner names the app \
                that takes your microphone, and another appears when a camera turns on. macOS \
                doesn't say which app is using a camera, so that one says only that it's in use. \
                While either is on, \(Constants.displayName)'s menu lists what's using it.
                """
            )
        }
        if settings.enableRecordingWatch {
            announcementScreenPicker
            announcementPlacementPicker
        }
    }

    /// Where along the top of that display the banners sit.
    ///
    /// Separate from the screen picker; crossing them would make nine rows.
    private var announcementPlacementPicker: some View {
        ThawPicker("Place announcements", selection: $settings.recordingWatchPlacement) {
            ForEach(ThawHUDPlacement.allCases, id: \.self) { placement in
                Text(placement.localized).tag(placement)
            }
        }
        .annotation {
            Text(
                """
                Banners appear just under the menu bar. The center is where \
                \(Constants.displayName)'s other confirmations appear; move them to a corner if \
                they land on top of what you're working on.
                """
            )
        }
    }

    /// Which display the banners land on. An unplugged choice stays, marked unavailable, so it survives replugging.
    private var announcementScreenPicker: some View {
        ThawPicker("Show announcements on", selection: $settings.recordingWatchScreen) {
            ForEach(announcementScreenChoices) { choice in
                Text(choice.name).tag(choice.screen)
            }
            if let unavailable = unavailableChosenDisplay {
                Text("Chosen display (unavailable)").tag(unavailable)
            }
        }
        .annotation {
            Text(
                """
                The pointer's screen follows wherever you're working. Pinning the banner to a \
                display shows it there even when the pointer is somewhere else, which is the point \
                when the camera turns on while you're not at the machine. If that display isn't \
                connected, the main display is used.
                """
            )
        }
    }

    /// One selectable row of the announcement-screen picker: a connected
    /// display by its own name, or the two fixed behaviors.
    private var announcementScreenChoices: [AnnouncementScreenChoice] {
        // Read so the body depends on it: display plug events bump this.
        _ = screenGeneration
        var choices = [
            AnnouncementScreenChoice(
                id: RecordingWatchScreen.screenWithPointer.storageKey,
                name: String(localized: "Screen with pointer"),
                screen: .screenWithPointer
            ),
            AnnouncementScreenChoice(
                id: RecordingWatchScreen.mainDisplay.storageKey,
                name: String(localized: "Main display"),
                screen: .mainDisplay
            ),
        ]
        choices += NSScreen.screens.compactMap { screen in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            return AnnouncementScreenChoice(
                id: uuid,
                name: screen.localizedName,
                screen: .display(uuid: uuid)
            )
        }
        return choices
    }

    /// The chosen display's tag when it is no longer connected, so the
    /// picker can still show that something is selected there.
    private var unavailableChosenDisplay: RecordingWatchScreen? {
        guard case let .display(uuid) = settings.recordingWatchScreen,
              !announcementScreenChoices.contains(where: { $0.id == uuid })
        else {
            return nil
        }
        return .display(uuid: uuid)
    }
}

/// One row of the announcement-screen picker. A struct because display cases
/// need their own names as labels.
private struct AnnouncementScreenChoice: Identifiable {
    /// Stable row identity: the screen choice's storage key, or the display
    /// UUID for a connected display.
    let id: String
    let name: String
    let screen: RecordingWatchScreen
}
