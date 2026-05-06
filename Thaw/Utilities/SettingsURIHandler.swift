//
//  SettingsURIHandler.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Security

/// Handles settings manipulation via thaw:// URLs with whitelist-based security.
@MainActor
enum SettingsURIHandler {
    private static let diagLog = DiagLog(category: "SettingsURIHandler")

    /// Tier 1: Safe boolean toggles that can be manipulated via URI
    static let supportedBooleanKeys: [String] = [
        "autoRehide",
        "showOnClick",
        "showOnDoubleClick",
        "showOnHover",
        "showOnScroll",
        "useIceBar",
        "useIceBarOnlyOnNotchedDisplay",
        "hideApplicationMenus",
        "enableAlwaysHiddenSection",
        "useOptionClickToShowAlwaysHiddenSection",
        "enableSecondaryContextMenu",
        "showAllSectionsOnUserDrag",
        "showMenuBarTooltips",
        "enableDiagnosticLogging",
        "customIceIconIsTemplate",
        "showIceIcon",
        "iceBarLocationOnHotkey",
        "useLCSSortingOnNotchedDisplays",
        "enableMenuBarItemOverflow",
    ]

    /// Double/numeric settings with ranges
    static let doubleKeys: [String] = [
        "rehideInterval",
        "showOnHoverDelay",
        "tooltipDelay",
        "iconRefreshInterval",
    ]

    /// Enum settings with string values
    static let enumKeys: [String] = [
        "rehideStrategy",
    ]

    /// Per-display settings keys (stored in DisplaySettingsManager, not Defaults)
    static let perDisplayKeys: [String] = [
        "useIceBar",
        "iceBarLocation",
        "alwaysShowHiddenItems",
        "iceBarLayout",
        "gridColumns",
    ]

    /// Mapping of URI key names to Defaults.Key enum cases
    private static let keyMapping: [String: Defaults.Key] = [
        "autoRehide": .autoRehide,
        "showOnClick": .showOnClick,
        "showOnDoubleClick": .showOnDoubleClick,
        "showOnHover": .showOnHover,
        "showOnScroll": .showOnScroll,
        "useIceBarOnlyOnNotchedDisplay": .useIceBarOnlyOnNotchedDisplay,
        "hideApplicationMenus": .hideApplicationMenus,
        "enableAlwaysHiddenSection": .enableAlwaysHiddenSection,
        "useOptionClickToShowAlwaysHiddenSection": .useOptionClickToShowAlwaysHiddenSection,
        "enableSecondaryContextMenu": .enableSecondaryContextMenu,
        "showAllSectionsOnUserDrag": .showAllSectionsOnUserDrag,
        "showMenuBarTooltips": .showMenuBarTooltips,
        "enableDiagnosticLogging": .enableDiagnosticLogging,
        "customIceIconIsTemplate": .customIceIconIsTemplate,
        "showIceIcon": .showIceIcon,
        "iceBarLocationOnHotkey": .iceBarLocationOnHotkey,
        "useLCSSortingOnNotchedDisplays": .useLCSSortingOnNotchedDisplays,
        "enableMenuBarItemOverflow": .enableMenuBarItemOverflow,
        "rehideInterval": .rehideInterval,
        "showOnHoverDelay": .showOnHoverDelay,
        "tooltipDelay": .tooltipDelay,
        "iconRefreshInterval": .iconRefreshInterval,
        "rehideStrategy": .rehideStrategy,
    ]

    /// Valid ranges for double settings (min, max, default)
    private static let doubleRanges: [String: (min: Double, max: Double)] = [
        "rehideInterval": (1, 300),
        "showOnHoverDelay": (0, 5),
        "tooltipDelay": (0, 5),
        "iconRefreshInterval": (0, 5),
    ]

    // MARK: - Security

