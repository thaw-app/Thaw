//
//  RuntimeSectionContextAdapter+NativeHiding.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit

extension RuntimeSectionContextAdapter {
    /// The kit reads this at launch only, before NativeAppHidingExperiment has started.
    var startsWithNativeAppHiding: Bool {
        appState?.settings.layout.enableNativeAppHiding ?? false
    }
}
