//
//  Defaults.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI

nonisolated enum Defaults {
    /// The store every accessor below reads and writes.
    ///
    /// Production never assigns this; it stays `.standard` for the life of
    /// the process. It exists so tests can point the whole `Defaults` facade
    /// at a scratch suite instead of the user's real `com.stonerl.Thaw`
    /// domain. Without it, exercising anything that persists a setting
    /// rewrites the defaults of whoever is running the tests, and the suite
    /// has to defend itself with per-key snapshot/restore that is not safe
    /// once tests run in parallel.
    ///
    /// `UserDefaults` is itself thread-safe, so the unchecked annotation
    /// covers only the reassignment, which is confined to test setup.
    static nonisolated(unsafe) var store: UserDefaults = .standard

    /// Returns a dictionary containing the keys and values for
    /// the defaults meant to be seen by all applications.
    static var globalDomain: [String: Any] {
        store.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    }

    /// Returns the object for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func object(forKey key: Key) -> Any? {
        store.object(forKey: key.rawValue)
    }

    /// Returns the string for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func string(forKey key: Key) -> String? {
        store.string(forKey: key.rawValue)
    }

    /// Returns the array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func array(forKey key: Key) -> [Any]? {
        store.array(forKey: key.rawValue)
    }

    /// Returns the dictionary for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func dictionary(forKey key: Key) -> [String: Any]? {
        store.dictionary(forKey: key.rawValue)
    }

    /// Returns the data for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func data(forKey key: Key) -> Data? {
        store.data(forKey: key.rawValue)
    }

    /// Returns the string array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func stringArray(forKey key: Key) -> [String]? {
        store.stringArray(forKey: key.rawValue)
    }

    /// Returns the integer value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func integer(forKey key: Key) -> Int {
        store.integer(forKey: key.rawValue)
    }

    /// Returns the single precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func float(forKey key: Key) -> Float {
        store.float(forKey: key.rawValue)
    }

    /// Returns the double precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func double(forKey key: Key) -> Double {
        store.double(forKey: key.rawValue)
    }

    /// Returns the Boolean value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func bool(forKey key: Key) -> Bool {
        store.bool(forKey: key.rawValue)
    }

    /// Returns the url for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func url(forKey key: Key) -> URL? {
        store.url(forKey: key.rawValue)
    }

    /// Sets the value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to set the value for.
    static func set(_ value: Any?, forKey key: Key) {
        store.set(value, forKey: key.rawValue)
    }

    /// Removes the value of the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to remove the value for.
    static func removeObject(forKey key: Key) {
        store.removeObject(forKey: key.rawValue)
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, assigns it to the given `inout` parameter.
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
}

nonisolated extension Defaults {
    enum DefaultValue {
        // MARK: General Settings

        static let showIceIcon = true
        static let iceIcon = ControlItemImageSet.defaultIceIcon
        static let customIceIconIsTemplate = false
        static let useIceBar = false
        static let useIceBarOnlyOnNotchedDisplay = false
        static let iceBarLocation: IceBarLocation = .dynamic
        static let iceBarLocationOnHotkey = false
        static let showOnClick = true
        static let showOnDoubleClick = true
        static let showOnHover = false
        static let showOnScroll = true
        static let autoRehide = true
        static let simpleMode = false
        static let autoZenWhileSharingScreen = false
        static let showSettingDescriptions = true
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
        static let enableSecondaryContextMenuQuit = false
        static let showOnHoverDelay: TimeInterval = 0.2
        static let tooltipDelay: TimeInterval = 0.5
        static let showMenuBarTooltips = false
        static let iconRefreshInterval: TimeInterval = 0.25
        #if DEBUG
            static let enableDiagnosticLogging = true
        #else
            static let enableDiagnosticLogging = false
        #endif
        static let diagnosticLogMaxSizeMB = 10
        static let diagnosticLogRetentionDays = 2
        static let diagnosticLogRotationInterval: LogRotationInterval = .off
        static let useOptionClickToShowAlwaysHiddenSection = false
        static let useDoubleClickToShowAlwaysHiddenSection = false
        static let enableMenuBarItemOverflow = true
        static let useThawBarOnNotchOverflow = true
        static let useAXClickDelivery = true

        // MARK: Search

        static let rememberSearchQuery = false
        static let searchSectionOrder: [String] = ["visible", "hidden", "alwaysHidden"]
        static let searchIncludeVisible = true
        static let searchIncludeHidden = true
        static let searchIncludeAlwaysHidden = true
        static let moveCursorToRevealedItem = false

        // MARK: Hotkeys Settings

        static nonisolated(unsafe) let hotkeys: [Any]? = nil

        // MARK: Attention Surfacing

        static let surfaceItemsSeekingAttention = false

        // MARK: Item Rendering

        static let alwaysUseAppIconForMenuBarItems = false

        // MARK: Appearance Settings

        static let menuBarAppearanceConfigurationV2 = MenuBarAppearanceConfigurationV2.defaultConfiguration

        // MARK: Display Settings

        static let displayIceBarConfigurations: [String: DisplayIceBarConfiguration] = [:]
        static let globalDisplayConfiguration: DisplayIceBarConfiguration = .defaultConfiguration
        static let confirmSpacingRelaunch = true
        static let unconfirmedSpacingProfileScope: SpacingProfileSaveScope = .activeProfile

        // MARK: Hidden Diagnostic Flags

        static let inputPauseThresholdMs = 50
        static let bulkApplyIdleThresholdMs = 300
        static let bulkApplyIdleWaitCapMs = 2000
        static let enforceConcealedSectionOrder = false
        static let automaticArrangementEnabled = true
        static let postMoveEventsToWindowOwner = true
        static let discardStrayMoveEvents = true
        static let failFastOnEventWindowMismatch = false
        static let axMessagingTimeout = SharedConstants.axMessagingTimeout
    }
}

