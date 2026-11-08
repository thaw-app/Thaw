//
//  VisibilitySettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Observation
import ThawUI

/// Model for the Visibility page's settings.
@MainActor
@Observable
final class VisibilitySettings: SettingsURIHandling {
    var showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay {
        didSet {
            guard oldValue != showOnHoverDelay else { return }
            Defaults.set(showOnHoverDelay, forKey: .showOnHoverDelay)
        }
    }

    var tooltipDelay = Defaults.DefaultValue.tooltipDelay {
        didSet {
            guard oldValue != tooltipDelay else { return }
            Defaults.set(tooltipDelay, forKey: .tooltipDelay)
        }
    }

    /// Enables tooltips in the actual menu bar, not just panels and settings.
    var showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips {
        didSet {
            guard oldValue != showMenuBarTooltips else { return }
            Defaults.set(showMenuBarTooltips, forKey: .showMenuBarTooltips)
        }
    }

    /// Automatic zen mode for mirroring or sharing; see PresentationMonitor for detection limits.
    var autoZenWhileSharingScreen = Defaults.DefaultValue.autoZenWhileSharingScreen {
        didSet {
            guard oldValue != autoZenWhileSharingScreen else { return }
            Defaults.set(autoZenWhileSharingScreen, forKey: .autoZenWhileSharingScreen)
        }
    }

    /// Readouts show item text below the bar on hover; no reads or drawing while disabled, and no polling without a visible readout.
    var enableMenuBarItemDescenders = Defaults.DefaultValue.enableMenuBarItemDescenders {
        didSet {
            guard oldValue != enableMenuBarItemDescenders else { return }
            Defaults.set(enableMenuBarItemDescenders, forKey: .enableMenuBarItemDescenders)
        }
    }

    var enableSwapBar = Defaults.DefaultValue.enableSwapBar {
        didSet {
            guard oldValue != enableSwapBar else { return }
            Defaults.set(enableSwapBar, forKey: .enableSwapBar)
        }
    }

    /// Whether a plain click on the Thaw icon swaps Visible and Hidden instead
    /// of revealing the hidden section.
    var swapOnThawIconClick = Defaults.DefaultValue.swapOnThawIconClick {
        didSet {
            guard oldValue != swapOnThawIconClick else { return }
            Defaults.set(swapOnThawIconClick, forKey: .swapOnThawIconClick)
        }
    }

    var showAlwaysHiddenOnIconDoubleClick = Defaults.DefaultValue.showAlwaysHiddenOnIconDoubleClick {
        didSet {
            guard oldValue != showAlwaysHiddenOnIconDoubleClick else { return }
            Defaults.set(showAlwaysHiddenOnIconDoubleClick, forKey: .showAlwaysHiddenOnIconDoubleClick)
        }
    }

    /// Samples camera presence and per-app microphone activity only while enabled.
    var enableRecordingWatch = Defaults.DefaultValue.enableRecordingWatch {
        didSet {
            guard oldValue != enableRecordingWatch else { return }
            Defaults.set(enableRecordingWatch, forKey: .enableRecordingWatch)
        }
    }

    /// Presenter mode: collapse the menu bar to zen mode while the camera or
    /// microphone is in use. Rides the recording watch's detector.
    var zenModeWhileRecording = Defaults.DefaultValue.zenModeWhileRecording {
        didSet {
            guard oldValue != zenModeWhileRecording else { return }
            Defaults.set(zenModeWhileRecording, forKey: .zenModeWhileRecording)
        }
    }

    /// Pointer-following announcements can be pinned for visibility away from the desk.
    /// Resolve each event so changes apply immediately; disconnected targets fall back to the primary display.
    var recordingWatchScreen = Defaults.DefaultValue.recordingWatchScreen {
        didSet {
            guard oldValue != recordingWatchScreen else { return }
            Defaults.set(recordingWatchScreen.storageKey, forKey: .recordingWatchScreen)
        }
    }

    /// Defaults to the shared HUD center, with alternatives to keep announcements out of the work area.
    /// Read per event so placement changes need no relaunch.
    var recordingWatchPlacement = Defaults.DefaultValue.recordingWatchPlacement {
        didSet {
            guard oldValue != recordingWatchPlacement else { return }
            Defaults.set(recordingWatchPlacement.rawValue, forKey: .recordingWatchPlacement)
        }
    }

