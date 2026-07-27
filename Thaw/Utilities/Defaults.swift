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
    /// Returns a dictionary containing the keys and values for
    /// the defaults meant to be seen by all applications.
    static var globalDomain: [String: Any] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    }

    /// Returns the object for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func object(forKey key: Key) -> Any? {
        UserDefaults.standard.object(forKey: key.rawValue)
    }

    /// Returns the string for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func string(forKey key: Key) -> String? {
        UserDefaults.standard.string(forKey: key.rawValue)
    }

    /// Returns the array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func array(forKey key: Key) -> [Any]? {
        UserDefaults.standard.array(forKey: key.rawValue)
    }

    /// Returns the dictionary for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func dictionary(forKey key: Key) -> [String: Any]? {
        UserDefaults.standard.dictionary(forKey: key.rawValue)
    }

    /// Returns the data for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func data(forKey key: Key) -> Data? {
        UserDefaults.standard.data(forKey: key.rawValue)
    }

    /// Returns the string array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func stringArray(forKey key: Key) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key.rawValue)
    }

    /// Returns the integer value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func integer(forKey key: Key) -> Int {
        UserDefaults.standard.integer(forKey: key.rawValue)
    }

    /// Returns the single precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func float(forKey key: Key) -> Float {
        UserDefaults.standard.float(forKey: key.rawValue)
    }

    /// Returns the double precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func double(forKey key: Key) -> Double {
        UserDefaults.standard.double(forKey: key.rawValue)
    }

    /// Returns the Boolean value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func bool(forKey key: Key) -> Bool {
        UserDefaults.standard.bool(forKey: key.rawValue)
    }

    /// Returns the url for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func url(forKey key: Key) -> URL? {
        UserDefaults.standard.url(forKey: key.rawValue)
    }

    /// Sets the value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to set the value for.
    static func set(_ value: Any?, forKey key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    /// Removes the value of the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to remove the value for.
    static func removeObject(forKey key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
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

extension Defaults {
    nonisolated enum DefaultValue {
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
        static let tempShowInterval: TimeInterval = 15
        static let tooltipDelay: TimeInterval = 0.5
        static let showMenuBarTooltips = false
        static let iconRefreshInterval: TimeInterval = 0.25
        #if DEBUG
            static let enableDiagnosticLogging = true
        #else
            static let enableDiagnosticLogging = false
        #endif
        static let useLCSSortingOnNotchedDisplays = true
        static let useOptionClickToShowAlwaysHiddenSection = false
        static let useDoubleClickToShowAlwaysHiddenSection = false
        static let enableMenuBarItemOverflow = true
        static let enableExperimentalSystemItemHiding = false
        static let enableExperimentalWindowHiding = false
        static let enableExperimentalOverflowPrevention = false
        static let alwaysUseAppIconForMenuBarItems = false
        static let menuBarOrderFulfillmentTimeout: TimeInterval = 3

        // MARK: Search

        static let rememberSearchQuery = false
        static let searchSectionOrder: [String] = ["visible", "hidden", "alwaysHidden"]
        static let searchIncludeVisible = true
        static let searchIncludeHidden = true
        static let searchIncludeAlwaysHidden = true

        // MARK: Hotkeys Settings

        static let hotkeys: [String: Data]? = nil

        // MARK: Appearance Settings

        static let menuBarAppearanceConfigurationV2 = MenuBarAppearanceConfigurationV2.defaultConfiguration

        // MARK: Display Settings

        static let displayIceBarConfigurations: [String: DisplayIceBarConfiguration] = [:]
        static let globalDisplayConfiguration: DisplayIceBarConfiguration = .defaultConfiguration
        static let confirmSpacingRelaunch = true
        static let unconfirmedSpacingProfileScope: SpacingProfileSaveScope = .activeProfile

        // MARK: Event Delivery

        static let axMessagingTimeout = 1.0
    }
}

extension Defaults {
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
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case displayIceBarConfigurations = "DisplayIceBarConfigurations"
        case globalDisplayConfiguration = "GlobalDisplayConfiguration"
        case knownDisplays = "KnownDisplays"
        case confirmSpacingRelaunch = "ConfirmSpacingRelaunch"
        case unconfirmedSpacingProfileScope = "UnconfirmedSpacingProfileScope"

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
        case tempShowInterval = "TempShowInterval"
        case tooltipDelay = "TooltipDelay"
        case iconRefreshInterval = "IconRefreshInterval"
        case showMenuBarTooltips = "ShowMenuBarTooltips"
        case enableDiagnosticLogging = "EnableDiagnosticLogging"
        case useLCSSortingOnNotchedDisplays = "UseLCSSortingOnNotchedDisplays"
        case useOptionClickToShowAlwaysHiddenSection = "UseOptionClickToShowAlwaysHiddenSection"
        case useDoubleClickToShowAlwaysHiddenSection = "UseDoubleClickToShowAlwaysHiddenSection"
        case enableMenuBarItemOverflow = "EnableMenuBarItemOverflow"
        case enableExperimentalSystemItemHiding = "EnableExperimentalSystemItemHiding"
        case enableExperimentalWindowHiding = "EnableExperimentalWindowHiding"
        case enableExperimentalOverflowPrevention = "EnableExperimentalOverflowPrevention"
        case alwaysUseAppIconForMenuBarItems = "AlwaysUseAppIconForMenuBarItems"
        case menuBarOrderFulfillmentTimeout = "MenuBarOrderFulfillmentTimeout"
        case diagnosticAssessmentModeSceneProbes = "Thaw.diagnosticAssessmentModeSceneProbes"
        case diagnosticAssessmentModeProbeHiddenTriggerPress = "Thaw.diagnosticAssessmentModeProbeHiddenTriggerPress"
        case debugSimulateNotch = "Thaw.debugSimulateNotch"
        /// Debug flag. Parks Thaw Bar flush against the menu bar
        /// strip with its chrome stripped, so the only open question — can it
        /// be made pixel-convincing against the real menu bar? — can be
        /// answered by eye before any transition machinery is written.
        case debugOverlayFlushMode = "Thaw.debugOverlayFlushMode"
        /// Persisted per-item volatility records. JSON blob
        /// keyed by `tagIdentifier`; see `MenuBarItemVolatilityIndex`.
        case menuBarItemVolatilityIndex = "MenuBarItemVolatilityIndex"
        /// Debug flag for overflow rescue. Parks Thaw Bar as an
        /// *interactive* flush panel beside the (real or simulated) notch, so
        /// assertion-hidden items stay visible and clickable in strip space
        /// macOS refuses to lay items into. Pairs with `debugSimulateNotch`
        /// on non-notched displays.
        case debugOverlayParkedMode = "Thaw.debugOverlayParkedMode"
        /// Width in points of the debug overflow spacer status item
        /// (chevron-herding experiment). 0 or absent = no spacer. See
        /// `OverflowSpacerExperiment`.
        case debugOverflowSpacerWidth = "Thaw.debugOverflowSpacerWidth"
        /// Covers the native macOS 27 overflow chevron with a menu-bar-matched
        /// strip. See `MenuBarChevronCover`. Off by default while it
        /// proves out.
        case debugChevronCover = "Thaw.debugChevronCover"
        /// Verifies out-of-process AX reads via the XPC service on macOS 27:
        /// logs a comparison of XPC snapshots against in-process enumeration
        /// without feeding results into item management. See `XPCAXReadProbe`.
        case debugXPCAXReads = "Thaw.debugXPCAXReads"
        /// Replays the last-known concealment from persisted state at macOS 27
        /// launch, before the first AX walk, so the menu bar opens hidden
        /// instead of flashing every icon for the cold-walk duration. Reconciled
        /// by the first live restriction pass. Off by default while it proves
        /// out. See `MenuBarSectionController.restorePersistedConcealmentAtLaunch`.
        case debugConcealRestore = "Thaw.debugConcealRestore"

        // MARK: Search

        case rememberSearchQuery = "RememberSearchQuery"
        case searchSectionOrder = "SearchSectionOrder"
        case searchIncludeVisible = "SearchIncludeVisible"
        case searchIncludeHidden = "SearchIncludeHidden"
        case searchIncludeAlwaysHidden = "SearchIncludeAlwaysHidden"

        // MARK: Internal

        case menuBarSearchPanelFrame = "MenuBarSearchPanelFrame"
        case menuBarSearchPanelFrameWithConfig = "MenuBarSearchPanelFrame_"

        // MARK: Menu Bar Item Custom Names

        case menuBarItemCustomNames = "MenuBarItemCustomNames"

        // MARK: Internal (Event Delivery)

        /// Items whose owners have recently failed to answer synthetic
        /// events, keyed by namespace and title. Managed by
        /// ``MenuBarItemFailureLedger``; not exposed in Settings.
        case unresponsiveMenuBarItems = "UnresponsiveMenuBarItems"

        /// Items whose moves have repeatedly returned `cannotComplete` and are
        /// treated as unmovable across launches. Managed by
        /// ``MenuBarItemFailureLedger``; not exposed in Settings.
        case cannotCompleteMenuBarItems = "CannotCompleteMenuBarItems"

        /// Build string the failure-ledger marks were last written against. On
        /// a version change the marks are dropped so a Thaw or OS fix re-tests
        /// every item. Managed by ``MenuBarItemFailureLedger``.
        case menuBarFailureLedgerVersion = "MenuBarFailureLedgerVersion"

        /// Persisted `uniqueIdentifier → owner bundle ID` map from the runtime
        /// session controller, so a macOS 27 launch can conceal the last-known
        /// hidden items immediately — before the first AX walk — instead of
        /// flashing every icon for the ~3 s the cold walk takes. Reconciled by
        /// the first live restriction pass. Managed by ``MenuBarSectionController``.
        case menuBarConcealBundleIDMap = "MenuBarConcealBundleIDMap"

        /// Seconds an accessibility message may block before it fails.
        ///
        /// Applied to every element AXSwift6 creates. `0` restores the
        /// system default of six seconds.
        ///
        /// Hidden diagnostic flag; not exposed in Settings. Default: 1.0.
        case axMessagingTimeout = "axMessagingTimeout"

        // MARK: Appearance Settings

        case menuBarAppearanceConfigurationV2 = "MenuBarAppearanceConfigurationV2"

        // MARK: Migration

        case hasMigrated0_8_0
        case hasMigrated0_10_0
        case hasMigrated0_10_1
        case hasMigrated0_11_10
        case hasMigrated0_11_13
        case hasMigrated0_11_13_1
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

        // MARK: Deprecated (Appearance Settings)

        case menuBarHasBorder = "MenuBarHasBorder"
        case menuBarBorderColor = "MenuBarBorderColor"
        case menuBarBorderWidth = "MenuBarBorderWidth"
        case menuBarHasShadow = "MenuBarHasShadow"
        case menuBarTintKind = "MenuBarTintKind"
        case menuBarTintColor = "MenuBarTintColor"
        case menuBarTintGradient = "MenuBarTintGradient"
        case menuBarShapeKind = "MenuBarShapeKind"
        case menuBarFullShapeInfo = "MenuBarFullShapeInfo"
        case menuBarSplitShapeInfo = "MenuBarSplitShapeInfo"
        case menuBarAppearanceConfiguration = "MenuBarAppearanceConfiguration"

        // MARK: Deprecated (Advanced Settings)

        case showSectionDividers = "ShowSectionDividers"
        case canToggleAlwaysHiddenSection = "CanToggleAlwaysHiddenSection"

        // MARK: Deprecated (Other)

        case sections = "Sections"
    }
}
