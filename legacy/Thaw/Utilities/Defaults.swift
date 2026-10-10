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
    /// Production leaves it `.standard`. Tests point it at a scratch suite so they
    /// don't rewrite the user's `com.stonerl.Thaw` domain, which per-key
    /// snapshot/restore can't protect once tests run in parallel. `UserDefaults` is
    /// thread-safe; the unchecked annotation covers only reassignment in test setup.
    static nonisolated(unsafe) var store: UserDefaults = .standard

    /// Returns a dictionary containing the keys and values for
    /// the defaults meant to be seen by all applications.
    static var globalDomain: [String: Any] {
        store.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    }

    static func object(forKey key: Key) -> Any? {
        store.object(forKey: key.rawValue)
    }

    static func string(forKey key: Key) -> String? {
        store.string(forKey: key.rawValue)
    }

    static func dictionary(forKey key: Key) -> [String: Any]? {
        store.dictionary(forKey: key.rawValue)
    }

    static func data(forKey key: Key) -> Data? {
        store.data(forKey: key.rawValue)
    }

    static func stringArray(forKey key: Key) -> [String]? {
        store.stringArray(forKey: key.rawValue)
    }

    static func integer(forKey key: Key) -> Int {
        store.integer(forKey: key.rawValue)
    }

    static func double(forKey key: Key) -> Double {
        store.double(forKey: key.rawValue)
    }

    static func bool(forKey key: Key) -> Bool {
        store.bool(forKey: key.rawValue)
    }

    static func set(_ value: Any?, forKey key: Key) {
        store.set(value, forKey: key.rawValue)
    }

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
        static let hideDockIconWhenToggling = false
        static let rehideStrategy: RehideStrategy = .smart
        static let rehideInterval: TimeInterval = 15
        static let tempShowInterval: TimeInterval = 0

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
        static let spacingApplyMode: SpacingApplyMode = .relaunchApps

        // MARK: Hidden Diagnostic Flags

        static let inputPauseThresholdMs = 50
        static let bulkApplyIdleThresholdMs = 300
        static let bulkApplyIdleWaitCapMs = 2000
        static let enforceConcealedSectionOrder = false
        static let automaticArrangementEnabled = true
        static let postMoveEventsToWindowOwner = true
        static let discardStrayMoveEvents = true
        static let failFastOnEventWindowMismatch = false
        static let faithfulDragMoves = false
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
        case hideDockIconWhenToggling = "HideDockIconWhenToggling"
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case tempShowInterval = "TempShowInterval"
        case displayIceBarConfigurations = "DisplayIceBarConfigurations"
        case globalDisplayConfiguration = "GlobalDisplayConfiguration"
        case knownDisplays = "KnownDisplays"
        case confirmSpacingRelaunch = "ConfirmSpacingRelaunch"
        case unconfirmedSpacingProfileScope = "UnconfirmedSpacingProfileScope"
        case spacingApplyMode = "SpacingApplyMode"

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
        /// `inputPauseThresholdMs` gates each move; this gates the batch. A batch hides
        /// the cursor for its whole length, so starting mid-interaction fights the user
        /// move by move. Set 0 to fall back to the per-move pause alone.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 300.
        case bulkApplyIdleThresholdMs = "bulkApplyIdleThresholdMs"

        /// Maximum milliseconds an automatic bulk apply waits for the idle
        /// window described by ``bulkApplyIdleThresholdMs``.
        ///
        /// The wait defers, never cancels: a user who never stops moving would otherwise
        /// starve the apply forever. After the cap the batch proceeds. Ignored when the
        /// threshold is 0.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 2000.
        case bulkApplyIdleWaitCapMs = "bulkApplyIdleWaitCapMs"

        /// Whether a bulk apply enforces item order *within* the hidden and
        /// always-hidden sections, rather than only their membership.
        ///
        /// Every move hijacks the cursor whatever its result, and on a well-populated
        /// hidden section most of a batch reorders items parked off-screen that the Thaw
        /// Bar renders from the cache anyway. False keeps membership only, so batches
        /// stay short. Set true to restore order inside the concealed sections.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: false.
        case enforceConcealedSectionOrder = "enforceConcealedSectionOrder"

        /// Whether Thaw rearranges the bar on its own initiative.
        ///
        /// The escape hatch. False stands down the late-arrival re-sort and the
        /// saved-layout restore; applying a profile still works.
        ///
        /// Try ``bulkApplyIdleThresholdMs``, ``enforceConcealedSectionOrder``, and the
        /// unfinished-batch rationing in `MoveCircuitBreaker.bulkApplyPermitted` first.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: true.
        case automaticArrangementEnabled = "automaticArrangementEnabled"

        /// Whether synthetic move events are posted to the process that owns
        /// the item's *window* rather than the app that owns the *item*.
        ///
        /// On macOS 26 Control Center hosts every status item window, so the window's CG
        /// owner is Control Center while `sourcePID` names the item's app. Events sent to
        /// `sourcePID` reach a process that doesn't own the dragged window, which caused
        /// the `itemResponseTimeout` failures (#900, #923, #924). Targeting the host also
        /// lets a slot with no resolved owner move, so
        /// ``MenuBarItem/ImmovabilityReason/unresolvedControlCenterPlaceholder`` stops
        /// applying while this is on.
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

        /// Whether an eligible move presses on the item where it sits and
        /// drags it to the destination (a faithful gesture) instead of the
        /// press-at-destination "teleport".
        ///
        /// On macOS 26 each status item is a remote FrontBoard scene hosted by Control
        /// Center. The teleport relies on Control Center relocating a passive item; with a
        /// cold source-app scene the drop can finish while the app never commits, and
        /// Control Center restores the autosaved slot (the "revert"). Pressing on the item
        /// makes the app start the drag itself (`NSStatusItemStartDragAction`) with a warm
        /// scene. Used only for on-screen paths inside one safe notch segment; parked and
        /// cross-notch endpoints use named teleports, and invalid or cross-display geometry
        /// is rejected. Inferred from field logs, not confirmed on a live bar, so opt-in.
        ///
        /// Enable with:
        ///   defaults write com.stonerl.Thaw faithfulDragMoves -bool YES
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: false.
        case faithfulDragMoves = "faithfulDragMoves"

        /// Seconds an accessibility message may block before it fails.
        ///
        /// Applied to every element AXSwift6 creates. `0` restores the
        /// system default of six seconds.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 1.0.
        case axMessagingTimeout = "axMessagingTimeout"
    }
}