    /// Search opens at its saved location, centered, or at the pointer; defaults to inspector.
    /// Read on each opening rather than watched because Settings focus closes the panel.
    var menuBarSearchPresentation = Defaults.DefaultValue.menuBarSearchPresentation {
        didSet {
            guard oldValue != menuBarSearchPresentation else { return }
            Defaults.set(menuBarSearchPresentation.rawValue, forKey: .menuBarSearchPresentation)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    var showOnClick = Defaults.DefaultValue.showOnClick {
        didSet {
            guard oldValue != showOnClick else { return }
            Defaults.set(showOnClick, forKey: .showOnClick)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    var showOnHover = Defaults.DefaultValue.showOnHover {
        didSet {
            guard oldValue != showOnHover else { return }
            Defaults.set(showOnHover, forKey: .showOnHover)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    var showOnScroll = Defaults.DefaultValue.showOnScroll {
        didSet {
            guard oldValue != showOnScroll else { return }
            Defaults.set(showOnScroll, forKey: .showOnScroll)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    var autoRehide = Defaults.DefaultValue.autoRehide {
        didSet {
            guard oldValue != autoRehide else { return }
            Defaults.set(autoRehide, forKey: .autoRehide)
        }
    }

    /// A strategy that determines how the auto-rehide feature works.
    var rehideStrategy = Defaults.DefaultValue.rehideStrategy {
        didSet {
            guard oldValue != rehideStrategy else { return }
            Defaults.set(rehideStrategy.rawValue, forKey: .rehideStrategy)
        }
    }

    /// A time interval for the auto-rehide feature when its rule
    /// is RehideStrategy.timed.
    var rehideInterval = Defaults.DefaultValue.rehideInterval {
        didSet {
            guard oldValue != rehideInterval else { return }
            Defaults.set(rehideInterval, forKey: .rehideInterval)
        }
    }

    /// Time interval temporarily shown menu bar items remain visible.
    var tempShowInterval = Defaults.DefaultValue.tempShowInterval {
        didSet {
            guard oldValue != tempShowInterval else { return }
            Defaults.set(tempShowInterval, forKey: .tempShowInterval)
        }
    }

    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    func performSetup() {
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    /// Reads the stored values.
    func loadInitialState() {
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tooltipDelay, assign: &tooltipDelay)
        Defaults.ifPresent(key: .showMenuBarTooltips, assign: &showMenuBarTooltips)
        Defaults.ifPresent(key: .autoZenWhileSharingScreen, assign: &autoZenWhileSharingScreen)
        Defaults.ifPresent(key: .enableMenuBarItemDescenders, assign: &enableMenuBarItemDescenders)
        // Read the legacy key first so the current key takes precedence.
        Defaults.ifPresent(key: .legacyEnableTransportBar, assign: &enableSwapBar)
        Defaults.ifPresent(key: .enableSwapBar, assign: &enableSwapBar)
        Defaults.ifPresent(key: .swapOnThawIconClick, assign: &swapOnThawIconClick)
        Defaults.ifPresent(key: .showAlwaysHiddenOnIconDoubleClick, assign: &showAlwaysHiddenOnIconDoubleClick)
        Defaults.ifPresent(key: .enableRecordingWatch, assign: &enableRecordingWatch)
        Defaults.ifPresent(key: .zenModeWhileRecording, assign: &zenModeWhileRecording)
        Defaults.ifPresent(key: .recordingWatchScreen) { (raw: String) in
            if let choice = RecordingWatchScreen.from(storageKey: raw) {
                recordingWatchScreen = choice
            }
        }
        Defaults.ifPresent(key: .recordingWatchPlacement) { (raw: String) in
            if let placement = ThawHUDPlacement(rawValue: raw) {
                recordingWatchPlacement = placement
            }
        }
        Defaults.ifPresent(key: .menuBarSearchPresentation) { (raw: String) in
            if let presentation = SearchPresentation(storedValue: raw) {
                menuBarSearchPresentation = presentation
            }
        }
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval, assign: &rehideInterval)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)
        Defaults.ifPresent(key: .rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }
    }

    /// The thaw:// keys of this page's Bool settings.
    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<VisibilitySettings, Bool>] = [
        "showMenuBarTooltips": \.showMenuBarTooltips,
        "autoZenWhileSharingScreen": \.autoZenWhileSharingScreen,
        "enableMenuBarItemDescenders": \.enableMenuBarItemDescenders,
        "enableSwapBar": \.enableSwapBar,
        "swapOnThawIconClick": \.swapOnThawIconClick,
        "showAlwaysHiddenOnIconDoubleClick": \.showAlwaysHiddenOnIconDoubleClick,
        "enableRecordingWatch": \.enableRecordingWatch,
        "zenModeWhileRecording": \.zenModeWhileRecording,
        "showOnClick": \.showOnClick,
        "showOnHover": \.showOnHover,
        "showOnScroll": \.showOnScroll,
        "autoRehide": \.autoRehide,
    ]

    /// The thaw:// keys of this page's Double settings.
    private static let uriDoubleKeys: [String: ReferenceWritableKeyPath<VisibilitySettings, Double>] = [
        "showOnHoverDelay": \.showOnHoverDelay,
        "tooltipDelay": \.tooltipDelay,
        "rehideInterval": \.rehideInterval,
        "tempShowInterval": \.tempShowInterval,
    ]

    /// Applies a thaw:// settings change for one of this page's keys.
    func handleExternalSettingsChange(_ notification: Notification) {
        if applySettingsURIChange(notification, bools: Self.uriBoolKeys, doubles: Self.uriDoubleKeys) {
            return
        }
        // Enums arrive as raw integers.
        if notification.userInfo?["key"] as? String == "rehideStrategy", let rawEnumValue = notification.userInfo?["rawEnumValue"] as? Int, let strategy = RehideStrategy(rawValue: rawEnumValue), rehideStrategy != strategy {
            rehideStrategy = strategy
        }
    }
}
