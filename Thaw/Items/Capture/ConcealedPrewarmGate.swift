//
//  ConcealedPrewarmGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Decides whether Capture Hidden Items may reveal hidden items to photograph them.
/// Nothing else reveals them for a picture.
nonisolated enum ConcealedPrewarmGate {
    /// The decision for the app as it is now.
    @MainActor
    static func mayReveal(for appState: AppState?) -> Bool {
        mayReveal(
            hasSectionController: appState?.menuBarManager.sectionController != nil,
            screenRecordingGranted: appState?.isPermissionGranted(.screenRecording) == true
        )
    }

    /// No reveal without Screen Recording: there would be nothing to photograph.
    static func mayReveal(hasSectionController: Bool, screenRecordingGranted: Bool) -> Bool {
        hasSectionController && screenRecordingGranted
    }
}
