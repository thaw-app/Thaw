//
//  ConcealedPrewarmGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Decides whether a prewarm may reveal hidden items to photograph them.
nonisolated enum ConcealedPrewarmGate {
    /// The decision for the app as it is now.
    @MainActor
    static func mayReveal(for appState: AppState?) -> Bool {
        mayReveal(
            hasSectionController: appState?.menuBarManager.sectionController != nil,
            screenRecordingGranted: appState?.isPermissionGranted(.screenRecording) == true,
            nativeHidingActive: appState?.menuBarManager.nativeAppHidingExperiment.isActive == true
        )
    }

    /// No reveal without Screen Recording (nothing to photograph) or under Native hiding
    /// (the reveal rebuilds the bar and the picture is refused).
    static func mayReveal(
        hasSectionController: Bool,
        screenRecordingGranted: Bool,
        nativeHidingActive: Bool
    ) -> Bool {
        hasSectionController && screenRecordingGranted && !nativeHidingActive
    }
}
