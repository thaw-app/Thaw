//
//  SettingsURIHandler.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import MenuBarModel
import Security

/// Handles settings manipulation via thaw:// URLs with whitelist-based security.
@MainActor
enum SettingsURIHandler {
    static let diagLog = DiagLog(category: "SettingsURIHandler")

    /// Tests use a private center so fixture writes cannot reach the running app's settings models.
    static var settingsChangeNotificationCenter = NotificationCenter.default

    /// Tests swap these so a response never opens a URL or reaches another process.
    static var openCallbackURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    static var postBroadcastJSON: (String) -> Void = { json in
        DistributedNotificationCenter.default().postNotificationName(
            .settingsURIGetResponse,
            object: nil,
            userInfo: ["json": json],
            deliverImmediately: true
        )
    }

    /// Keep global allow-lists, Defaults.Key mappings, and bounds together to prevent drift.
    /// Per-display settings live in DisplaySettingsManager and perDisplayKeys instead.
    struct SettingURIEntry {
        /// How a setting's value is stored and parsed.
        enum Kind {
            case boolean
            case double(min: Double, max: Double)
            case integer(min: Int, max: Int)
            /// An integer-backed enum validated by name, currently only
            /// RehideStrategy.
            case enumeration
            case string
        }

        let defaultsKey: Defaults.Key
        let kind: Kind
        let isWritable: Bool

        var isBoolean: Bool {
            if case .boolean = kind {
                return true
            }
            return false
        }
    }

