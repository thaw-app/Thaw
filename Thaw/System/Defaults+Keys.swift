//
//  Defaults+Keys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension Defaults {
    enum Key: String {
        // MARK: General Settings

        case showThawIcon = "ShowIceIcon"
        case thawIcon = "IceIcon"
        case customThawIconIsTemplate = "CustomIceIconIsTemplate"
        case simpleMode = "SimpleMode"
        case profilesEnabled = "ProfilesEnabled"
        case showSettingDescriptions = "ShowSettingDescriptions"
        case blackSettingsBackground = "BlackSettingsBackground"
        case settingsAppearance = "SettingsAppearance"
        case simpleModeShowsPreview = "SimpleModeShowsPreview"
        case lastSettingsPane = "LastSettingsPane"
        case hiddenSidebarPanes = "HiddenSidebarPanes"
        case settingsInOwnProcess = "SettingsInOwnProcess"
        case menuBarItemAlertReveals = "MenuBarItemAlertReveals"
        case autoZenWhileSharingScreen = "AutoZenWhileSharingScreen"
        case menuBarAppearanceSpaceOverrides = "MenuBarAppearanceSpaceOverrides"
        case lockThawBarPosition = "LockThawBarPosition"
        case openHiddenItemsInMenuBar = "OpenHiddenItemsInMenuBar"
        case roundScreenCorners = "RoundScreenCorners"
        case screenCornerRadius = "ScreenCornerRadius"
        case menuBarSpacers = "MenuBarSpacers"
        case enableExperimentalRevealSystemExtras = "EnableExperimentalRevealSystemExtras"
        case useThawBar = "UseIceBar"
        case useThawBarOnlyOnNotchedDisplay = "UseIceBarOnlyOnNotchedDisplay"
        case thawBarLocation = "ThawBarLocation"
        case thawBarLocationOnHotkey = "ThawBarLocationOnHotkey"
        case showOnClick = "ShowOnClick"
        case showOnHover = "ShowOnHover"
        case showOnScroll = "ShowOnScroll"
        case autoRehide = "AutoRehide"
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case displayThawBarConfigurations = "DisplayIceBarConfigurations"
        case globalDisplayConfiguration = "GlobalDisplayConfiguration"
        case knownDisplays = "KnownDisplays"
        case confirmSpacingRelaunch = "ConfirmSpacingRelaunch"
        case unconfirmedSpacingProfileScope = "UnconfirmedSpacingProfileScope"
        case spacingApplyMode = "SpacingApplyMode"
        case showEveryItemOnWideDisplays = "ShowEveryItemOnWideDisplays"
        case wideDisplayMinimumWidth = "WideDisplayMinimumWidth"

        // MARK: Hotkeys Settings

        case hotkeys = "Hotkeys"
        case profileHotkeys = "ProfileHotkeys"
        /// Triggers saved before they moved to the Triggers module. Thaw only
        /// checks whether any exist, to start that module switched on.
        case appRunningTriggers = "AppRunningTriggersV1"
        case menuBarItemHotkeys = "MenuBarItemHotkeys"

        // MARK: Advanced Settings

        case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
        case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
        case newItemsSection = "NewItemsSection"
        case newItemsPlacementData = "NewItemsPlacementData"
        case sectionDividerStyle = "SectionDividerStyle"
        case customSectionDividerImage = "CustomSectionDividerImage"
        case customSectionDividerIsTemplate = "CustomSectionDividerIsTemplate"
        case hideApplicationMenus = "HideApplicationMenus"
        case enableSecondaryContextMenu = "EnableSecondaryContextMenu"
        case showOnHoverDelay = "ShowOnHoverDelay"
        case tempShowInterval = "TempShowInterval"
        case tooltipDelay = "TooltipDelay"
        case iconRefreshInterval = "IconRefreshInterval"
        case showMenuBarTooltips = "ShowMenuBarTooltips"
        case enableDiagnosticLogging = "EnableDiagnosticLogging"
        case enableMenuBarItemOverflow = "EnableMenuBarItemOverflow"
        case enableExperimentalSystemItemHiding = "EnableExperimentalSystemItemHiding"
        /// Who arranges the menu bar: Thaw (MenuBarArrangementMode.automatic)
        /// or the person using it (MenuBarArrangementMode.manual). Manual
        /// stops every Thaw-performed move and every position-table write.
        case menuBarArrangementMode = "MenuBarArrangementMode"
        case enableExperimentalOverflowPrevention = "EnableExperimentalOverflowPrevention"
        case alwaysUseAppIconForMenuBarItems = "AlwaysUseAppIconForMenuBarItems"
        case menuBarOrderFulfillmentTimeout = "MenuBarOrderFulfillmentTimeout"
        /// Routes menu bar item captures through the MenuBarCaptureService
        /// XPC helper instead of in-process ScreenCaptureKit, containing
        /// SkyLight's per-call dictionary leak in a bounded-lifetime helper.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case captureViaXPCService = "CaptureViaXPCService"
        /// Hidden diagnostic flag: route the ambient menu bar walk through the AX helper.
        case axEnumerationViaSubprocess = "AXEnumerationViaSubprocess"
        case diagnosticRestrictionSceneProbes = "Thaw.diagnosticRestrictionSceneProbes"
        case diagnosticRestrictionProbeHiddenTriggerPress = "Thaw.diagnosticRestrictionProbeHiddenTriggerPress"
        case debugSimulateNotch = "Thaw.debugSimulateNotch"
        /// Hangs a small readout below a menu bar item while the pointer
        /// rests on it. Read live so the descenders appear and disappear
        /// without relaunching.
        case enableMenuBarItemDescenders = "EnableMenuBarItemDescenders"
        /// The Swap bar: a floating strip at the bottom of the pointer's
        /// display that swaps the shown and hidden groups, with the active
        /// profile and the section and zen toggles beside it. Read live so
        /// the panel comes and goes with the switch.
        case enableSwapBar = "EnableSwapBar"
        case swapOnThawIconClick = "SwapOnThawIconClick"
        /// The control item panel, hung under Thaw's own icon. Read live so the
        /// secondary click changes what it raises without a relaunch.
        case enableControlItemPanel = "EnableControlItemPanel"
        /// The Swap bar's key while it was the Lab "transport bar". Read once
        /// at launch so a tester who had it on keeps it; never written.
        case legacyEnableTransportBar = "EnableTransportBar"
        /// Whether the last swap left the groups traded; persisted because the
        /// swap itself outlives the process.
        case swapActive = "SwapActive"
        /// Whether What's New may fetch the latest notes from the repository.
        /// Off, it shows the notes that shipped with the build. A Privacy
        /// switch, so it is read live.
        case fetchReleaseNotes = "FetchReleaseNotes"
        /// Names the app holding the microphone, and reports that a camera is
        /// on, where macOS shows only a dot. Read live so the poller starts
        /// and stops without relaunching.
        case enableRecordingWatch = "EnableRecordingWatch"
        case enableNativeAppHiding = "EnableNativeAppHiding"
        /// Per-extra stand-ins. Read live so flipping one reconciles only the
        /// extra it names.
        case enableModuleStandIns = "EnableModuleStandIns"
        case skippedModuleStandIns = "SkippedModuleStandIns"
        case enableTimeMachineTakeover = "EnableTimeMachineTakeover"
        case enableTimerTakeover = "EnableTimerTakeover"
        case enableTextInputTakeover = "EnableTextInputTakeover"
        case zenModeWhileRecording = "ZenModeWhileRecording"
        /// Where the recording watch's announcements appear. Stored as the
        /// enum's string tag, since the display case carries an associated
        /// UUID that a raw value cannot hold.
        case recordingWatchScreen = "RecordingWatchScreen"
        /// Where along the top of the chosen display the recording watch's
        /// announcements appear. Stored as the placement's raw value.
        case recordingWatchPlacement = "RecordingWatchPlacement"
        case enableDesktopMenuHiding = "EnableDesktopMenuHiding"
        /// Persisted per-item volatility records. JSON blob
        /// keyed by tagIdentifier; see MenuBarItemVolatilityIndex.
        case menuBarItemVolatilityIndex = "MenuBarItemVolatilityIndex"
        /// Width in points of the debug overflow spacer status item
        /// (chevron-herding experiment). 0 or absent = no spacer. See
        /// OverflowSpacer.
        case debugOverflowSpacerWidth = "Thaw.debugOverflowSpacerWidth"

        // MARK: Search

        case rememberSearchQuery = "RememberSearchQuery"
        case menuBarSearchRecents = "MenuBarSearchRecents"
        /// Where the search panel opens: remembered, centered, or at the
        /// pointer. Stored as the SearchPresentation case's raw value.
        case menuBarSearchPresentation = "MenuBarSearchPresentation"

        // MARK: Internal

        case menuBarSearchPanelFrameWithConfig = "MenuBarSearchPanelFrame_"

        /// The marketing version whose release notes the user has been shown
        /// (or implicitly skipped). Absent until first recorded, and absence
        /// means a fresh install, which never gets the What's New sheet.
        case lastWhatsNewVersion = "LastWhatsNewVersion"

        // MARK: Menu Bar Item Custom Names

        case menuBarItemCustomNames = "MenuBarItemCustomNames"

        /// The overlay strip's persisted item widths, as JSON keyed by
        /// canonical persistent identifier. Written by the Overlay Menu Bar
        /// while engaged; read when a concealed item has no saner width
        /// source. Absent until the first recorded measurement.
        case overlayItemWidths = "OverlayItemWidths"

        // MARK: Menu Bar Layout Table Access

        /// The bookmark for MenuBarAgent's layout table from the open panel,
        /// letting later launches re-take the grant. Absent by default.
        case menuBarLayoutTableBookmark = "MenuBarLayoutTableBookmark"

        // MARK: Menu Bar Item Groups

        /// User-authored menu bar item groups, as a JSON-encoded
        /// MenuBarItemGroupSet. Absent when the user has never created or
        /// dissolved a group, which is the default and means "no groups".
        case menuBarItemGroups = "MenuBarItemGroups"

        // MARK: Internal (Event Delivery)

        /// Items whose owners have recently failed to answer synthetic
        /// events, keyed by namespace and title. Managed by
        /// MenuBarItemFailureLedger; not exposed in Settings.
        case unresponsiveMenuBarItems = "UnresponsiveMenuBarItems"

        /// Items whose moves have repeatedly returned cannotComplete and are
        /// treated as unmovable across launches. Managed by
        /// MenuBarItemFailureLedger; not exposed in Settings.
        case cannotCompleteMenuBarItems = "CannotCompleteMenuBarItems"
        case strandedMenuBarItems = "StrandedMenuBarItems"

        /// Build string the failure-ledger marks were last written against. On
        /// a version change the marks are dropped so a Thaw or OS fix re-tests
        /// every item. Managed by MenuBarItemFailureLedger.
        case menuBarFailureLedgerVersion = "MenuBarFailureLedgerVersion"

        /// Seconds an accessibility message may block before it fails.
        ///
        /// Applied to every AXElement as it is wrapped. 0 restores the
        /// system default of six seconds.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 1.0.
        case axMessagingTimeout

        /// Whether automatic section-order passes plan drags with the LCS
        /// planner (see DefaultValue.useLCSSectionOrderPlanner).
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case useLCSSectionOrderPlanner

        /// Input-idle window (ms) required before a cursor-warping synthetic
        /// move (see DefaultValue.inputPauseThresholdMs).
        ///
        /// Hidden escape hatch; not exposed in Settings. Default: 50.
        case inputPauseThresholdMs

        /// Whether Edit Layout opens the SwiftUI reorder editor (see DefaultValue.useReorderLayoutEditor).
        /// Hidden; not exposed in Settings. Default: false.
        case useReorderLayoutEditor

        /// Whether Always-Hidden members are natively hidden via their
        /// owners' preference domains (see DefaultValue.useNativeAlwaysHide).
        ///
        /// Hidden; not exposed in Settings. Default: false.
        case useNativeAlwaysHide

        /// Hidden diagnostic: turns off the bridge that lets the Clock and the
        /// system shortcut open Notification Center while items are hidden.
        case disableNotificationCenterBridge

        // MARK: Appearance Settings

        case menuBarAppearanceConfigurationV2 = "MenuBarAppearanceConfigurationV2"

        // MARK: Migration

        /// Pinned to the Ice-era key string already written to disk.
        case hasMigratedPerDisplayThawBar = "hasMigratedPerDisplayIceBar"

        // MARK: First Launch

        case hasCompletedFirstLaunch

        // MARK: Reduced Mode

        case reducedModeChosen
        case reducedModeHiddenBundleIDs

        // MARK: Updates Consent

        case hasSeenUpdateConsent

        // MARK: Native Hiding

        /// The user answered the one-time offer to show apps an older
        /// version may have left switched off in System Settings.
        case hasAnsweredHiddenAppsRestoreOffer

        // MARK: Onboarding

        case hasSeenOnboarding

        /// The onboarding version the user last finished; absent reads as 0.
        /// hasSeenOnboarding alone cannot tell an upgrader from a returning
        /// user, so OnboardingSequencer compares this to welcome upgraders once.
        case onboardingVersion = "OnboardingVersion"

        /// Raw values of the FirstRunHints the user has retired, read and
        /// written only through FirstRunHintStore. Absent until the first
        /// dismissal, which reads as an empty array.
        case dismissedFirstRunHints

        /// Recorded at launch when an upgrade predates multi-select so TipKit can wait until Layout opens.
        case pendingMultiSelectTip
        /// Recorded once multi-select is used so TipKit does not boot on later launches.
        case hasRetiredMultiSelectTip

        // MARK: Settings URI

        case settingsURIEnabled = "SettingsURIEnabled"
        case settingsURIWhitelist = "SettingsURIWhitelist"
        case settingsURISigningIdentities = "SettingsURISigningIdentities"
        case settingsURICodeHashes = "SettingsURICodeHashes"

        // MARK: Profiles

        case lastSettledProfileID = "LastSettledProfileID"

        // MARK: Modules

        case enabledModules = "EnabledModules"
        /// Settings left from before their features became modules. Thaw only
        /// checks whether they exist, to start each module switched on.
        case globalPreProfileHook = "GlobalPreProfileHook"
        case globalPostProfileHook = "GlobalPostProfileHook"
        case lastActiveProfileID = "LastActiveProfileID"
        case widgetIconPublished = "StatusIconPrototype.published"
    }
}
