//
//  SettingsURIRoute.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Which thaw:// hosts need the Settings URI switch and an approved sender before they run.
nonisolated enum SettingsURIRoute {
    /// Hosts that read or change settings, drive another app's items, or report on them.
    static let authorizedHosts: Set<String> = [
        "set", "toggle", "get", "authorize", "reveal-item",
        "list-items", "activate-item", "list-profiles", "apply-profile", "get-appearance", "move-item",
        "proxy-press",
    ]

    static func requiresAuthorization(_ host: String) -> Bool {
        authorizedHosts.contains(host.lowercased())
    }
}