    /// Unset keys read registered Defaults values; SettingsURIKeyTableTests ensures every global table key is registered.
    static let keyTable: [String: SettingURIEntry] = [
        // MARK: - General
        "showThawIcon": SettingURIEntry(defaultsKey: .showThawIcon, kind: .boolean, isWritable: true),
        "customThawIconIsTemplate": SettingURIEntry(defaultsKey: .customThawIconIsTemplate, kind: .boolean, isWritable: true),
        "simpleMode": SettingURIEntry(defaultsKey: .simpleMode, kind: .boolean, isWritable: true),
        "showSettingDescriptions": SettingURIEntry(defaultsKey: .showSettingDescriptions, kind: .boolean, isWritable: true),
        "lockThawBarPosition": SettingURIEntry(defaultsKey: .lockThawBarPosition, kind: .boolean, isWritable: true),
        "enableThawBarOnly": SettingURIEntry(defaultsKey: .enableThawBarOnly, kind: .boolean, isWritable: true),
        "openHiddenItemsInMenuBar": SettingURIEntry(defaultsKey: .openHiddenItemsInMenuBar, kind: .boolean, isWritable: true),
        "showThawBarOnlyWithInlineReveal": SettingURIEntry(defaultsKey: .showThawBarOnlyWithInlineReveal, kind: .boolean, isWritable: true),
        "showThawBarOnlyLauncher": SettingURIEntry(defaultsKey: .showThawBarOnlyLauncher, kind: .boolean, isWritable: true),
        "useThawBarOnlyOnNotchedDisplay": SettingURIEntry(defaultsKey: .useThawBarOnlyOnNotchedDisplay, kind: .boolean, isWritable: true),
        "thawBarLocationOnHotkey": SettingURIEntry(defaultsKey: .thawBarLocationOnHotkey, kind: .boolean, isWritable: true),
        "showOnClick": SettingURIEntry(defaultsKey: .showOnClick, kind: .boolean, isWritable: true),
        "showOnHover": SettingURIEntry(defaultsKey: .showOnHover, kind: .boolean, isWritable: true),
        "showOnScroll": SettingURIEntry(defaultsKey: .showOnScroll, kind: .boolean, isWritable: true),
        "autoRehide": SettingURIEntry(defaultsKey: .autoRehide, kind: .boolean, isWritable: true),
        "rehideInterval": SettingURIEntry(defaultsKey: .rehideInterval, kind: .double(min: 1, max: 300), isWritable: true),
        "tempShowInterval": SettingURIEntry(defaultsKey: .tempShowInterval, kind: .double(min: 0, max: 30), isWritable: true),
        "rehideStrategy": SettingURIEntry(defaultsKey: .rehideStrategy, kind: .enumeration, isWritable: true),

        // MARK: - Advanced
        "enableAlwaysHiddenSection": SettingURIEntry(defaultsKey: .enableAlwaysHiddenSection, kind: .boolean, isWritable: true),
        "showAllSectionsOnUserDrag": SettingURIEntry(defaultsKey: .showAllSectionsOnUserDrag, kind: .boolean, isWritable: true),
        "hideApplicationMenus": SettingURIEntry(defaultsKey: .hideApplicationMenus, kind: .boolean, isWritable: true),
        "enableSecondaryContextMenu": SettingURIEntry(defaultsKey: .enableSecondaryContextMenu, kind: .boolean, isWritable: true),
        "showMenuBarTooltips": SettingURIEntry(defaultsKey: .showMenuBarTooltips, kind: .boolean, isWritable: true),
        "showOnHoverDelay": SettingURIEntry(defaultsKey: .showOnHoverDelay, kind: .double(min: 0, max: 5), isWritable: true),
        "tooltipDelay": SettingURIEntry(defaultsKey: .tooltipDelay, kind: .double(min: 0, max: 5), isWritable: true),
        "iconRefreshInterval": SettingURIEntry(defaultsKey: .iconRefreshInterval, kind: .double(min: 0, max: 5), isWritable: true),
        "menuBarItemAlertRevealCooldown": SettingURIEntry(defaultsKey: .menuBarItemAlertRevealCooldown, kind: .double(min: 5, max: 300), isWritable: true),
        "menuBarOrderFulfillmentTimeout": SettingURIEntry(defaultsKey: .menuBarOrderFulfillmentTimeout, kind: .double(min: 1, max: 15), isWritable: true),
        "autoZenWhileSharingScreen": SettingURIEntry(defaultsKey: .autoZenWhileSharingScreen, kind: .boolean, isWritable: true),
        "enableDiagnosticLogging": SettingURIEntry(defaultsKey: .enableDiagnosticLogging, kind: .boolean, isWritable: true),
        "enableMenuBarItemOverflow": SettingURIEntry(defaultsKey: .enableMenuBarItemOverflow, kind: .boolean, isWritable: true),
        "enableExperimentalSystemItemHiding": SettingURIEntry(defaultsKey: .enableExperimentalSystemItemHiding, kind: .boolean, isWritable: true),
        "enableExperimentalOverflowPrevention": SettingURIEntry(defaultsKey: .enableExperimentalOverflowPrevention, kind: .boolean, isWritable: true),
        "alwaysUseAppIconForMenuBarItems": SettingURIEntry(defaultsKey: .alwaysUseAppIconForMenuBarItems, kind: .boolean, isWritable: true),
        "enableMenuBarItemDescenders": SettingURIEntry(defaultsKey: .enableMenuBarItemDescenders, kind: .boolean, isWritable: true),
        "enableSwapBar": SettingURIEntry(defaultsKey: .enableSwapBar, kind: .boolean, isWritable: true),
        "swapOnThawIconClick": SettingURIEntry(defaultsKey: .swapOnThawIconClick, kind: .boolean, isWritable: true),
        "enableControlItemPanel": SettingURIEntry(defaultsKey: .enableControlItemPanel, kind: .boolean, isWritable: true),
        "fetchReleaseNotes": SettingURIEntry(defaultsKey: .fetchReleaseNotes, kind: .boolean, isWritable: true),
        "enableRecordingWatch": SettingURIEntry(defaultsKey: .enableRecordingWatch, kind: .boolean, isWritable: true),
        "zenModeWhileRecording": SettingURIEntry(defaultsKey: .zenModeWhileRecording, kind: .boolean, isWritable: true),
        "enableDesktopMenuHiding": SettingURIEntry(defaultsKey: .enableDesktopMenuHiding, kind: .boolean, isWritable: true),

        // MARK: - Search
        "searchIncludeVisible": SettingURIEntry(defaultsKey: .searchIncludeVisible, kind: .boolean, isWritable: true),
        "searchIncludeHidden": SettingURIEntry(defaultsKey: .searchIncludeHidden, kind: .boolean, isWritable: true),
        "searchIncludeAlwaysHidden": SettingURIEntry(defaultsKey: .searchIncludeAlwaysHidden, kind: .boolean, isWritable: true),
    ]

    /// Derived from keyTable so the allow-lists can never disagree with it.
    static var supportedBooleanKeys: [String] {
        keyTable.compactMap { $0.value.isBoolean ? $0.key : nil }.sorted()
    }

    static var doubleKeys: [String] {
        keyTable.compactMap { entry in
            if case .double = entry.value.kind {
                return entry.key
            }
            return nil
        }.sorted()
    }

    static var enumKeys: [String] {
        keyTable.compactMap { entry in
            if case .enumeration = entry.value.kind {
                return entry.key
            }
            return nil
        }.sorted()
    }

