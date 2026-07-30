//
//  AutomationSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import SwiftUI

/// Settings model for managing Settings URI automation and whitelist.
@MainActor
final class AutomationSettings: ObservableObject {
    // MARK: - Published Properties

    @Published var isSettingsURIEnabled: Bool {
        didSet {
            Defaults.set(isSettingsURIEnabled, forKey: .settingsURIEnabled)
        }
    }

    @Published var whitelistedApps: [WhitelistedApp] = []

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

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        self.isSettingsURIEnabled = Defaults.bool(forKey: .settingsURIEnabled)
        refreshWhitelist()

        // Listen for whitelist changes from SettingsURIHandler
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
            // Sort by display name, with unknown apps at the bottom
            let lhsName = lhs.appName?.lowercased() ?? lhs.bundleId.lowercased()
            let rhsName = rhs.appName?.lowercased() ?? rhs.bundleId.lowercased()
            return lhsName < rhsName
        }
    }

    /// Adds a bundle ID to the whitelist.
    func addToWhitelist(bundleId: String) {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        SettingsURIHandler.addToWhitelist(bundleId: trimmed)
        refreshWhitelist()
    }

    /// Removes a bundle ID from the whitelist.
    func removeFromWhitelist(bundleId: String) {
        SettingsURIHandler.removeFromWhitelist(bundleId: bundleId)
        refreshWhitelist()
    }

    /// Removes a whitelisted app at the specified index.
    func removeWhitelistedApp(at indexSet: IndexSet) {
        let appsToRemove = indexSet.compactMap { index -> String? in
            guard index < whitelistedApps.count else { return nil }
            return whitelistedApps[index].bundleId
        }

        for bundleId in appsToRemove {
            SettingsURIHandler.removeFromWhitelist(bundleId: bundleId)
        }

        refreshWhitelist()
    }

    /// Attempts to add the currently running app to the whitelist (for testing).
    func addCurrentApp() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        addToWhitelist(bundleId: bundleId)
    }

    /// Validates a bundle ID format (basic check).
    static func isValidBundleId(_ bundleId: String) -> Bool {
        // Basic validation: should contain at least one dot, no spaces
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(".") && !trimmed.contains(" ") && !trimmed.isEmpty
    }
}
