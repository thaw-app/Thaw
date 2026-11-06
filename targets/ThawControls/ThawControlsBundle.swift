//
//  ThawControlsBundle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// The bundle carries controls only, no widgets and no Live Activities, so
// the extension stays a thin, stateless shim in front of the Darwin
// notification bridge described in ControlCommandNames.swift.

import SwiftUI
import WidgetKit

@main
struct ThawControlsBundle: WidgetBundle {
    var body: some Widget {
        RevealHiddenItemsControl()
        ToggleZenModeControl()
    }
}
