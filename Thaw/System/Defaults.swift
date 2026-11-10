//
//  Defaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import ThawUI

/// Typed access to the app's UserDefaults domain.
///
/// Forwards to store with a typed Key, so each settings name is spelled once.
/// Missing values, coercion and thread safety are UserDefaults' own.
nonisolated enum Defaults {
    /// The store every accessor below reads and writes.
    ///
    /// Only tests assign this, pointing at a scratch suite, since per-key
    /// restore cannot protect the real domain under parallel tests. The
    /// unchecked annotation covers only that test-setup reassignment.
    static nonisolated(unsafe) var store: UserDefaults = .standard {
        didSet {
            // A scratch suite starts with no registered defaults, so re-register
            // whenever the facade is pointed somewhere new.
            registerDefaults()
        }
    }

    /// Returns a dictionary containing the keys and values for
    /// the defaults meant to be seen by all applications.
    static var globalDomain: [String: Any] {
        _ = registered
        return store.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    }

    static func object(forKey key: Key) -> Any? {
        _ = registered
        return store.object(forKey: key.rawValue)
    }

    static func string(forKey key: Key) -> String? {
        _ = registered
        return store.string(forKey: key.rawValue)
    }

    static func array(forKey key: Key) -> [Any]? {
        _ = registered
        return store.array(forKey: key.rawValue)
    }

    static func dictionary(forKey key: Key) -> [String: Any]? {
        _ = registered
        return store.dictionary(forKey: key.rawValue)
    }

    static func data(forKey key: Key) -> Data? {
        _ = registered
        return store.data(forKey: key.rawValue)
    }

    static func stringArray(forKey key: Key) -> [String]? {
        _ = registered
        return store.stringArray(forKey: key.rawValue)
    }

    static func integer(forKey key: Key) -> Int {
        _ = registered
        return store.integer(forKey: key.rawValue)
    }

    static func double(forKey key: Key) -> Double {
        _ = registered
        return store.double(forKey: key.rawValue)
    }

    static func bool(forKey key: Key) -> Bool {
        _ = registered
        return store.bool(forKey: key.rawValue)
    }

    static func url(forKey key: Key) -> URL? {
        _ = registered
        return store.url(forKey: key.rawValue)
    }

    static func set(_ value: Any?, forKey key: Key) {
        _ = registered
        store.set(value, forKey: key.rawValue)
    }

    static func removeObject(forKey key: Key) {
        _ = registered
        store.removeObject(forKey: key.rawValue)
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, assigns it to the given inout parameter.
    static func ifPresent<Value>(key: Key, assign value: inout Value) {
        if let found = object(forKey: key) as? Value {
            value = found
        }
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, performs the given closure.
    static func ifPresent<Value>(key: Key, body: (Value) throws -> Void) rethrows {
        if let found = object(forKey: key) as? Value {
            try body(found)
        }
    }

    /// The documented defaults that are plist values, keyed for registration.
    ///
    /// Values UserDefaults cannot hold are omitted; their readers fall back to
    /// DefaultValue. Computed because Any is not Sendable.
    private static var defaultRegistrationValues: [Key: Any] {
        [
            // General Settings
            .showThawIcon: DefaultValue.showThawIcon,
            .customThawIconIsTemplate: DefaultValue.customThawIconIsTemplate,
            .simpleMode: DefaultValue.simpleMode,
            .showSettingDescriptions: DefaultValue.showSettingDescriptions,
            // .settingsAppearance: unregistered, so its first read can tell it is unset and migrate.
            .simpleModeShowsPreview: DefaultValue.simpleModeShowsPreview,
            .lockThawBarPosition: DefaultValue.lockThawBarPosition,
            .openHiddenItemsInMenuBar: DefaultValue.openHiddenItemsInMenuBar,
            .roundScreenCorners: DefaultValue.roundScreenCorners,
            .screenCornerRadius: DefaultValue.screenCornerRadius,
            .useThawBar: DefaultValue.useThawBar,
            .useThawBarOnlyOnNotchedDisplay: DefaultValue.useThawBarOnlyOnNotchedDisplay,
            .useNativeAlwaysHide: DefaultValue.useNativeAlwaysHide,
            .thawBarLocation: DefaultValue.thawBarLocation.rawValue,
            .thawBarLocationOnHotkey: DefaultValue.thawBarLocationOnHotkey,
            .showOnClick: DefaultValue.showOnClick,
            .showOnHover: DefaultValue.showOnHover,
            .showOnScroll: DefaultValue.showOnScroll,
            .autoRehide: DefaultValue.autoRehide,
            .rehideStrategy: DefaultValue.rehideStrategy.rawValue,
            .rehideInterval: DefaultValue.rehideInterval,

            // Advanced Settings
            .enableAlwaysHiddenSection: DefaultValue.enableAlwaysHiddenSection,
            .showAllSectionsOnUserDrag: DefaultValue.showAllSectionsOnUserDrag,
            .newItemsSection: DefaultValue.newItemsSection,
            .sectionDividerStyle: DefaultValue.sectionDividerStyle.rawValue,
            .customSectionDividerIsTemplate: DefaultValue.customSectionDividerIsTemplate,
            .hideApplicationMenus: DefaultValue.hideApplicationMenus,
            .enableSecondaryContextMenu: DefaultValue.enableSecondaryContextMenu,
            .showOnHoverDelay: DefaultValue.showOnHoverDelay,
            .tempShowInterval: DefaultValue.tempShowInterval,
            .tooltipDelay: DefaultValue.tooltipDelay,
            .showMenuBarTooltips: DefaultValue.showMenuBarTooltips,
            .iconRefreshInterval: DefaultValue.iconRefreshInterval,
            .autoZenWhileSharingScreen: DefaultValue.autoZenWhileSharingScreen,
            .enableDiagnosticLogging: DefaultValue.enableDiagnosticLogging,
            .enableMenuBarItemOverflow: DefaultValue.enableMenuBarItemOverflow,
            .menuBarArrangementMode: DefaultValue.menuBarArrangementMode.rawValue,
            .enableExperimentalOverflowPrevention: DefaultValue.enableExperimentalOverflowPrevention,
            .alwaysUseAppIconForMenuBarItems: DefaultValue.alwaysUseAppIconForMenuBarItems,
            .enableMenuBarItemDescenders: DefaultValue.enableMenuBarItemDescenders,
            // .enableSwapBar
            // Not registered: the legacy-key migration runs only while this
            // is unset, and unset already reads as false.
            .enableControlItemPanel: DefaultValue.enableControlItemPanel,
            .swapOnThawIconClick: DefaultValue.swapOnThawIconClick,
            .swapActive: DefaultValue.swapActive,
            .fetchReleaseNotes: DefaultValue.fetchReleaseNotes,
            .enableRecordingWatch: DefaultValue.enableRecordingWatch,
            .enableNativeAppHiding: DefaultValue.enableNativeAppHiding,
            .enableModuleStandIns: DefaultValue.enableModuleStandIns,
            .enableTimeMachineTakeover: DefaultValue.enableTimeMachineTakeover,
            .enableTimerTakeover: DefaultValue.enableTimerTakeover,
            .enableTextInputTakeover: DefaultValue.enableTextInputTakeover,
            .zenModeWhileRecording: DefaultValue.zenModeWhileRecording,
            .recordingWatchPlacement: DefaultValue.recordingWatchPlacement.rawValue,
            .enableDesktopMenuHiding: DefaultValue.enableDesktopMenuHiding,
            .menuBarOrderFulfillmentTimeout: DefaultValue.menuBarOrderFulfillmentTimeout,
            .captureViaXPCService: DefaultValue.captureViaXPCService,
            .axEnumerationViaSubprocess: DefaultValue.axEnumerationViaSubprocess,

            // Search
            .rememberSearchQuery: DefaultValue.rememberSearchQuery,
            .menuBarSearchPresentation: DefaultValue.menuBarSearchPresentation.rawValue,

            // Display Settings
            .confirmSpacingRelaunch: DefaultValue.confirmSpacingRelaunch,
            .unconfirmedSpacingProfileScope: DefaultValue.unconfirmedSpacingProfileScope.rawValue,
            .spacingApplyMode: DefaultValue.spacingApplyMode.rawValue,
            .showEveryItemOnWideDisplays: DefaultValue.showEveryItemOnWideDisplays,
            .wideDisplayMinimumWidth: DefaultValue.wideDisplayMinimumWidth,

            // Event Delivery
            .axMessagingTimeout: DefaultValue.axMessagingTimeout,
            .useLCSSectionOrderPlanner: DefaultValue.useLCSSectionOrderPlanner,
            .inputPauseThresholdMs: DefaultValue.inputPauseThresholdMs,
            .useReorderLayoutEditor: DefaultValue.useReorderLayoutEditor,
        ]
    }

    /// Registers defaultRegistrationValues against store.
    ///
    /// register(defaults:) layers the values below anything already written,
    /// so a user's stored choice always wins and this never overwrites one.
    static func registerDefaults() {
        let values = Dictionary(
            uniqueKeysWithValues: defaultRegistrationValues.map { ($0.key.rawValue, $0.value) }
        )
        store.register(defaults: values)
    }

    /// Runs registerDefaults() on first use.
    ///
    /// Every accessor reads this first, so registration never depends on
    /// app-launch code.
    private static let registered: Void = registerDefaults()
}

extension Defaults {
    nonisolated enum DefaultValue {
        // MARK: General Settings

        static let showThawIcon = true
        static let thawIcon = ControlItemImageSet.defaultThawIcon
        static let customThawIconIsTemplate = false
        static let simpleMode = false
        static let showSettingDescriptions = true
        static let simpleModeShowsPreview = true
        static let lockThawBarPosition = true
        static let openHiddenItemsInMenuBar = false
        static let roundScreenCorners = false
        static let screenCornerRadius = 10.0
        static let useThawBar = false
        static let useThawBarOnlyOnNotchedDisplay = false

        /// Native Always-Hidden: writes NSStatusItem VisibleCC <label> = false
        /// into the owning app's domain so the host stops publishing the item.
        /// Touches other apps' domains, so off until validated. Default: false.
        static let useNativeAlwaysHide = false
        static let thawBarLocation: ThawBarLocation = .dynamic
        static let thawBarLocationOnHotkey = false
        static let showOnClick = true
        static let showOnHover = false
        static let showOnScroll = true
        static let autoRehide = true
        static let rehideStrategy: RehideStrategy = .smart
        static let rehideInterval: TimeInterval = 15

        // MARK: Advanced Settings

        static let enableAlwaysHiddenSection = false
        static let showAllSectionsOnUserDrag = true
        static let newItemsSection = "hidden"
        static let sectionDividerStyle: SectionDividerStyle = .noDivider
        static let customSectionDividerIsTemplate = true
        static let hideApplicationMenus = true
        static let enableSecondaryContextMenu = true
        static let showOnHoverDelay: TimeInterval = 0.2
        static let tempShowInterval: TimeInterval = 15
        static let tooltipDelay: TimeInterval = 0.5
        static let showMenuBarTooltips = false
        static let iconRefreshInterval: TimeInterval = 0.25
        /// Minimum seconds between two alert reveals of the same item.
        static let autoZenWhileSharingScreen = false
        #if DEBUG
            static let enableDiagnosticLogging = true
        #else
            static let enableDiagnosticLogging = false
        #endif
        static let enableMenuBarItemOverflow = false
        static let menuBarArrangementMode = MenuBarArrangementMode.automatic
        static let enableExperimentalOverflowPrevention = false
        static let alwaysUseAppIconForMenuBarItems = false
        static let enableMenuBarItemDescenders = false
        static let enableSwapBar = false
        static let swapOnThawIconClick = false
        static let enableControlItemPanel = false
        static let swapActive = false
        static let fetchReleaseNotes = true
        static let enableRecordingWatch = false
        static let enableNativeAppHiding = false
        /// Stand-ins for Apple menu extras Thaw removes while they sit in a
        /// hidden section. Each is off by default and independent of the others.
        static let enableModuleStandIns = false
        /// The Control Center modules left as Apple's own while the others are
        /// replaced, by stand-in raw value. Empty replaces all four.
        static let skippedModuleStandIns: [String] = []
        static let enableTimeMachineTakeover = false
        static let enableTimerTakeover = false
        static let enableTextInputTakeover = false
        static let zenModeWhileRecording = false
        /// Where the recording watch's announcements appear: the storage key
        /// of a RecordingWatchScreen, parsed back on load.
        static let recordingWatchScreen = RecordingWatchScreen.screenWithPointer
        /// Where along the top of that display they appear.
        static let recordingWatchPlacement = ThawHUDPlacement.center
        static let enableDesktopMenuHiding = false
        static let menuBarOrderFulfillmentTimeout: TimeInterval = 3
        /// Route screen capture through the MenuBarCaptureService helper, so a
        /// leaking or wedged capture is retired with the helper, not the app.
        /// On unless a user turned it off.
        static let captureViaXPCService = true
        /// Route the ambient menu bar walk and the pointer-path reads and
        /// presses through the bundled AX helper, so a hung app blocks the
        /// helper instead of Thaw. On unless a user turned it off.
        static let axEnumerationViaSubprocess = true

        // MARK: Search

        static let rememberSearchQuery = false
        /// How the menu bar search panel opens. Stored as the case's raw
        /// value; the default is the behavior the panel shipped with.
        static let menuBarSearchPresentation = SearchPresentation.inspector

        // MARK: Hotkeys Settings

        static let hotkeys: [String: Data]? = nil

        // MARK: Appearance Settings

        static let menuBarAppearanceConfigurationV2 = MenuBarAppearanceConfigurationV2.defaultConfiguration

        // MARK: Display Settings

        static let displayThawBarConfigurations: [String: DisplayThawBarConfiguration] = [:]
        static let globalDisplayConfiguration: DisplayThawBarConfiguration = .defaultConfiguration
        static let confirmSpacingRelaunch = true
        static let unconfirmedSpacingProfileScope: SpacingProfileSaveScope = .activeProfile
        static let spacingApplyMode: SpacingApplyMode = .relaunchApps
        static let showEveryItemOnWideDisplays = false
        static let wideDisplayMinimumWidth: Double = 2560

        // MARK: Event Delivery

        static let axMessagingTimeout = 1.0

        /// On by default: plan section-order drags with the LCS planner, one
        /// move per misplaced item, instead of the pairwise walk.
        static let useLCSSectionOrderPlanner = true

        /// Input-idle window (ms) before a synthetic move warps the cursor, so
        /// it never lands between the user's own movements. Default: 50.
        static let inputPauseThresholdMs = 50

        /// Edit Layout opens the SwiftUI reorder editor, in its own window, in place of the Layout pane pop-out. Default: false.
        static let useReorderLayoutEditor = false
    }
}
