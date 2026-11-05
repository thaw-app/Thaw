//
//  ZenModeWhileRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The times Thaw turns Zen Mode on by itself, as one row: while the screen
/// is shared or mirrored, and while the camera or microphone is on. Each
/// turns Zen Mode off again when it ends, and the two don't undo each other.
struct ZenModeWhileRow: View {
    @Bindable var settings: AdvancedSettings

    var body: some View {
        ToggleButtonRow("Turn on Zen Mode while") {
            Toggle("Sharing the screen", isOn: $settings.autoZenWhileSharingScreen)
                .help("While you share your screen or mirror a display. macOS offers no way to see that another app is recording the screen, so recordings are not covered.")
            Toggle("Camera or microphone", isOn: $settings.zenModeWhileRecording)
                .help("While any app uses the camera or microphone, such as during a call.")
        }
        .annotation(
            "Zen Mode keeps hidden items out of sight, so a cluttered bar stays out of a call or a shared screen.",
            more: "It turns off again when sharing stops or the camera and microphone go idle. While the camera or microphone is on, turning Zen Mode off by hand puts it back within a second."
        )
    }
}
