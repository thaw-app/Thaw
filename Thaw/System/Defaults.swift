//
//  Defaults.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI

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
            .lockThawBarPosition: DefaultValue.lockThawBarPosition,
            .enableThawBarOnly: DefaultValue.enableThawBarOnly,
            .openHiddenItemsInMenuBar: DefaultValue.openHiddenItemsInMenuBar,
            .roundScreenCorners: DefaultValue.roundScreenCorners,
            .screenCornerRadius: DefaultValue.screenCornerRadius,
            .showThawBarOnlyWithInlineReveal: DefaultValue.showThawBarOnlyWithInlineReveal,
            .showThawBarOnlyLauncher: DefaultValue.showThawBarOnlyLauncher,
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
            .hideApplicationMenus: DefaultValue.hideApplicationMenus,
            .enableSecondaryContextMenu: DefaultValue.enableSecondaryContextMenu,
            .showOnHoverDelay: DefaultValue.showOnHoverDelay,
            .tempShowInterval: DefaultValue.tempShowInterval,
            .tooltipDelay: DefaultValue.tooltipDelay,
            .showMenuBarTooltips: DefaultValue.showMenuBarTooltips,
            .iconRefreshInterval: DefaultValue.iconRefreshInterval,
            .menuBarItemAlertRevealCooldown: DefaultValue.menuBarItemAlertRevealCooldown,
            .autoZenWhileSharingScreen: DefaultValue.autoZenWhileSharingScreen,
            .enableDiagnosticLogging: DefaultValue.enableDiagnosticLogging,
            .enableMenuBarItemOverflow: DefaultValue.enableMenuBarItemOverflow,
            .enableExperimentalSystemItemHiding: DefaultValue.enableExperimentalSystemItemHiding,
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
            .searchSectionOrder: DefaultValue.searchSectionOrder,
            .searchIncludeVisible: DefaultValue.searchIncludeVisible,
            .searchIncludeHidden: DefaultValue.searchIncludeHidden,
            .searchIncludeAlwaysHidden: DefaultValue.searchIncludeAlwaysHidden,
            .menuBarSearchPresentation: DefaultValue.menuBarSearchPresentation.rawValue,

            // Display Settings
            .confirmSpacingRelaunch: DefaultValue.confirmSpacingRelaunch,
            .unconfirmedSpacingProfileScope: DefaultValue.unconfirmedSpacingProfileScope.rawValue,
            .spacingApplyMode: DefaultValue.spacingApplyMode.rawValue,

            // Event Delivery
            .axMessagingTimeout: DefaultValue.axMessagingTimeout,
            .addressMoveDragToMenuBarAgent: DefaultValue.addressMoveDragToMenuBarAgent,
            .addressMoveDragViaEventRecord: DefaultValue.addressMoveDragViaEventRecord,
            .useHeldCommandDrag: DefaultValue.useHeldCommandDrag,
            .useLCSSectionOrderPlanner: DefaultValue.useLCSSectionOrderPlanner,
            .inputPauseThresholdMs: DefaultValue.inputPauseThresholdMs,
            .platformLimitationsAcknowledged: DefaultValue.platformLimitationsAcknowledged,
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
        static let lockThawBarPosition = true
        static let enableThawBarOnly = true
        static let openHiddenItemsInMenuBar = false
        static let roundScreenCorners = false
        static let screenCornerRadius = 10.0
        static let showThawBarOnlyWithInlineReveal = false
        static let showThawBarOnlyLauncher = true
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
        static let newItemsPlacementData: Data? = nil
        static let sectionDividerStyle: SectionDividerStyle = .noDivider
        static let hideApplicationMenus = true
        static let enableSecondaryContextMenu = true
        static let showOnHoverDelay: TimeInterval = 0.2
        static let tempShowInterval: TimeInterval = 15
        static let tooltipDelay: TimeInterval = 0.5
        static let showMenuBarTooltips = false
        static let iconRefreshInterval: TimeInterval = 0.25
        /// Minimum seconds between two alert reveals of the same item.
        static let menuBarItemAlertRevealCooldown: TimeInterval = 45
        static let autoZenWhileSharingScreen = false
        #if DEBUG
            static let enableDiagnosticLogging = true
        #else
            static let enableDiagnosticLogging = false
        #endif
        static let enableMenuBarItemOverflow = false
        static let enableExperimentalSystemItemHiding = false
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
        static let searchSectionOrder: [String] = ["visible", "hidden", "alwaysHidden"]
        static let searchIncludeVisible = true
        static let searchIncludeHidden = true
        static let searchIncludeAlwaysHidden = true
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

        // MARK: Event Delivery

        static let axMessagingTimeout = 1.0

        /// On by default: the first drag attempt goes to MenuBarAgent's PID and
        /// only the retry uses the HID tap, costing at most one attempt per move.
        /// Whether MenuBarAgent honors the addressed drag is still unverified.
        static let addressMoveDragToMenuBarAgent = true

        /// The first drag attempt as SkyLight event records. Off because the
        /// agent accepts but ignores them, wasting 1.5 s per move. Default: false.
        static let addressMoveDragViaEventRecord = false

        /// On by default: Command-drags use slower steps and a hold before
        /// release, which survives cross-divider moves where the faster
        /// gesture failed with cannotComplete.
        static let useHeldCommandDrag = true

        /// On by default: plan section-order drags with the LCS planner, one
        /// move per misplaced item, instead of the pairwise walk.
        static let useLCSSectionOrderPlanner = true

        /// Input-idle window (ms) before a synthetic move warps the cursor, so
        /// it never lands between the user's own movements. Default: 50.
        static let inputPauseThresholdMs = 50

        /// The user has seen the Layout pane's macOS 27 limitations notice; only
        /// its info button stays after that. Default: false.
        static let platformLimitationsAcknowledged = false
    }
}