    /// Per-display settings keys (stored in DisplaySettingsManager, not Defaults)
    static let perDisplayKeys: [String] = [
        "useThawBar",
        "thawBarLocation",
        "alwaysShowHiddenItems",
        "thawBarLayout",
        "gridColumns",
    ]

    // MARK: - Security

    /// Apps from the same developer that may control settings without the authorization prompt.
    /// Any app can claim a bundle ID, so the app must also carry this app's team ID.
    static let builtInTrustedBundleIDs: Set<String> = ["com.thaw.floe"]

    /// Whether a sender is trusted without asking: a built-in bundle ID signed by this app's team.
    /// An unsigned build of either side has no team and is never trusted this way.
    static func isBuiltInTrusted(bundleId: String, senderTeamID: String?, ownTeamID: String?) -> Bool {
        guard builtInTrustedBundleIDs.contains(bundleId),
              let senderTeamID, let ownTeamID
        else { return false }
        return senderTeamID == ownTeamID
    }

    /// Whether the installed app with this bundle ID is a built-in trusted sender.
    /// Such a sender also works while the Settings URI feature is switched off.
    /// The team lookups are parameters so the rule can be tested without a signed build.
    static func isBuiltInTrustedSender(
        bundleIdentifier: String?,
        senderTeamID: (String) -> String? = { getTeamIdentifier(for: $0) },
        ownTeamID: () -> String? = { teamIdentifier(ofAppAt: Bundle.main.bundleURL, logName: "this app") }
    ) -> Bool {
        guard let bundleIdentifier, builtInTrustedBundleIDs.contains(bundleIdentifier) else { return false }
        return isBuiltInTrusted(
            bundleId: bundleIdentifier,
            senderTeamID: senderTeamID(bundleIdentifier),
            ownTeamID: ownTeamID()
        )
    }

