//
//  AutomationSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import Observation
import SwiftUI

/// Settings model for managing Settings URI automation and whitelist.
@MainActor
@Observable
final class AutomationSettings {
    // MARK: - Observable Properties

    var isSettingsURIEnabled: Bool {
        didSet {
            Defaults.set(isSettingsURIEnabled, forKey: .settingsURIEnabled)
        }
    }

    var whitelistedApps: [WhitelistedApp] = []

    // MARK: - Types

    /// Represents a whitelisted application.
    struct WhitelistedApp: Identifiable, Equatable {
        let bundleId: String
        let appName: String?
        let icon: NSImage?

        var id: String {
            bundleId
        }

        var displayName: String {
            appName ?? bundleId
        }

        static func == (lhs: WhitelistedApp, rhs: WhitelistedApp) -> Bool {
            lhs.bundleId == rhs.bundleId
        }
    }

    // MARK: - Private Properties

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        self.isSettingsURIEnabled = Defaults.bool(forKey: .settingsURIEnabled)
        refreshWhitelist()

        NotificationCenter.default
            .publisher(for: .settingsURIWhitelistDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWhitelist()
            }
            .store(in: &cancellables)
    }

    // MARK: - Whitelist Management

    /// Refreshes the whitelist from UserDefaults and updates app info.
    func refreshWhitelist() {
        let bundleIds = SettingsURIHandler.getWhitelist()

        whitelistedApps = bundleIds.map { bundleId in
            WhitelistedApp(
                bundleId: bundleId,
                appName: SettingsURIHandler.getAppName(for: bundleId),
                icon: SettingsURIHandler.getAppIcon(for: bundleId)
            )
        }.sorted { lhs, rhs in
            // Unknown app names fall back to bundle IDs for sorting.
            let lhsName = lhs.appName?.lowercased() ?? lhs.bundleId.lowercased()
            let rhsName = rhs.appName?.lowercased() ?? rhs.bundleId.lowercased()
            return lhsName < rhsName
        }
    }

    /// Allows the app at url, pinned to the team or code hash in its own signature, the way an approval
    /// from the prompt is. Returns false when its signature doesn't name bundleID, since no request
    /// could then match the grant.
    @discardableResult
    func addToWhitelist(
        appAt url: URL,
        bundleID: String,
        identify: (URL) -> SettingsURISender? = SettingsURISender.identify(appAt:)
    ) -> Bool {
        guard let identity = identify(url), identity.bundleIdentifier == bundleID,
              identity.teamIdentifier != nil || identity.codeHash != nil
        else {
            return false
        }
        SettingsURIHandler.addToWhitelist(
            bundleId: bundleID,
            teamIdentifier: identity.teamIdentifier,
            codeHash: identity.teamIdentifier == nil ? identity.codeHash : nil
        )
        refreshWhitelist()
        return true
    }

    func removeFromWhitelist(bundleId: String) {
        SettingsURIHandler.removeFromWhitelist(bundleId: bundleId)
        refreshWhitelist()
    }

    /// Attempts to add the currently running app to the whitelist (for testing).
    func addCurrentApp() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        addToWhitelist(appAt: Bundle.main.bundleURL, bundleID: bundleId)
    }

    /// What picking an app in the allowed-apps chooser does.
    nonisolated enum AllowedAppChoice: Equatable {
        case add(String)
        case alreadyAllowed(String)
        case noBundleID
    }

    nonisolated static func choice(forBundleID bundleID: String?, allowed: [String]) -> AllowedAppChoice {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return .noBundleID }
        return allowed.contains(trimmed) ? .alreadyAllowed(trimmed) : .add(trimmed)
    }
}
