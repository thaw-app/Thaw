//
//  RequiredPermissionsNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The line under Continue while setup is blocked, naming the required permissions still missing.
enum RequiredPermissionsNotice {
    static func text(missing titles: [String]) -> String {
        guard !titles.isEmpty else { return "" }
        let names = titles.formatted(.list(type: .and))
        return titles.count == 1
            ? String(localized: "\(names) is required to continue.")
            : String(localized: "\(names) are required to continue.")
    }

    @MainActor
    static func text(for permissions: some PermissionsManaging) -> String {
        text(missing: permissions.allPermissions.filter { $0.isRequired && !$0.hasPermission }.map(\.title))
    }
}
