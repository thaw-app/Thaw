//
//  RecordingAlertRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// The camera and microphone alerts: whether they show, on which screen and where.
struct RecordingAlertRows: View {
    @Bindable var settings: VisibilitySettings

    var body: some View {
        Toggle("Alert when the camera or microphone turns on", isOn: $settings.enableRecordingWatch)
            .annotation("A short notice under the menu bar names the app using the microphone. macOS doesn't say which app uses the camera.")
        if settings.enableRecordingWatch {
            ThawPicker("Show alerts on", selection: $settings.recordingWatchScreen) {
                ForEach(Self.screenChoices(current: settings.recordingWatchScreen), id: \.choice) { option in
                    Text(option.name).tag(option.choice)
                }
            }
            ThawPicker("Alert position", selection: $settings.recordingWatchPlacement) {
                Text("Left").tag(ThawHUDPlacement.leading)
                Text("Center").tag(ThawHUDPlacement.center)
                Text("Right").tag(ThawHUDPlacement.trailing)
            }
        }
    }

    /// The pointer's screen, the main display and each connected display by name,
    /// plus a chosen display that is disconnected, so the picker can show it.
    static func screenChoices(current: RecordingWatchScreen) -> [(choice: RecordingWatchScreen, name: String)] {
        var choices: [(choice: RecordingWatchScreen, name: String)] = [
            (.screenWithPointer, String(localized: "Screen with pointer")),
            (.mainDisplay, String(localized: "Main display")),
        ]
        for screen in NSScreen.screens {
            if let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) {
                choices.append((.display(uuid: uuid), screen.localizedName))
            }
        }
        if !choices.contains(where: { $0.choice == current }) {
            choices.append((current, String(localized: "Chosen display")))
        }
        return choices
    }
}
