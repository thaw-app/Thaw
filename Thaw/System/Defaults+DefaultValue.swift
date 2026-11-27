//
//  Defaults+DefaultValue.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import ThawUI

extension Defaults {
    nonisolated enum DefaultValue {
        // MARK: General Settings (see Defaults+General.swift)

        static let roundScreenCorners = false
        static let screenCornerRadius = 10.0

        /// Native Always-Hidden: writes NSStatusItem VisibleCC <label> = false
        /// into the owning app's domain so the host stops publishing the item.
        /// Touches other apps' domains, so off until validated. Default: false.
        static let useNativeAlwaysHide = false
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
        static let enableMenuBarItemOverflow = false
        static let menuBarArrangementMode = MenuBarArrangementMode.automatic
        static let enableExperimentalOverflowPrevention = false
        static let alwaysUseAppIconForMenuBarItems = false
        static let enableMenuBarItemDescenders = false
        static let enableSwapBar = false
        static let swapOnThawIconClick = false
        static let showAlwaysHiddenOnIconDoubleClick = true
        static let enableControlItemPanel = false
        static let swapActive = false
        static let fetchReleaseNotes = true
        static let showReleaseNotesAfterUpdate = true
        static let showSpaceIndicator = false
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
        /// Wi-Fi, Bluetooth and Sound stand-ins turned on, by raw value.
        static let optInStandIns: [String] = []
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

        /// On by default: Settings runs in a process of its own, so its memory goes away when the window closes.
        static let settingsInOwnProcess = true

        /// Input-idle window (ms) before a synthetic move warps the cursor, so
        /// it never lands between the user's own movements. Default: 50.
        static let inputPauseThresholdMs = 50

        /// Edit Layout opens the SwiftUI reorder editor, in its own window, in place of the Layout pane pop-out. Default: false.
    }
}