    /// Gets the team identifier for a bundle ID by checking the app's code signature.
    private static func getTeamIdentifier(for bundleId: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            diagLog.debug("Settings URI: Cannot find app URL for \(bundleId)")
            return nil
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            diagLog.debug("Settings URI: Failed to create static code for \(bundleId): \(createStatus)")
            return nil
        }

        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo)
        guard infoStatus == errSecSuccess, let info = signingInfo as? [String: Any] else {
            diagLog.debug("Settings URI: Failed to get signing info for \(bundleId): \(infoStatus)")
            return nil
        }

        // Extract team identifier from signing info
        if let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String {
            return teamId
        }

        diagLog.debug("Settings URI: No team identifier found for \(bundleId)")
        return nil
    }

    /// Verifies that an app's current code signature matches the stored signing identity.
    private static func verifyCodeSignature(bundleId: String, storedTeamId: String?) -> Bool {
        // If no stored team ID, only allow if app is also unsigned (legacy entries)
        guard let storedTeamId else {
            let currentTeamId = getTeamIdentifier(for: bundleId)
            return currentTeamId == nil
        }

        guard let currentTeamId = getTeamIdentifier(for: bundleId) else {
            diagLog.warning("Settings URI: App \(bundleId) is unsigned but was authorized with team ID")
            return false
        }

        return currentTeamId == storedTeamId
    }

    /// Gets the stored signing identities dictionary.
    private static func getSigningIdentities() -> [String: String] {
        guard let data = Defaults.data(forKey: .settingsURISigningIdentities),
              let identities = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return identities
    }

    /// Saves the signing identities dictionary.
    private static func saveSigningIdentities(_ identities: [String: String]) {
        if let data = try? JSONEncoder().encode(identities) {
            Defaults.set(data, forKey: .settingsURISigningIdentities)
        }
    }

    /// Checks if the sender is in the whitelist and has valid code signature.
    static func isWhitelisted(bundleIdentifier: String?) -> Bool {
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty else {
            diagLog.warning("Settings URI: No sender bundle ID provided")
            return false
        }

        let whitelist = Defaults.stringArray(forKey: .settingsURIWhitelist) ?? []
        guard whitelist.contains(bundleId) else {
            diagLog.debug("Settings URI: Unauthorized request from \(bundleId)")
            return false
        }

        // Verify code signature matches stored identity
        let signingIdentities = getSigningIdentities()
        let storedTeamId = signingIdentities[bundleId]

        guard verifyCodeSignature(bundleId: bundleId, storedTeamId: storedTeamId) else {
            diagLog.warning("Settings URI: Code signature mismatch for \(bundleId)")
            return false
        }

        diagLog.debug("Settings URI: Authorized request from \(bundleId)")
        return true
    }

    /// Shows NSAlert confirmation dialog for first-time authorization.
    /// Returns true if user approves, false otherwise.
    static func promptForAuthorization(bundleId: String) -> Bool {
        let appName = getAppName(for: bundleId) ?? bundleId
        let teamId = getTeamIdentifier(for: bundleId)

        let alert = NSAlert()
        alert.messageText = String(localized: "Allow \"\(appName)\" to control \(Constants.displayName) settings?")

        let baseText = String(
            localized: """
            If granted, this app will be able to:

            • Read current settings and configurations
            • Turn features and options on or off
            • Adjust timing values (delays, intervals, timers)
            • Change how \(Constants.displayName) Bar behaves
            • Customize settings for each display

            This permission stays active until removed in \(Constants.displayName)'s Automation settings.
            """
        )

        var fullText = baseText
        if let teamId {
            fullText += "\n\n" + String(localized: "Signed by: \(teamId)")
        } else {
            fullText += "\n\n" + String(localized: "Warning: This app is not code-signed.")
        }

        alert.informativeText = fullText

        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Deny"))

        let response = alert.runModal()
        let approved = response == .alertFirstButtonReturn

        if approved {
            diagLog.info("Settings URI: User authorized \(bundleId) (team: \(teamId ?? "unsigned"))")
            addToWhitelist(bundleId: bundleId, teamIdentifier: teamId)
        } else {
            diagLog.info("Settings URI: User denied \(bundleId)")
        }

        return approved
    }

    /// Adds a bundle ID to the whitelist with its signing identity.
    static func addToWhitelist(bundleId: String, teamIdentifier: String? = nil) {
        var whitelist = Defaults.stringArray(forKey: .settingsURIWhitelist) ?? []
        guard !whitelist.contains(bundleId) else { return }

        whitelist.append(bundleId)
        Defaults.set(whitelist, forKey: .settingsURIWhitelist)

        // Store signing identity if available
        if let teamId = teamIdentifier {
            var identities = getSigningIdentities()
            identities[bundleId] = teamId
            saveSigningIdentities(identities)
        }

        diagLog.info("Settings URI: Added \(bundleId) to whitelist (team: \(teamIdentifier ?? "unsigned"))")
        NotificationCenter.default.post(name: .settingsURIWhitelistDidChange, object: nil)
    }

    /// Removes a bundle ID from the whitelist.
    static func removeFromWhitelist(bundleId: String) {
        var whitelist = Defaults.stringArray(forKey: .settingsURIWhitelist) ?? []
        whitelist.removeAll { $0 == bundleId }
        Defaults.set(whitelist, forKey: .settingsURIWhitelist)

        // Remove signing identity
        var identities = getSigningIdentities()
        identities.removeValue(forKey: bundleId)
        saveSigningIdentities(identities)

        diagLog.info("Settings URI: Removed \(bundleId) from whitelist")
        NotificationCenter.default.post(name: .settingsURIWhitelistDidChange, object: nil)
    }

    /// Gets the display name for a bundle ID.
    static func getAppName(for bundleId: String) -> String? {
        // Try to find running app
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return app.localizedName
        }

        // Try to get from bundle path
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url)
        {
            return bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        }

        return nil
    }

    /// Gets the icon for a bundle ID.
    static func getAppIcon(for bundleId: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    // MARK: - Validation

    /// Checks if a settings key is supported for URI manipulation.
    static func isValidSettingsKey(_ key: String) -> Bool {
        return supportedBooleanKeys.contains(key)
            || doubleKeys.contains(key)
            || enumKeys.contains(key)
            || perDisplayKeys.contains(key)
    }

    /// Parses a boolean value from string.
    static func parseBool(_ value: String) -> Bool? {
        let lowercased = value.lowercased()
        if lowercased == "true" || lowercased == "1" || lowercased == "yes" {
            return true
        } else if lowercased == "false" || lowercased == "0" || lowercased == "no" {
            return false
        }
        return nil
    }

    /// Parses a double value from string.
    static func parseDouble(_ value: String) -> Double? {
        return Double(value)
    }

    // MARK: - Execution

    /// Handles thaw://set?key=X&value=Y&type=bool URL.
    /// Returns true if setting was changed successfully.
    static func handleSet(key: String, value: String, sender: String?, displayUUID: String? = nil) -> Bool {
        diagLog.debug("Settings URI: set request - key=\(key), value=\(value), sender=\(sender ?? "unknown"), display=\(displayUUID ?? "none")")

        // Validate key
        guard isValidSettingsKey(key) else {
            diagLog.warning("Settings URI: Invalid key '\(key)'")
            return false
        }

        // Check if this is a per-display setting
        if perDisplayKeys.contains(key) {
            return handlePerDisplaySet(key: key, value: value, displayUUID: displayUUID)
        }

        // Route to appropriate handler based on key type
        if doubleKeys.contains(key) {
            return handleDoubleSet(key: key, value: value)
        } else if enumKeys.contains(key) {
            return handleEnumSet(key: key, value: value)
        }

        // Parse boolean value
        guard let boolValue = parseBool(value) else {
            diagLog.warning("Settings URI: Invalid boolean value '\(value)'")
            return false
        }

        // Get the Defaults.Key
        guard let defaultsKey = keyMapping[key] else {
            diagLog.error("Settings URI: No mapping for key '\(key)'")
            return false
        }

        // Apply the setting
        Defaults.set(boolValue, forKey: defaultsKey)

        // Notify settings models that a value changed externally
        postSettingsDidChangeNotification(key: key, value: boolValue)

        diagLog.info("Settings URI: Set \(key) = \(boolValue)")

        return true
    }

    /// Handles setting a double/numeric value with range validation.
    private static func handleDoubleSet(key: String, value: String) -> Bool {
        guard let doubleValue = parseDouble(value) else {
            diagLog.warning("Settings URI: Invalid double value '\(value)' for \(key)")
            return false
        }

        // Reject non-finite values (NaN, Infinity)
        guard doubleValue.isFinite else {
            diagLog.warning("Settings URI: Non-finite value '\(value)' not allowed for \(key)")
            return false
        }

        // Validate and clamp to range
        let (minVal, maxVal) = doubleRanges[key] ?? (0, Double.greatestFiniteMagnitude)
        let clampedValue = Swift.max(minVal, Swift.min(doubleValue, maxVal))

        if clampedValue != doubleValue {
            diagLog.debug("Settings URI: Clamped \(key) from \(doubleValue) to \(clampedValue) (range: \(minVal)-\(maxVal))")
        }

        // Get the Defaults.Key
        guard let defaultsKey = keyMapping[key] else {
            diagLog.error("Settings URI: No mapping for key '\(key)'")
            return false
        }

        // Apply the setting
        Defaults.set(clampedValue, forKey: defaultsKey)

        // Notify settings models that a value changed externally
        postSettingsDidChangeNotification(key: key, doubleValue: clampedValue)

        diagLog.info("Settings URI: Set \(key) = \(clampedValue)")

        return true
    }

    /// Handles setting an enum value.
    private static func handleEnumSet(key: String, value: String) -> Bool {
        if key == "rehideStrategy" {
            guard let strategy = RehideStrategy.fromString(value) else {
                diagLog.warning("Settings URI: Invalid rehideStrategy value '\(value)'. Valid: smart (0), timed (1), focusedApp/focused_app (2)")
                return false
            }

            guard let defaultsKey = keyMapping[key] else {
                diagLog.error("Settings URI: No mapping for key '\(key)'")
                return false
            }

            Defaults.set(strategy.rawValue, forKey: defaultsKey)
            postSettingsDidChangeNotification(key: key, rawEnumValue: strategy.rawValue)
            diagLog.info("Settings URI: Set \(key) = \(strategy) (\(strategy.rawValue))")
            return true
        }
        return false
    }

    /// Handles setting a per-display configuration value.
    /// useIceBar: affects active display only (or specific display if UUID provided)
    /// iceBarLocation, alwaysShowHiddenItems: affects all displays with IceBar enabled (or specific display if UUID provided)
    private static func handlePerDisplaySet(key: String, value: String, displayUUID: String?) -> Bool {
        // If specific display UUID provided, use that
        if let uuid = displayUUID, !uuid.isEmpty {
            return handlePerDisplaySetForSpecificDisplay(key: key, value: value, displayUUID: uuid)
        }

        // Otherwise use default scope behavior
        switch key {
        case "useIceBar":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for useIceBar")
                return false
            }
            // Post notification for DisplaySettingsManager to handle active display
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: .activeDisplay)
            diagLog.info("Settings URI: Set useIceBar = \(boolValue) on active display")
            return true

        case "iceBarLocation":
            // Parse IceBarLocation from string value
            guard let location = IceBarLocation.fromString(value) else {
                diagLog.warning("Settings URI: Invalid iceBarLocation value '\(value)'. Valid: dynamic, mousePointer, iceIcon, leftAligned, rightAligned (or 0-4)")
                return false
            }
            // Post notification for DisplaySettingsManager to handle all enabled displays
            // Use rawValue string for consistency
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(location.rawValue), scope: .allEnabledDisplays)
            diagLog.info("Settings URI: Set iceBarLocation = \(location) on all enabled displays")
            return true

        case "alwaysShowHiddenItems":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for alwaysShowHiddenItems")
                return false
            }
            // Post notification for DisplaySettingsManager to handle all displays without IceBar
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: .allNonIceBarDisplays)
            diagLog.info("Settings URI: Set alwaysShowHiddenItems = \(boolValue) on all non-IceBar displays")
            return true

        case "iceBarLayout":
            guard let layout = IceBarLayout.fromString(value) else {
                diagLog.warning("Settings URI: Invalid iceBarLayout value '\(value)'. Valid: horizontal, vertical, grid (or 0, 1, 2)")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(layout.rawValue), scope: .allEnabledDisplays)
            diagLog.info("Settings URI: Set iceBarLayout = \(layout) on all enabled displays")
            return true

        case "gridColumns":
            guard let intValue = Int(value) else {
                diagLog.warning("Settings URI: Invalid gridColumns value '\(value)'")
                return false
            }
            let clamped = Swift.max(2, Swift.min(intValue, 10))
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(clamped), scope: .allEnabledDisplays)
            diagLog.info("Settings URI: Set gridColumns = \(clamped) on all enabled displays")
            return true

        default:
            return false
        }
    }

    /// Handles setting a per-display configuration value for a specific display UUID.
    private static func handlePerDisplaySetForSpecificDisplay(key: String, value: String, displayUUID: String) -> Bool {
        // Validate UUID format
        guard UUID(uuidString: displayUUID) != nil else {
            diagLog.warning("Settings URI: Invalid display UUID format '\(displayUUID)'")
            return false
        }

        // Validate display exists (connected or has persisted config)
        guard getDisplayConfiguration(forUUID: displayUUID) != nil else {
            diagLog.warning("Settings URI: Unknown display UUID '\(displayUUID)'")
            return false
        }

        switch key {
        case "useIceBar":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for useIceBar")
                return false
            }
            // Post notification for specific display
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: .specificDisplay(uuid: displayUUID))
            diagLog.info("Settings URI: Set useIceBar = \(boolValue) on display \(displayUUID)")
            return true

        case "iceBarLocation":
            // Parse IceBarLocation from string value
            guard let location = IceBarLocation.fromString(value) else {
                diagLog.warning("Settings URI: Invalid iceBarLocation value '\(value)'. Valid: dynamic, mousePointer, iceIcon, leftAligned, rightAligned (or 0-4)")
                return false
            }
            // Post notification for specific display
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(location.rawValue), scope: .specificDisplay(uuid: displayUUID))
            diagLog.info("Settings URI: Set iceBarLocation = \(location) on display \(displayUUID)")
            return true

        case "alwaysShowHiddenItems":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for alwaysShowHiddenItems")
                return false
            }
            // Post notification for specific display
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: .specificDisplay(uuid: displayUUID))
            diagLog.info("Settings URI: Set alwaysShowHiddenItems = \(boolValue) on display \(displayUUID)")
            return true

        case "iceBarLayout":
            guard let layout = IceBarLayout.fromString(value) else {
                diagLog.warning("Settings URI: Invalid iceBarLayout value '\(value)'. Valid: horizontal, vertical, grid (or 0, 1, 2)")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(layout.rawValue), scope: .specificDisplay(uuid: displayUUID))
            diagLog.info("Settings URI: Set iceBarLayout = \(layout) on display \(displayUUID)")
            return true

        case "gridColumns":
            guard let intValue = Int(value) else {
                diagLog.warning("Settings URI: Invalid gridColumns value '\(value)'")
                return false
            }
            let clamped = Swift.max(2, Swift.min(intValue, 10))
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(clamped), scope: .specificDisplay(uuid: displayUUID))
            diagLog.info("Settings URI: Set gridColumns = \(clamped) on display \(displayUUID)")
            return true

        default:
            return false
        }
    }

    /// Handles thaw://toggle?key=X URL.
    /// Returns true if setting was toggled successfully.
    static func handleToggle(key: String, sender: String?, displayUUID: String? = nil) -> Bool {
        diagLog.debug("Settings URI: toggle request - key=\(key), sender=\(sender ?? "unknown"), display=\(displayUUID ?? "none")")

        // Validate key
        guard isValidSettingsKey(key) else {
            diagLog.warning("Settings URI: Invalid key '\(key)'")
            return false
        }

        // Check if this is a per-display setting
        if perDisplayKeys.contains(key) {
            return handlePerDisplayToggle(key: key, displayUUID: displayUUID)
        }

        // Verify this is a boolean setting (not double or enum)
        guard supportedBooleanKeys.contains(key) else {
            diagLog.warning("Settings URI: Cannot toggle non-boolean key '\(key)'. Use set action instead.")
            return false
        }

        // Get the Defaults.Key
        guard let defaultsKey = keyMapping[key] else {
            diagLog.error("Settings URI: No mapping for key '\(key)'")
            return false
        }

        // Get current value and toggle
        let currentValue = Defaults.bool(forKey: defaultsKey)
        let newValue = !currentValue

        // Apply the setting
        Defaults.set(newValue, forKey: defaultsKey)

        // Notify settings models that a value changed externally
        postSettingsDidChangeNotification(key: key, value: newValue)

        diagLog.info("Settings URI: Toggled \(key) from \(currentValue) to \(newValue)")

        return true
    }

    /// Handles toggling a per-display configuration value.
    /// Currently only supports useIceBar and alwaysShowHiddenItems.
    private static func handlePerDisplayToggle(key: String, displayUUID: String?) -> Bool {
        // If specific display UUID provided, use that
        if let uuid = displayUUID, !uuid.isEmpty {
            // Validate UUID format
            guard uuid.contains("-"), !uuid.isEmpty else {
                diagLog.warning("Settings URI: Invalid display UUID format '\(uuid)'")
                return false
            }

            switch key {
            case "useIceBar":
                // Post notification for DisplaySettingsManager to toggle specific display
                postPerDisplaySettingsDidChangeNotification(key: key, toggle: true, scope: .specificDisplay(uuid: uuid))
                diagLog.info("Settings URI: Toggled useIceBar on display \(uuid)")
                return true

            case "alwaysShowHiddenItems":
                // Post notification for DisplaySettingsManager to toggle specific display
                postPerDisplaySettingsDidChangeNotification(key: key, toggle: true, scope: .specificDisplay(uuid: uuid))
                diagLog.info("Settings URI: Toggled alwaysShowHiddenItems on display \(uuid)")
                return true

            default:
                // iceBarLocation doesn't support toggle
                diagLog.warning("Settings URI: Toggle not supported for '\(key)'")
                return false
            }
        }

        // Default behavior without UUID
        switch key {
        case "useIceBar":
            // Post notification for DisplaySettingsManager to toggle active display
            postPerDisplaySettingsDidChangeNotification(key: key, toggle: true, scope: .activeDisplay)
            diagLog.info("Settings URI: Toggled useIceBar on active display")
            return true

        case "alwaysShowHiddenItems":
            // Post notification for DisplaySettingsManager to toggle on all non-IceBar displays
            postPerDisplaySettingsDidChangeNotification(key: key, toggle: true, scope: .allNonIceBarDisplays)
            diagLog.info("Settings URI: Toggled alwaysShowHiddenItems on all non-IceBar displays")
            return true

        default:
            // iceBarLocation doesn't support toggle
            diagLog.warning("Settings URI: Toggle not supported for '\(key)'")
            return false
        }
    }

    /// Posts a notification that a setting was changed externally via Settings URI.
    private static func postSettingsDidChangeNotification(key: String, value: Bool) {
        NotificationCenter.default.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: [
                "key": key,
                "value": value,
            ]
        )
    }

    /// Posts a notification for double value settings.
    private static func postSettingsDidChangeNotification(key: String, doubleValue: Double) {
        NotificationCenter.default.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: [
                "key": key,
                "doubleValue": doubleValue,
            ]
        )
    }

    /// Posts a notification for enum value settings.
    private static func postSettingsDidChangeNotification(key: String, rawEnumValue: Int) {
        NotificationCenter.default.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: [
                "key": key,
                "rawEnumValue": rawEnumValue,
            ]
        )
    }

    /// Posts a notification for per-display settings changes.
    private static func postPerDisplaySettingsDidChangeNotification(
        key: String,
        value: Bool? = nil,
        stringValue: String? = nil,
        toggle: Bool = false,
        scope: PerDisplayScope
    ) {
        var userInfo: [String: Any] = [
            "key": key,
            "scope": scope.rawValue,
        ]
        if let value {
            userInfo["value"] = value
        }
        if let stringValue {
            userInfo["stringValue"] = stringValue
        }
        if toggle {
            userInfo["toggle"] = true
        }

        NotificationCenter.default.post(
            name: .perDisplaySettingsDidChangeViaURI,
            object: nil,
            userInfo: userInfo
        )
    }

    /// Scope for per-display setting application.
    enum PerDisplayScope: Equatable {
        case activeDisplay
        case allEnabledDisplays
        case allNonIceBarDisplays
        case specificDisplay(uuid: String)

        /// String representation for notification userInfo
        var rawValue: String {
            switch self {
            case .activeDisplay: return "active"
            case .allEnabledDisplays: return "allEnabled"
            case .allNonIceBarDisplays: return "allNonIceBar"
            case let .specificDisplay(uuid): return "specific:\(uuid)"
            }
        }

        /// Extract UUID if this is a specific display scope
        var specificUUID: String? {
            if case let .specificDisplay(uuid) = self {
                return uuid
            }
            return nil
        }
    }

    /// Returns the current whitelist as an array of bundle IDs.
    static func getWhitelist() -> [String] {
        return Defaults.stringArray(forKey: .settingsURIWhitelist) ?? []
    }

    /// Checks if Settings URI feature is enabled.
    static func isEnabled() -> Bool {
        return Defaults.bool(forKey: .settingsURIEnabled)
    }

    // MARK: - Getters (Read Operations)

    /// Handles thaw://get?key=X&callback=Y URLs.
    /// Returns settings values via callback URL or distributed notification.
    static func handleGet(
        key: String?,
        displayUUID: String?,
        callback: String?,
        broadcast: Bool,
        requestId: String?
    ) -> Bool {
        let responseId = requestId ?? UUID().uuidString

        // Validate response mechanism
        guard callback != nil || broadcast else {
            diagLog.warning("Settings URI Get: No response mechanism provided - provide callback=<url> or broadcast=true")
            return false
        }

        // Gather requested data
        let response: [String: Any] = if let singleKey = key {
            // Single key request
            handleSingleKeyGet(key: singleKey, displayUUID: displayUUID, requestId: responseId)
        } else {
            // No key specified - error
            createErrorResponse(requestId: responseId, error: "No key specified", details: "Provide key=<name>")
        }

        // Send response
        if let callbackURL = callback {
            // Full data sent via callback URL (direct to requesting app)
            return sendCallbackResponse(response: response, callback: callbackURL)
        } else if broadcast {
            // Broadcast only sends acknowledgment, not full settings data (security)
            let ackResponse: [String: Any] = [
                "requestId": responseId,
                "status": "ack",
                "message": "Use callback URL to receive full settings data",
            ]
            return sendBroadcastResponse(response: ackResponse)
        }

        return false
    }

    /// Handles getting a single key's value.
    private static func handleSingleKeyGet(key: String, displayUUID: String?, requestId: String) -> [String: Any] {
        switch key {
        case "all":
            return getAllSettings(requestId: requestId)
        case "displays":
            return getAllDisplays(requestId: requestId)
        case "display":
            if let uuid = displayUUID {
                return getSpecificDisplay(uuid: uuid, requestId: requestId)
            } else {
                return createErrorResponse(requestId: requestId, error: "Display UUID required", details: "Provide display=<uuid> when key=display")
            }
        case "version":
            let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            return [
                "requestId": requestId,
                "status": "success",
                "key": "version",
                "data": [
                    "value": shortVersion,
                    "build": buildVersion,
                    "type": "string",
                ],
            ]
        default:
            // Individual setting
            if let value = getSettingValue(key: key, displayUUID: displayUUID) {
                return [
                    "requestId": requestId,
                    "status": "success",
                    "key": key,
                    "data": value,
                ]
            } else {
                return createErrorResponse(requestId: requestId, error: "Setting not found or invalid key", details: "Key: \(key)")
            }
        }
    }

    /// Gets a single setting value with metadata.
    private static func getSettingValue(key: String, displayUUID: String?) -> [String: Any]? {
        // Handle per-display keys specially (not in keyMapping)
        if perDisplayKeys.contains(key) {
            // Validate display UUID if provided
            guard let config = getDisplayConfiguration(forUUID: displayUUID) else {
                // Unknown display UUID
                return nil
            }

            switch key {
            case "useIceBar":
                return [
                    "value": config.useIceBar,
                    "type": "boolean",
                ]
            case "iceBarLocation":
                return [
                    "value": String(describing: config.iceBarLocation),
                    "rawValue": config.iceBarLocation.rawValue,
                    "type": "enum",
                    "validValues": ["dynamic": 0, "mousePointer": 1, "iceIcon": 2],
                ]
            case "alwaysShowHiddenItems":
                return [
                    "value": config.alwaysShowHiddenItems,
                    "type": "boolean",
                ]
            case "iceBarLayout":
                return [
                    "value": String(describing: config.iceBarLayout),
                    "rawValue": config.iceBarLayout.rawValue,
                    "type": "enum",
                    "validValues": ["horizontal": 0, "vertical": 1, "grid": 2],
                ]
            case "gridColumns":
                return [
                    "value": config.gridColumns,
                    "type": "integer",
                    "range": ["min": 2, "max": 10],
                ]
            default:
                return nil
            }
        }

        // Check if it's a boolean setting
        if supportedBooleanKeys.contains(key) {
            guard let defaultsKey = keyMapping[key] else { return nil }
            let value = Defaults.bool(forKey: defaultsKey)
            return [
                "value": value,
                "type": "boolean",
            ]
        }

        // Check if it's a double setting
        if doubleKeys.contains(key) {
            guard let defaultsKey = keyMapping[key] else { return nil }
            let value = Defaults.double(forKey: defaultsKey)
            let range = doubleRanges[key]
            var result: [String: Any] = [
                "value": value,
                "type": "double",
            ]
            if let (min, max) = range {
                result["range"] = ["min": min, "max": max]
            }
            return result
        }

        // Check if it's an enum setting
        if enumKeys.contains(key) {
            guard let defaultsKey = keyMapping[key] else { return nil }
            let rawValue = Defaults.integer(forKey: defaultsKey)

            if key == "rehideStrategy", let strategy = RehideStrategy(rawValue: rawValue) {
                return [
                    "value": String(describing: strategy),
                    "rawValue": rawValue,
                    "type": "enum",
                    "validValues": ["smart": 0, "timed": 1, "focusedApp": 2],
                ]
            }

            return [
                "rawValue": rawValue,
                "type": "enum",
            ]
        }

        return nil
    }

    /// Gets all settings including per-display configurations.
    private static func getAllSettings(requestId: String) -> [String: Any] {
        var globalSettings: [String: [String: Any]] = [:]

        // Boolean settings
        for key in supportedBooleanKeys where !perDisplayKeys.contains(key) {
            if let value = getSettingValue(key: key, displayUUID: nil) {
                globalSettings[key] = value
            }
        }

        // Double settings
        for key in doubleKeys {
            if let value = getSettingValue(key: key, displayUUID: nil) {
                globalSettings[key] = value
            }
        }

        // Enum settings
        for key in enumKeys {
            if let value = getSettingValue(key: key, displayUUID: nil) {
                globalSettings[key] = value
            }
        }

        // Per-display settings
        var displaysData: [String: [String: Any]] = [:]
        for screen in NSScreen.screens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
            displaysData[uuid] = getDisplayInfo(screen: screen, uuid: uuid)
        }

        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        return [
            "requestId": requestId,
            "status": "success",
            "data": [
                "appVersion": [
                    "value": shortVersion,
                    "build": buildVersion,
                ],
                "global": globalSettings,
                "displays": displaysData,
            ],
        ]
    }

    /// Gets the display configuration for a specific UUID, or the active display if nil.
    /// Returns nil if a specific UUID is provided but doesn't match any connected or persisted display.
    private static func getDisplayConfiguration(forUUID uuid: String?) -> DisplayIceBarConfiguration? {
        let configurations = Defaults.data(forKey: .displayIceBarConfigurations)
            .flatMap { try? JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: $0) }
            ?? [:]

        if let uuid {
            // Check if UUID matches a connected display
            let connectedUUIDs = NSScreen.screens.compactMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
            let isConnected = connectedUUIDs.contains(uuid)
            let hasPersisted = configurations[uuid] != nil

            // Return nil if UUID doesn't match any known display
            guard isConnected || hasPersisted else {
                return nil
            }
            return configurations[uuid] ?? .defaultConfiguration
        }

        // Use active display
        guard let activeDisplayID = Bridging.getActiveMenuBarDisplayID(),
              let activeUUID = Bridging.getDisplayUUIDString(for: activeDisplayID)
        else {
            return .defaultConfiguration
        }
        return configurations[activeUUID] ?? .defaultConfiguration
    }

    /// Gets information for a specific display.
    private static func getDisplayInfo(screen: NSScreen, uuid: String) -> [String: Any] {
        let config = Defaults.data(forKey: .displayIceBarConfigurations)
            .flatMap { try? JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: $0) }?[uuid]
            ?? .defaultConfiguration

        let displayID = screen.displayID
        let isConnected = CGDisplayIsActive(displayID) != 0

        return [
            "name": screen.localizedName,
            "isConnected": isConnected,
            "isPrimary": screen == NSScreen.main,
            "hasNotch": screen.hasNotch,
            "resolution": "\(Int(screen.frame.width))x\(Int(screen.frame.height))",
            "useIceBar": config.useIceBar,
            "iceBarLocation": String(describing: config.iceBarLocation),
            "alwaysShowHiddenItems": config.alwaysShowHiddenItems,
            "iceBarLayout": String(describing: config.iceBarLayout),
            "gridColumns": config.gridColumns,
        ]
    }

    /// Gets all displays.
    private static func getAllDisplays(requestId: String) -> [String: Any] {
        var displays: [[String: Any]] = []

        for screen in NSScreen.screens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else { continue }
            var info = getDisplayInfo(screen: screen, uuid: uuid)
            info["uuid"] = uuid
            displays.append(info)
        }

        return [
            "requestId": requestId,
            "status": "success",
            "data": ["displays": displays],
        ]
    }

    /// Gets a specific display by UUID.
    private static func getSpecificDisplay(uuid: String, requestId: String) -> [String: Any] {
        // Find screen with matching UUID
        for screen in NSScreen.screens {
            guard let screenUUID = Bridging.getDisplayUUIDString(for: screen.displayID),
                  screenUUID == uuid else { continue }

            var info = getDisplayInfo(screen: screen, uuid: uuid)
            info["uuid"] = uuid

            return [
                "requestId": requestId,
                "status": "success",
                "data": info,
            ]
        }

        // Check if we have config for disconnected display
        if let configs = Defaults.data(forKey: .displayIceBarConfigurations)
            .flatMap({ try? JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: $0) }),
            let config = configs[uuid]
        {
            return [
                "requestId": requestId,
                "status": "success",
                "data": [
                    "uuid": uuid,
                    "name": "Disconnected Display",
                    "isConnected": false,
                    "useIceBar": config.useIceBar,
                    "iceBarLocation": String(describing: config.iceBarLocation),
                    "alwaysShowHiddenItems": config.alwaysShowHiddenItems,
                    "iceBarLayout": String(describing: config.iceBarLayout),
                    "gridColumns": config.gridColumns,
                ],
            ]
        }

        return createErrorResponse(requestId: requestId, error: "Display not found", details: "UUID: \(uuid)")
    }

    /// Creates an error response.
    private static func createErrorResponse(requestId: String, error: String, details: String? = nil) -> [String: Any] {
        var response: [String: Any] = [
            "requestId": requestId,
            "status": "error",
            "error": error,
        ]
        if let details {
            response["details"] = details
        }
        return response
    }

    /// Blocked schemes for callback URLs (security).
    private static let blockedCallbackSchemes: Set<String> = ["file", "javascript", "data", "about", "blob"]

    /// Sends response via callback URL.
    private static func sendCallbackResponse(response: [String: Any], callback: String) -> Bool {
        // Parse callback URL with URLComponents for safe composition
        guard var components = URLComponents(string: callback) else {
            diagLog.error("Settings URI Get: Invalid callback URL format: \(callback)")
            return false
        }

        // Validate scheme exists
        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            diagLog.error("Settings URI Get: Callback URL missing scheme: \(callback)")
            return false
        }

        // Reject dangerous schemes
        if blockedCallbackSchemes.contains(scheme) || scheme.hasPrefix("x-apple-") {
            diagLog.error("Settings URI Get: Callback URL scheme not allowed: \(scheme)")
            return false
        }

        // Encode response as JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            diagLog.error("Settings URI Get: Failed to encode callback response")
            return false
        }

        // Preserve existing query items and append data
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "data", value: jsonString))
        components.queryItems = queryItems

        // Build final URL
        guard let callbackURL = components.url else {
            diagLog.error("Settings URI Get: Failed to compose callback URL")
            return false
        }

        // Open callback URL
        let success = NSWorkspace.shared.open(callbackURL)
        if success {
            diagLog.info("Settings URI Get: Sent callback via scheme: \(scheme)")
        } else {
            diagLog.error("Settings URI Get: Failed to open callback via scheme: \(scheme)")
        }
        return success
    }

    /// Sends response via distributed notification.
    private static func sendBroadcastResponse(response: [String: Any]) -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            diagLog.error("Settings URI Get: Failed to encode broadcast response")
            return false
        }

        DistributedNotificationCenter.default().postNotificationName(
            .settingsURIGetResponse,
            object: nil,
            userInfo: ["json": jsonString],
            deliverImmediately: true
        )

        diagLog.info("Settings URI Get: Broadcasted response via distributed notification")
        return true
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a setting is changed externally via Settings URI scheme.
    static let settingsDidChangeViaURI = Notification.Name("com.stonerl.Thaw.settingsDidChangeViaURI")

    /// Posted when a per-display setting is changed externally via Settings URI scheme.
    static let perDisplaySettingsDidChangeViaURI = Notification.Name("com.stonerl.Thaw.perDisplaySettingsDidChangeViaURI")

    /// Posted when a get request response is broadcast via distributed notification.
    static let settingsURIGetResponse = Notification.Name("com.stonerl.Thaw.settingsURIGetResponse")

    /// Posted when the Settings URI whitelist changes.
    static let settingsURIWhitelistDidChange = Notification.Name("com.stonerl.Thaw.settingsURIWhitelistDidChange")
}