extension Defaults {
    enum Key: String {
        // MARK: General Settings

        case showThawIcon = "ShowIceIcon"
        case thawIcon = "IceIcon"
        case customThawIconIsTemplate = "CustomIceIconIsTemplate"
        case simpleMode = "SimpleMode"
        case showSettingDescriptions = "ShowSettingDescriptions"
        case lastSettingsPane = "LastSettingsPane"
        case hiddenSidebarPanes = "HiddenSidebarPanes"
        case menuBarItemAlertReveals = "MenuBarItemAlertReveals"
        case menuBarItemAlertRevealCooldown = "MenuBarItemAlertRevealCooldown"
        case autoZenWhileSharingScreen = "AutoZenWhileSharingScreen"
        case menuBarAppearanceSpaceOverrides = "MenuBarAppearanceSpaceOverrides"
        case lockThawBarPosition = "LockThawBarPosition"
        case enableThawBarOnly = "EnableThawBarOnly"
        case openHiddenItemsInMenuBar = "OpenHiddenItemsInMenuBar"
        case roundScreenCorners = "RoundScreenCorners"
        case screenCornerRadius = "ScreenCornerRadius"
        case showThawBarOnlyWithInlineReveal = "ShowThawBarOnlyWithInlineReveal"
        case showThawBarOnlyLauncher = "ShowThawBarOnlyLauncher"
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

        // MARK: Hotkeys Settings

        case hotkeys = "Hotkeys"
        case profileHotkeys = "ProfileHotkeys"
        case appRunningTriggers = "AppRunningTriggersV1"
        case menuBarItemHotkeys = "MenuBarItemHotkeys"

        // MARK: Advanced Settings

        case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
        case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
        case newItemsSection = "NewItemsSection"
        case newItemsPlacementData = "NewItemsPlacementData"
        case sectionDividerStyle = "SectionDividerStyle"
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
        /// Hidden diagnostic flag; not exposed in Settings. Default: false
        /// until the helper's TCC attribution proves out on macOS 27.
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
        case searchSectionOrder = "SearchSectionOrder"
        case searchIncludeVisible = "SearchIncludeVisible"
        case searchIncludeHidden = "SearchIncludeHidden"
        case searchIncludeAlwaysHidden = "SearchIncludeAlwaysHidden"
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
        /// Applied to every element AXSwift6 creates. 0 restores the
        /// system default of six seconds.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 1.0.
        case axMessagingTimeout

        /// Whether the reorder drag is addressed to MenuBarAgent instead of the
        /// HID stream, avoiding the cursor warp. MenuBarAgent is resolved by
        /// name, since ownerPID is the third-party app.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: false.
        case addressMoveDragToMenuBarAgent

        /// Whether the first synthetic-drag attempt is delivered as event
        /// records addressed to MenuBarAgent (see
        /// DefaultValue.addressMoveDragViaEventRecord).
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: false.
        case addressMoveDragViaEventRecord

        /// Whether synthetic Command-drags use the held HID gesture (see
        /// DefaultValue.useHeldCommandDrag). Off selects the original
        /// addressed gesture, kept for comparison.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case useHeldCommandDrag

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

        /// Whether the Layout pane's macOS 27 limitations notice was acknowledged.
        /// Hidden; not exposed in Settings. Default: false.
        case platformLimitationsAcknowledged = "macOS27LimitationsAcknowledged"

        /// Whether Always-Hidden members are natively hidden via their
        /// owners' preference domains (see DefaultValue.useNativeAlwaysHide).
        ///
        /// Hidden; not exposed in Settings. Default: false.
        case useNativeAlwaysHide

        // MARK: Appearance Settings

        case menuBarAppearanceConfigurationV2 = "MenuBarAppearanceConfigurationV2"

        // MARK: Migration

        /// Pinned to the Ice-era key string already written to disk.
        case hasMigratedPerDisplayThawBar = "hasMigratedPerDisplayIceBar"

        // MARK: First Launch

        case hasCompletedFirstLaunch

        // MARK: Updates Consent

        case hasSeenUpdateConsent

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

        // MARK: Settings URI

        case settingsURIEnabled = "SettingsURIEnabled"
        case settingsURIWhitelist = "SettingsURIWhitelist"
        case settingsURISigningIdentities = "SettingsURISigningIdentities"

        // MARK: Profile Hooks

        case globalPreProfileHook = "GlobalPreProfileHook"
        case globalPostProfileHook = "GlobalPostProfileHook"
    }
}