nonisolated extension Defaults {
    enum Key: String {
        // MARK: General Settings

        case showIceIcon = "ShowIceIcon"
        case iceIcon = "IceIcon"
        case customIceIconIsTemplate = "CustomIceIconIsTemplate"
        case useIceBar = "UseIceBar"
        case useIceBarOnlyOnNotchedDisplay = "UseIceBarOnlyOnNotchedDisplay"
        case iceBarLocation = "IceBarLocation"
        case iceBarLocationOnHotkey = "IceBarLocationOnHotkey"
        case showOnClick = "ShowOnClick"
        case showOnDoubleClick = "ShowOnDoubleClick"
        case showOnHover = "ShowOnHover"
        case showOnScroll = "ShowOnScroll"
        case autoRehide = "AutoRehide"
        case simpleMode = "SimpleMode"
        case showSettingDescriptions = "ShowSettingDescriptions"
        case autoZenWhileSharingScreen = "AutoZenWhileSharingScreen"
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case displayIceBarConfigurations = "DisplayIceBarConfigurations"
        case globalDisplayConfiguration = "GlobalDisplayConfiguration"
        case knownDisplays = "KnownDisplays"
        case confirmSpacingRelaunch = "ConfirmSpacingRelaunch"
        case unconfirmedSpacingProfileScope = "UnconfirmedSpacingProfileScope"

        // MARK: Menu Bar Spacers

        case menuBarSpacers = "MenuBarSpacers"

        // MARK: Hotkeys Settings

        case hotkeys = "Hotkeys"
        case profileHotkeys = "ProfileHotkeys"
        case menuBarItemHotkeys = "MenuBarItemHotkeys"

        // MARK: Advanced Settings

        case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
        case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
        case newItemsSection = "NewItemsSection"
        case newItemsPlacementData = "NewItemsPlacementData"
        case sectionDividerStyle = "SectionDividerStyle"
        case hideApplicationMenus = "HideApplicationMenus"
        case enableSecondaryContextMenu = "EnableSecondaryContextMenu"
        case enableSecondaryContextMenuQuit = "EnableSecondaryContextMenuQuit"
        case showOnHoverDelay = "ShowOnHoverDelay"
        case tooltipDelay = "TooltipDelay"
        case iconRefreshInterval = "IconRefreshInterval"
        case showMenuBarTooltips = "ShowMenuBarTooltips"
        case enableDiagnosticLogging = "EnableDiagnosticLogging"
        case diagnosticLogMaxSizeMB = "DiagnosticLogMaxSizeMB"
        case diagnosticLogRetentionDays = "DiagnosticLogRetentionDays"
        case diagnosticLogRotationInterval = "DiagnosticLogRotationInterval"
        case useOptionClickToShowAlwaysHiddenSection = "UseOptionClickToShowAlwaysHiddenSection"
        case useDoubleClickToShowAlwaysHiddenSection = "UseDoubleClickToShowAlwaysHiddenSection"
        case enableMenuBarItemOverflow = "EnableMenuBarItemOverflow"
        case useThawBarOnNotchOverflow = "UseThawBarOnNotchOverflow"
        case useAXClickDelivery = "UseAXClickDelivery"

        // MARK: Search

        case rememberSearchQuery = "RememberSearchQuery"
        case searchSectionOrder = "SearchSectionOrder"
        case searchIncludeVisible = "SearchIncludeVisible"
        case searchIncludeHidden = "SearchIncludeHidden"
        case searchIncludeAlwaysHidden = "SearchIncludeAlwaysHidden"
        case moveCursorToRevealedItem = "MoveCursorToRevealedItem"

        // MARK: Internal

        case menuBarSearchPanelFrame = "MenuBarSearchPanelFrame"
        case menuBarSearchPanelFrameWithConfig = "MenuBarSearchPanelFrame_"

        // MARK: Menu Bar Item Custom Names

        case menuBarItemCustomNames = "MenuBarItemCustomNames"

        /// The name each item last resolved to, used to label items during
        /// the window before source-PID resolution lands. Managed by
        /// ``MenuBarItemNameMemory``; not exposed in Settings.
        case menuBarItemResolvedNames = "MenuBarItemResolvedNames"

        // MARK: Internal (Event Delivery)

        /// Items whose owners have recently failed to answer synthetic
        /// events, keyed by namespace and title. Managed by
        /// ``UnresponsiveItemStore``; not exposed in Settings.
        case unresponsiveMenuBarItems = "UnresponsiveMenuBarItems"

        /// The app build the persisted unresponsive-item marks were recorded
        /// against. A change drops the marks, so a fix that makes a
        /// previously stuck item movable is not hidden behind the two-week
        /// mark lifetime. Managed by ``MenuBarItemFailureLedger``.
        case unresponsiveMenuBarItemsBuild = "UnresponsiveMenuBarItemsBuild"

        // MARK: Internal (Layout Identity)

        /// How many consecutive applies each saved identifier has been
        /// planned for without matching a live item, keyed by canonical
        /// identifier. Managed by ``StaleIdentifierLedger``; not exposed in
        /// Settings.
        case staleIdentifierMissCounts = "StaleIdentifierMissCounts"

        /// The app build the persisted miss counts were accumulated under. A
        /// change drops them, so an improvement to identity resolution is not
        /// hidden behind counts earned against the old behavior. Managed by
        /// ``StaleIdentifierLedger``.
        case staleIdentifierMissCountsBuild = "StaleIdentifierMissCountsBuild"

        /// The app build whose pruning rules were last applied to the profile
        /// files on disk. Managed by
        /// ``ProfileManager/repairPersistedLayoutsIfNeeded()``; not exposed in
        /// Settings.
        case profileLayoutRepairBuild = "ProfileLayoutRepairBuild"

        // MARK: Item Rendering

        /// Whether menu bar items are drawn as their owning app's icon
        /// instead of a live capture, everywhere Thaw renders them.
        case alwaysUseAppIconForMenuBarItems = "AlwaysUseAppIconForMenuBarItems"

        // MARK: Attention Surfacing

        /// Whether an item that blinks for attention while hidden is
        /// temporarily surfaced. Off by default: it moves items on a
        /// heuristic, and a wrong verdict is a wrong move.
        case surfaceItemsSeekingAttention = "SurfaceItemsSeekingAttention"

        // MARK: Appearance Settings

        case menuBarAppearanceConfigurationV2 = "MenuBarAppearanceConfigurationV2"
        case menuBarAppearanceSpaceOverrides = "MenuBarAppearanceSpaceOverrides"
        case lastSettingsPane = "LastSettingsPane"

        // MARK: Migration

        case hasMigratedPerDisplayIceBar

        // MARK: First Launch

        case hasCompletedFirstLaunch

        // MARK: Updates Consent

        case hasSeenUpdateConsent

        // MARK: Onboarding

        case hasSeenOnboarding

        // MARK: Settings URI

        case settingsURIEnabled = "SettingsURIEnabled"
        case settingsURIWhitelist = "SettingsURIWhitelist"
        case settingsURISigningIdentities = "SettingsURISigningIdentities"

        // MARK: Profile Hooks

        case globalPreProfileHook = "GlobalPreProfileHook"
        case globalPostProfileHook = "GlobalPostProfileHook"

        // MARK: Menu Bar Item Triggers

        case menuBarItemTriggers = "MenuBarItemTriggers"
        case triggerFeatureFlags = "TriggerFeatureFlags"
        case showTriggerFeatureFlagsAllOffMenuItem = "ShowTriggerFeatureFlagsAllOffMenuItem"

        // MARK: Focus Filter

        /// Profile ID requested by the most recent Focus Filter
        /// activation. Written by ``ThawFocusFilter`` and consumed by
        /// ``ProfileManager/applyFocusFilterProfile()``.
        case focusFilterRequestedProfileID = "FocusFilterRequestedProfileID"

        // MARK: Hidden Diagnostic Flags

        /// Milliseconds of input inactivity required before a menu-bar item
        /// reorder move proceeds.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 50.
        case inputPauseThresholdMs = "inputPauseThresholdMs"

        /// Milliseconds of input inactivity required before an *automatic*
        /// bulk apply starts issuing its move sequence.
        ///
        /// `inputPauseThresholdMs` gates each individual move; this gates
        /// the batch. A batch holds the cursor hidden for its whole length,
        /// so starting one the instant a late arrival is noticed can take
        /// the pointer away mid-interaction and then fight the user for it
        /// move by move. Waiting for a real lull first costs nothing when
        /// the bar is idle — the common case — and avoids the collision
        /// entirely when it isn't.
        ///
        /// 300 ms is the default: a batch dispatched mid-interaction contests
        /// the pointer for its whole length, and waiting for one real lull up
        /// front costs nothing on an idle bar. Set 0 to disable the gate and
        /// fall back to the per-move pause alone.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 300.
        case bulkApplyIdleThresholdMs = "bulkApplyIdleThresholdMs"

        /// Maximum milliseconds an automatic bulk apply waits for the idle
        /// window described by ``bulkApplyIdleThresholdMs``.
        ///
        /// The wait defers, it never cancels. A user who keeps the mouse
        /// moving indefinitely would otherwise starve the apply forever,
        /// and a layout that is never restored is a worse outcome than one
        /// restored during input. Once the cap elapses the batch proceeds
        /// as it always did.
        ///
        /// Ignored when the threshold is 0.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 2000.
        case bulkApplyIdleWaitCapMs = "bulkApplyIdleWaitCapMs"

        /// Whether a bulk apply enforces item order *within* the hidden and
        /// always-hidden sections, rather than only their membership.
        ///
        /// Every move costs the same whether or not its result is visible:
        /// the cursor is hijacked, a drag is synthesised, the landing is
        /// polled. On a bar with a well-populated hidden section a large
        /// share of a batch can be spent reordering items parked thousands
        /// of points off-screen, which the Thaw Bar renders from the cache
        /// anyway. Setting this to false surrenders that ordering and keeps
        /// membership, shortening batches on exactly the bars where long
        /// batches hurt most.
        ///
        /// False by default: on a well-populated hidden section the ordering
        /// moves are the bulk of a batch and none of their results are
        /// visible, so surrendering them is what keeps batches short enough
        /// not to fight the user. Set true to restore order as well as
        /// membership inside the concealed sections.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: false.
        case enforceConcealedSectionOrder = "enforceConcealedSectionOrder"

        /// Whether Thaw rearranges the bar on its own initiative.
        ///
        /// The escape hatch for bars where the automatic paths misbehave in
        /// ways no gate has caught. Set to false and the late-arrival
        /// re-sort and the saved-layout restore both stand down; applying a
        /// profile still works, so the user keeps a way to arrange the bar
        /// deliberately — they just decide when.
        ///
        /// This is the blunt instrument. The graduated responses —
        /// ``bulkApplyIdleThresholdMs``, ``enforceConcealedSectionOrder``,
        /// and the unfinished-batch rationing in
        /// `automaticBulkApplyPermitted` — are all better first attempts.
        /// Reach for this when they have not helped.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case automaticArrangementEnabled = "automaticArrangementEnabled"

        /// Whether synthetic move events are posted to the process that owns
        /// the item's *window* rather than the app that owns the *item*.
        ///
        /// On macOS 26 those are different processes: Control Center hosts
        /// every status item window, so the CG owner of the window Thaw is
        /// dragging is Control Center, while `sourcePID` names the app whose
        /// status item it logically is. Thaw has always preferred
        /// `sourcePID`, which was right when the owning app really did own
        /// the window, and on 26 targets a process that does not own the
        /// window being dragged.
        ///
        /// Two consequences, both confirmed by the rc.3 test build. Moves
        /// that failed with `itemResponseTimeout` were failing because the
        /// events went to the wrong process (#900, #923, and the
        /// notch-overflow ejections in #924). And an item whose owning app
        /// never resolved need not be
        /// immovable at all: with the host as the target, the move does not
        /// require knowing who owns the item, so
        /// ``MenuBarItem/ImmovabilityReason/unresolvedControlCenterPlaceholder``
        /// stops applying while this is on, which is now the shipping
        /// posture.
        ///
        /// On by default: on macOS 26 the window's owner is the process that
        /// actually receives the drag, and addressing it is what lets a
        /// Control Center slot with no resolved owner move at all.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case postMoveEventsToWindowOwner = "postMoveEventsToWindowOwner"

        /// Whether stray echoes of synthetic move events are discarded
        /// before they can be delivered against the wrong window.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case discardStrayMoveEvents = "discardStrayMoveEvents"

        /// Whether a synthetic event that comes back addressed to a
        /// different window than it was posted with fails its operation
        /// immediately rather than running to timeout.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: false.
        case failFastOnEventWindowMismatch = "failFastOnEventWindowMismatch"

        /// Seconds an accessibility message may block before it fails.
        ///
        /// Applied to every element AXSwift6 creates. `0` restores the
        /// system default of six seconds.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 1.0.
        case axMessagingTimeout = "axMessagingTimeout"
    }
}
