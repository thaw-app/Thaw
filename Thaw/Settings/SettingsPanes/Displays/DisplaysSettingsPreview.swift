//
//  DisplaysSettingsPreview.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

#if DEBUG
    extension DisplaySettingsManager {
        /// A saved display that isn't connected: the Displays preview shows it in the Not connected
        /// picker with Forget Display, and the Thaw Bar preview lists it in its display picker.
        /// Forgetting it changes only the preview's settings.
        func addPreviewSavedDisplay() {
            knownDisplays["0F0F0F0F-0000-4000-8000-000000000001"] = KnownDisplay(name: "Studio Display", hasNotch: false)
        }
    }
#endif
