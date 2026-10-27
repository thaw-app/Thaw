//
//  AppNavigationState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import ThawCapture

/// The model for app-wide navigation.
@MainActor
@Observable
final class AppNavigationState {
    nonisolated enum SettingsDisclosure: Hashable {
        case layoutSpacers
        /// Layout's Options tab, which holds the settings you rarely change.
        case layoutOptions
        case layoutAppleItems
        /// Appearance's fill tabs, inside and behind the shape.
        case appearanceInsideShape
        case appearanceBehindShape
    }

    var isAppFrontmost = false
    var isSettingsPresented = false {
        didSet {
            if isSettingsPresented || oldValue {
                settingsPresentationID = nil
            }
            updateCaptureUIState()
        }
    }

    var isThawBarPresented = false {
        didSet { updateCaptureUIState() }
    }

    var isSearchPresented = false {
        didSet { updateCaptureUIState() }
    }

    var isLayoutEditorPresented = false {
        didSet { updateCaptureUIState() }
    }

    /// Simple Mode has no sidebar, so its capture state cannot use the full window's last pane.
    /// Seed from preferences for presentations that begin before view synchronization.
    var isSimpleModeSettings = Defaults.bool(forKey: .simpleMode) {
        didSet { updateCaptureUIState() }
    }

    /// Keep capture off for panes such as General and About so they do not light the recording indicator.
    /// This includes Appearance's background sampler; item-glyph demand uses
    /// MenuBarItemImageCache.NavigationStateSnapshot.liveCaptureScope instead.
    private var settingsConsumesCapture: Bool {
        // Simple Mode opens on the folded bar, which draws real glyphs.
        if isSimpleModeSettings {
            return true
        }
        return switch settingsNavigationIdentifier {
        case .menuBarLayout, .thawBar, .menuBarAppearance, .hotkeys:
            true
        default:
            false
        }
    }

    var hasVisibleCaptureUI: Bool {
        isThawBarPresented || isSearchPresented || isLayoutEditorPresented
            || (isSettingsPresented && settingsConsumesCapture)
    }

    private var settingsPresentationID: UUID?

    var hasCaptureUI: Bool {
        hasVisibleCaptureUI
            || (settingsPresentationID != nil && settingsConsumesCapture)
    }

    func beginSettingsPresentation() -> UUID? {
        guard !isSettingsPresented, settingsPresentationID == nil else { return nil }
        let id = UUID()
        settingsPresentationID = id
        updateCaptureUIState()
        return id
    }

    func finishSettingsPresentation(_ id: UUID) {
        guard settingsPresentationID == id else { return }
        cancelSettingsPresentation()
    }

    func cancelSettingsPresentation() {
        settingsPresentationID = nil
        updateCaptureUIState()
    }

    private func updateCaptureUIState() {
        ScreenCapture.setCaptureUIActive(hasCaptureUI)
    }

    var requestedSettingsDisclosure: SettingsDisclosure?

    /// The section of the search result being opened, so a page with tabs opens the tab holding it.
    var requestedSettingsSection: String?

    /// AppState selects About after window construction; the pane consumes this upgrade request by presenting the changelog.
    var isWhatsNewRequested = false

    var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general {
        didSet {
            // Observation routes this assignment back through didSet, which then saves it.
            let destination = settingsNavigationIdentifier.destination
            guard destination == settingsNavigationIdentifier else {
                settingsNavigationIdentifier = destination
                return
            }
            // A search sets its section after the page, so only a section left from another page is dropped.
            if settingsNavigationIdentifier != oldValue {
                requestedSettingsSection = nil
            }
            Defaults.set(settingsNavigationIdentifier.rawValue, forKey: .lastSettingsPane)
            // Which pane is showing decides whether capture is on, so moving
            // from General to Layout has to re-evaluate without a window toggle.
            updateCaptureUIState()
        }
    }

    init() {
        updateCaptureUIState()
        // Restore the full window's last pane for returning from Simple Mode; init assignment does not persist via didSet.
        // Ignore panes no longer in the sidebar so selection and detail stay connected.
        if let rawValue = Defaults.string(forKey: .lastSettingsPane),
           let pane = SettingsNavigationIdentifier(rawValue: rawValue)?.destination,
           SettingsSidebarPanes.all.contains(pane)
        {
            settingsNavigationIdentifier = pane
        }
        // Panes hidden by the old customizable sidebar show again.
        Defaults.removeObject(forKey: .hiddenSidebarPanes)
    }
}
