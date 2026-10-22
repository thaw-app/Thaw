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

    /// Without Screen Recording a reveal can't be photographed and would only
    /// flash hidden items on the bar. With native hiding a reveal switches the
    /// app back on in macOS's own list, which rebuilds the bar. The item then
    /// lands beside macOS's chevron, where its picture is refused, so these
    /// items keep the picture taken while they were shown.
    static func mayReveal(
        hasSectionController: Bool,
        screenRecordingGranted: Bool,
        nativeHidingActive: Bool
    ) -> Bool {
        hasSectionController && screenRecordingGranted && !nativeHidingActive
    }
}