    /// Gets the team identifier for a bundle ID by checking the app's code signature.
    private static func getTeamIdentifier(for bundleId: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            diagLog.debug("Settings URI: Cannot find app URL for \(bundleId)")
            return nil
        }
        return teamIdentifier(ofAppAt: appURL, logName: bundleId)
    }

    /// The team identifier in the code signature of the app at appURL.
    static func teamIdentifier(ofAppAt appURL: URL, logName bundleId: String) -> String? {
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

        if let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String {
            return teamId
        }

        diagLog.debug("Settings URI: No team identifier found for \(bundleId)")
        return nil
    }

    /// Verifies that an app's current code signature matches the stored signing identity.
    private static func verifyCodeSignature(bundleId: String, storedTeamId: String?) -> Bool {
        // Without a stored team ID, authorize only apps that also have no current team ID.
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

    private static func getSigningIdentities() -> [String: String] {
        guard let data = Defaults.data(forKey: .settingsURISigningIdentities),
              let identities = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return identities
    }

    private static func saveSigningIdentities(_ identities: [String: String]) {
        if let data = try? JSONEncoder().encode(identities) {
            Defaults.set(data, forKey: .settingsURISigningIdentities)
        }
    }

    /// Checks if the sender is in the whitelist and has valid code signature.
    static func isWhitelisted(
        bundleIdentifier: String?,
        builtInTrust: (String) -> Bool = { isBuiltInTrustedSender(bundleIdentifier: $0) }
    ) -> Bool {
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty else {
            diagLog.warning("Settings URI: No sender bundle ID provided")
            return false
        }

        if builtInTrust(bundleId) {
            diagLog.debug("Settings URI: Authorized built-in request from \(bundleId)")
            return true
        }

        let whitelist = Defaults.stringArray(forKey: .settingsURIWhitelist) ?? []
        guard whitelist.contains(bundleId) else {
            diagLog.debug("Settings URI: Unauthorized request from \(bundleId)")
            return false
        }

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
        alert.messageText = String(localized: "Allow “\(appName)” to control \(Constants.displayName) settings?")

        let baseText = String(
            localized: """
            If granted, this app will be able to:

            • Read current settings and configurations
            • Turn features and options on or off
            • Adjust timing values (delays, intervals, timers)
            • Change how \(Constants.displayName) Bar behaves
            • Customize settings for each display

            This permission stays active until removed in \(Constants.displayName)’s Automation settings.
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

        var identities = getSigningIdentities()
        identities.removeValue(forKey: bundleId)
        saveSigningIdentities(identities)

        diagLog.info("Settings URI: Removed \(bundleId) from whitelist")
        NotificationCenter.default.post(name: .settingsURIWhitelistDidChange, object: nil)
    }

    static func getAppName(for bundleId: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return app.localizedName
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url)
        {
            return bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        }

        return nil
    }

    static func getAppIcon(for bundleId: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    // MARK: - Validation

    /// Accept Ice parameter aliases for script compatibility; output uses current names.
    private static let legacyKeyAliases: [String: String] = [
        "useIceBar": "useThawBar",
        "useIceBarOnlyOnNotchedDisplay": "useThawBarOnlyOnNotchedDisplay",
        "customIceIconIsTemplate": "customThawIconIsTemplate",
        "showIceIcon": "showThawIcon",
        "iceBarLocationOnHotkey": "thawBarLocationOnHotkey",
        "iceBarLocation": "thawBarLocation",
        "iceBarLayout": "thawBarLayout",
    ]

    static func canonicalKey(_ key: String) -> String {
        legacyKeyAliases[key] ?? key
    }

    /// Checks if a settings key is supported for URI manipulation.
    static func isValidSettingsKey(_ key: String) -> Bool {
        let key = canonicalKey(key)
        return keyTable[key] != nil || perDisplayKeys.contains(key)
    }

    /// Unset keys use shipped defaults registered through object(forKey:).
    private static func effectiveBool(for entry: SettingURIEntry) -> Bool {
        (Defaults.object(forKey: entry.defaultsKey) as? Bool) ?? false
    }

    /// Reads a double setting's effective value, with the same registered-default
    /// lookup as effectiveBool(for:).
    private static func effectiveDouble(for entry: SettingURIEntry) -> Double {
        (Defaults.object(forKey: entry.defaultsKey) as? Double) ?? 0
    }

    static func parseBool(_ value: String) -> Bool? {
        let lowercased = value.lowercased()
        if lowercased == "true" || lowercased == "1" || lowercased == "yes" {
            return true
        } else if lowercased == "false" || lowercased == "0" || lowercased == "no" {
            return false
        }
        return nil
    }

    static func parseDouble(_ value: String) -> Double? {
        return Double(value)
    }

    // MARK: - Execution

    /// Handles "thaw://set?key=X&value=Y&type=bool" URLs.
    /// Returns true if setting was changed successfully.
    static func handleSet(key: String, value: String, sender: String?, displayUUID: String? = nil) -> Bool {
        let key = canonicalKey(key)
        diagLog.debug("Settings URI: set request - key=\(key), value=\(value), sender=\(sender ?? "unknown"), display=\(displayUUID ?? "none")")

        guard isValidSettingsKey(key) else {
            diagLog.warning("Settings URI: Invalid key '\(key)'")
            return false
        }

        if perDisplayKeys.contains(key) {
            return handlePerDisplaySet(key: key, value: value, displayUUID: displayUUID)
        }

        guard let entry = keyTable[key] else {
            diagLog.error("Settings URI: No mapping for key '\(key)'")
            return false
        }

        guard entry.isWritable else {
            diagLog.warning("Settings URI: Key '\(key)' is read-only")
            return false
        }

        switch entry.kind {
        case .boolean:
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)'")
                return false
            }

            guard applyBooleanSetting(boolValue, key: key, entry: entry) else { return false }

            diagLog.info("Settings URI: Set \(key) = \(boolValue)")

            return true

        case .double:
            return handleDoubleSet(key: key, value: value, entry: entry)

        case .enumeration:
            return handleEnumSet(key: key, value: value, entry: entry)

        case .integer, .string:
            // No global integer or string setting is published yet.
            diagLog.warning("Settings URI: Key '\(key)' has an unsupported kind")
            return false
        }
    }

    private static func applyBooleanSetting(_ value: Bool, key: String, entry: SettingURIEntry) -> Bool {
        if entry.defaultsKey == .enableExperimentalSystemItemHiding,
           value, Defaults.bool(forKey: .enableNativeAppHiding)
        {
            diagLog.warning("Settings URI: Cannot enable system item hiding while native app hiding is enabled")
            return false
        }
        Defaults.set(value, forKey: entry.defaultsKey)
        postSettingsDidChangeNotification(key: key, value: value)
        return true
    }

    /// Handles setting a double/numeric value with range validation.
    private static func handleDoubleSet(key: String, value: String, entry: SettingURIEntry) -> Bool {
        guard let doubleValue = parseDouble(value) else {
            diagLog.warning("Settings URI: Invalid double value '\(value)' for \(key)")
            return false
        }

        // Reject non-finite values (NaN, Infinity)
        guard doubleValue.isFinite else {
            diagLog.warning("Settings URI: Non-finite value '\(value)' not allowed for \(key)")
            return false
        }

        guard case let .double(minVal, maxVal) = entry.kind else {
            return false
        }

        let clampedValue = Swift.max(minVal, Swift.min(doubleValue, maxVal))

        if clampedValue != doubleValue {
            diagLog.debug("Settings URI: Clamped \(key) from \(doubleValue) to \(clampedValue) (range: \(minVal)-\(maxVal))")
        }

        Defaults.set(clampedValue, forKey: entry.defaultsKey)

        postSettingsDidChangeNotification(key: key, doubleValue: clampedValue)

        diagLog.info("Settings URI: Set \(key) = \(clampedValue)")

        return true
    }

    private static func handleEnumSet(key: String, value: String, entry: SettingURIEntry) -> Bool {
        guard key == "rehideStrategy", let strategy = RehideStrategy.fromString(value) else {
            diagLog.warning("Settings URI: Invalid rehideStrategy value '\(value)'. Valid: smart (0), timed (1), focusedApp/focused_app (2)")
            return false
        }

        Defaults.set(strategy.rawValue, forKey: entry.defaultsKey)
        postSettingsDidChangeNotification(key: key, rawEnumValue: strategy.rawValue)
        diagLog.info("Settings URI: Set \(key) = \(strategy) (\(strategy.rawValue))")
        return true
    }

    // MARK: - Reveal Item Resolution

    /// Require exactly one of bundle or itemID; canonicalize itemID directly.
    /// Reject bundle requests unless the bundleID: prefix matches exactly one assigned identifier.
    static func resolveRevealItemIdentifier(
        bundle: String?,
        itemID: String?,
        sectionAssignment: [String: MenuBarSection.Name]
    ) -> String? {
        let hasBundle = !(bundle?.isEmpty ?? true)
        let hasItemID = !(itemID?.isEmpty ?? true)

        guard hasBundle != hasItemID else {
            diagLog.warning(
                "Settings URI reveal-item: expected exactly one of bundle/item-id, got bundle=\(bundle ?? "nil"), item-id=\(itemID ?? "nil")"
            )
            return nil
        }

        if hasItemID, let itemID {
            return MenuBarItemTag.canonicalPersistentIdentifier(itemID)
        }

        guard let bundle else { return nil }

        let prefix = "\(bundle):"
        let matches = sectionAssignment.keys.filter { $0.hasPrefix(prefix) }
        guard let match = matches.first, matches.count == 1 else {
            diagLog.warning(
                "Settings URI reveal-item: bundle '\(bundle)' matched \(matches.count) assigned item(s), expected exactly 1"
            )
            return nil
        }

        return match
    }

    /// Set and toggle share scope validation: nonempty UUIDs must name known displays; omitted UUIDs use the key's default scope.
    private static func resolvePerDisplayScope(key: String, displayUUID: String?) -> PerDisplayScope? {
        if let uuid = displayUUID, !uuid.isEmpty {
            guard UUID(uuidString: uuid) != nil else {
                diagLog.warning("Settings URI: Invalid display UUID format '\(uuid)'")
                return nil
            }
            // Connected displays and displays with a persisted config both count.
            guard getDisplayConfiguration(forUUID: uuid) != nil else {
                diagLog.warning("Settings URI: Unknown display UUID '\(uuid)'")
                return nil
            }
            return .specificDisplay(uuid: uuid)
        }

        switch key {
        case "useThawBar": return .activeDisplay
        case "alwaysShowHiddenItems": return .allNonThawBarDisplays
        case "thawBarLocation", "thawBarLayout", "gridColumns": return .allEnabledDisplays
        default: return nil
        }
    }

    private static func handlePerDisplaySet(key: String, value: String, displayUUID: String?) -> Bool {
        guard let scope = resolvePerDisplayScope(key: key, displayUUID: displayUUID) else {
            return false
        }

        switch key {
        case "useThawBar":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for useThawBar")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: scope)
            diagLog.info("Settings URI: Set useThawBar = \(boolValue) on \(scope.logDescription)")
            return true

        case "thawBarLocation":
            guard let location = ThawBarLocation.fromString(value) else {
                diagLog.warning("Settings URI: Invalid thawBarLocation value '\(value)'. Valid: dynamic, mousePointer, thawIcon, leftAligned, rightAligned (or 0-4)")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(location.rawValue), scope: scope)
            diagLog.info("Settings URI: Set thawBarLocation = \(location) on \(scope.logDescription)")
            return true

        case "alwaysShowHiddenItems":
            guard let boolValue = parseBool(value) else {
                diagLog.warning("Settings URI: Invalid boolean value '\(value)' for alwaysShowHiddenItems")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, value: boolValue, scope: scope)
            diagLog.info("Settings URI: Set alwaysShowHiddenItems = \(boolValue) on \(scope.logDescription)")
            return true

        case "thawBarLayout":
            guard let layout = ThawBarLayout.fromString(value) else {
                diagLog.warning("Settings URI: Invalid thawBarLayout value '\(value)'. Valid: horizontal, vertical, grid (or 0, 1, 2)")
                return false
            }
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(layout.rawValue), scope: scope)
            diagLog.info("Settings URI: Set thawBarLayout = \(layout) on \(scope.logDescription)")
            return true

        case "gridColumns":
            guard let intValue = Int(value) else {
                diagLog.warning("Settings URI: Invalid gridColumns value '\(value)'")
                return false
            }
            let clamped = Swift.max(2, Swift.min(intValue, 10))
            postPerDisplaySettingsDidChangeNotification(key: key, stringValue: String(clamped), scope: scope)
            diagLog.info("Settings URI: Set gridColumns = \(clamped) on \(scope.logDescription)")
            return true

        default:
            return false
        }
    }

    /// Handles "thaw://toggle?key=X" URLs.
    /// Returns true if setting was toggled successfully.
    static func handleToggle(key: String, sender: String?, displayUUID: String? = nil) -> Bool {
        let key = canonicalKey(key)
        diagLog.debug("Settings URI: toggle request - key=\(key), sender=\(sender ?? "unknown"), display=\(displayUUID ?? "none")")

        guard isValidSettingsKey(key) else {
            diagLog.warning("Settings URI: Invalid key '\(key)'")
            return false
        }

        if perDisplayKeys.contains(key) {
            return handlePerDisplayToggle(key: key, displayUUID: displayUUID)
        }

        guard let entry = keyTable[key], entry.isBoolean else {
            diagLog.warning("Settings URI: Cannot toggle non-boolean key '\(key)'. Use set action instead.")
            return false
        }

        guard entry.isWritable else {
            diagLog.warning("Settings URI: Key '\(key)' is read-only")
            return false
        }

        let currentValue = effectiveBool(for: entry)
        let newValue = !currentValue

        guard applyBooleanSetting(newValue, key: key, entry: entry) else { return false }

        diagLog.info("Settings URI: Toggled \(key) from \(currentValue) to \(newValue)")

        return true
    }

    /// Handles toggling a per-display configuration value.
    /// Currently only supports useThawBar and alwaysShowHiddenItems.
    private static func handlePerDisplayToggle(key: String, displayUUID: String?) -> Bool {
        guard key == "useThawBar" || key == "alwaysShowHiddenItems" else {
            diagLog.warning("Settings URI: Toggle not supported for '\(key)'")
            return false
        }

        guard let scope = resolvePerDisplayScope(key: key, displayUUID: displayUUID) else {
            return false
        }

        postPerDisplaySettingsDidChangeNotification(key: key, toggle: true, scope: scope)
        diagLog.info("Settings URI: Toggled \(key) on \(scope.logDescription)")
        return true
    }

    /// Posts a notification that a setting was changed externally via Settings URI.
    private static func postSettingsDidChangeNotification(key: String, value: Bool) {
        settingsChangeNotificationCenter.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: [
                "key": key,
                "value": value,
            ]
        )
    }

    private static func postSettingsDidChangeNotification(key: String, doubleValue: Double) {
        settingsChangeNotificationCenter.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: [
                "key": key,
                "doubleValue": doubleValue,
            ]
        )
    }

    private static func postSettingsDidChangeNotification(key: String, rawEnumValue: Int) {
        settingsChangeNotificationCenter.post(
            name: .settingsDidChangeViaURI,
            object: nil,
            userInfo: [
                "key": key,
                "rawEnumValue": rawEnumValue,
            ]
        )
    }

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
        case allNonThawBarDisplays
        case specificDisplay(uuid: String)

        /// String representation for notification userInfo
        var rawValue: String {
            switch self {
            case .activeDisplay: return "active"
            case .allEnabledDisplays: return "allEnabled"
            case .allNonThawBarDisplays: return "allNonThawBar"
            case let .specificDisplay(uuid): return "specific:\(uuid)"
            }
        }

        /// Human-readable scope for log messages.
        var logDescription: String {
            switch self {
            case .activeDisplay: return "active display"
            case .allEnabledDisplays: return "all enabled displays"
            case .allNonThawBarDisplays: return "all non-ThawBar displays"
            case let .specificDisplay(uuid): return "display \(uuid)"
            }
        }

        var specificUUID: String? {
            if case let .specificDisplay(uuid) = self {
                return uuid
            }
            return nil
        }
    }

    static func getWhitelist() -> [String] {
        return Defaults.stringArray(forKey: .settingsURIWhitelist) ?? []
    }

    static func isEnabled() -> Bool {
        return Defaults.bool(forKey: .settingsURIEnabled)
    }

    // MARK: - Getters (Read Operations)

    /// Handles "thaw://get?key=X&callback=Y" URLs.
    /// Returns settings values via callback URL or distributed notification.
    static func handleGet(
        key: String?,
        displayUUID: String?,
        callback: String?,
        broadcast: Bool,
        requestId: String?
    ) -> Bool {
        let responseId = requestId ?? UUID().uuidString

        guard callback != nil || broadcast else {
            diagLog.warning("Settings URI Get: No response mechanism provided - provide callback=<url> or broadcast=true")
            return false
        }

        let response: [String: Any] = if let singleKey = key {
            handleSingleKeyGet(key: singleKey, displayUUID: displayUUID, requestId: responseId)
        } else {
            createErrorResponse(requestId: responseId, error: "No key specified", details: "Provide key=<name>")
        }

        if let callbackURL = callback {
            // Send full settings data directly to the requesting app.
            return sendCallbackResponse(response: response, callback: callbackURL)
        } else if broadcast {
            // Broadcast acknowledgments only to avoid exposing settings data to other listeners.
            let ackResponse: [String: Any] = [
                "requestId": responseId,
                "status": "ack",
                "message": "Use callback URL to receive full settings data",
            ]
            return sendBroadcastResponse(response: ackResponse)
        }

        return false
    }

    private static func handleSingleKeyGet(key: String, displayUUID: String?, requestId: String) -> [String: Any] {
        let key = canonicalKey(key)
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
        if perDisplayKeys.contains(key) {
            guard let config = getDisplayConfiguration(forUUID: displayUUID) else {
                // Unknown display UUID
                return nil
            }

            switch key {
            case "useThawBar":
                return [
                    "value": config.useThawBar,
                    "type": "boolean",
                ]
            case "thawBarLocation":
                return [
                    "value": String(describing: config.thawBarLocation),
                    "rawValue": config.thawBarLocation.rawValue,
                    "type": "enum",
                    "validValues": ["dynamic": 0, "mousePointer": 1, "thawIcon": 2],
                ]
            case "alwaysShowHiddenItems":
                return [
                    "value": config.alwaysShowHiddenItems,
                    "type": "boolean",
                ]
            case "thawBarLayout":
                return [
                    "value": String(describing: config.thawBarLayout),
                    "rawValue": config.thawBarLayout.rawValue,
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

        guard let entry = keyTable[key] else { return nil }

        switch entry.kind {
        case .boolean:
            return [
                "value": effectiveBool(for: entry),
                "type": "boolean",
            ]

        case let .double(min, max):
            return [
                "value": effectiveDouble(for: entry),
                "type": "double",
                "range": ["min": min, "max": max],
            ]

        case .enumeration:
            let rawValue = (Defaults.object(forKey: entry.defaultsKey) as? Int) ?? 0

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

        case .integer, .string:
            return nil
        }
    }

    /// Gets all settings including per-display configurations.
    private static func getAllSettings(requestId: String) -> [String: Any] {
        var globalSettings: [String: [String: Any]] = [:]

        for key in supportedBooleanKeys where !perDisplayKeys.contains(key) {
            if let value = getSettingValue(key: key, displayUUID: nil) {
                globalSettings[key] = value
            }
        }

        for key in doubleKeys {
            if let value = getSettingValue(key: key, displayUUID: nil) {
                globalSettings[key] = value
            }
        }

        for key in enumKeys {
            if let value = getSettingValue(key: key, displayUUID: nil) {
                globalSettings[key] = value
            }
        }

        var displaysData: [String: [String: Any]] = [:]
        for screen in NSScreen.managedScreens {
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
    private static func getDisplayConfiguration(forUUID uuid: String?) -> DisplayThawBarConfiguration? {
        let configurations = Defaults.data(forKey: .displayThawBarConfigurations)
            .flatMap { try? JSONDecoder().decode([String: DisplayThawBarConfiguration].self, from: $0) }
            ?? [:]
        let globalConfiguration = Defaults.data(forKey: .globalDisplayConfiguration)
            .flatMap { try? JSONDecoder().decode(DisplayThawBarConfiguration.self, from: $0) }
            ?? .defaultConfiguration

        if let uuid {
            let connectedUUIDs = NSScreen.managedScreens.compactMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
            let isConnected = connectedUUIDs.contains(uuid)
            let hasPersisted = configurations[uuid] != nil

            guard isConnected || hasPersisted else {
                return nil
            }
            return configurations[uuid] ?? globalConfiguration
        }

        guard let activeDisplayID = Bridging.getActiveMenuBarDisplayID(),
              let activeUUID = Bridging.getDisplayUUIDString(for: activeDisplayID)
        else {
            return globalConfiguration
        }
        return configurations[activeUUID] ?? globalConfiguration
    }

    private static func getDisplayInfo(screen: NSScreen, uuid: String) -> [String: Any] {
        let config = getDisplayConfiguration(forUUID: uuid) ?? .defaultConfiguration

        let displayID = screen.displayID
        let isConnected = CGDisplayIsActive(displayID) != 0

        return [
            "name": screen.localizedName,
            "isConnected": isConnected,
            "isPrimary": screen == NSScreen.main,
            "hasNotch": screen.hasNotch,
            "resolution": "\(Int(screen.frame.width))x\(Int(screen.frame.height))",
            "useThawBar": config.useThawBar,
            "thawBarLocation": String(describing: config.thawBarLocation),
            "alwaysShowHiddenItems": config.alwaysShowHiddenItems,
            "thawBarLayout": String(describing: config.thawBarLayout),
            "gridColumns": config.gridColumns,
        ]
    }

    private static func getAllDisplays(requestId: String) -> [String: Any] {
        var displays: [[String: Any]] = []

        for screen in NSScreen.managedScreens {
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

    private static func getSpecificDisplay(uuid: String, requestId: String) -> [String: Any] {
        for screen in NSScreen.managedScreens {
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
        if let configs = Defaults.data(forKey: .displayThawBarConfigurations)
            .flatMap({ try? JSONDecoder().decode([String: DisplayThawBarConfiguration].self, from: $0) }),
            let config = configs[uuid]
        {
            return [
                "requestId": requestId,
                "status": "success",
                "data": [
                    "uuid": uuid,
                    "name": "Disconnected Display",
                    "isConnected": false,
                    "useThawBar": config.useThawBar,
                    "thawBarLocation": String(describing: config.thawBarLocation),
                    "alwaysShowHiddenItems": config.alwaysShowHiddenItems,
                    "thawBarLayout": String(describing: config.thawBarLayout),
                    "gridColumns": config.gridColumns,
                ],
            ]
        }

        return createErrorResponse(requestId: requestId, error: "Display not found", details: "UUID: \(uuid)")
    }

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
    static func sendCallbackResponse(response: [String: Any], callback: String) -> Bool {
        // Use URLComponents to compose callbacks safely.
        guard var components = URLComponents(string: callback) else {
            diagLog.error("Settings URI Get: Invalid callback URL format: \(callback)")
            return false
        }

        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            diagLog.error("Settings URI Get: Callback URL missing scheme: \(callback)")
            return false
        }

        if blockedCallbackSchemes.contains(scheme) || scheme.hasPrefix("x-apple-") {
            diagLog.error("Settings URI Get: Callback URL scheme not allowed: \(scheme)")
            return false
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            diagLog.error("Settings URI Get: Failed to encode callback response")
            return false
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "data", value: jsonString))
        components.queryItems = queryItems

        guard let callbackURL = components.url else {
            diagLog.error("Settings URI Get: Failed to compose callback URL")
            return false
        }

        let success = openCallbackURL(callbackURL)
        if success {
            diagLog.info("Settings URI Get: Sent callback via scheme: \(scheme)")
        } else {
            diagLog.error("Settings URI Get: Failed to open callback via scheme: \(scheme)")
        }
        return success
    }

    /// Sends response via distributed notification.
    static func sendBroadcastResponse(response: [String: Any]) -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            diagLog.error("Settings URI Get: Failed to encode broadcast response")
            return false
        }

        postBroadcastJSON(jsonString)

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
