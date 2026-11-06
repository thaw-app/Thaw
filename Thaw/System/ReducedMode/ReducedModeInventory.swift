//
//  ReducedModeInventory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// An app the reduced mode can hide.
struct ReducedModeApp: Equatable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// Which apps the reduced mode offers to hide. It cannot read the menu bar, so it works from
/// the running apps, narrowed by the position table when that can be read.
enum ReducedModeInventory {
    struct Running {
        let bundleID: String?
        let name: String?
        let isBackgroundOnly: Bool
    }

    /// - Parameters:
    ///   - tableKeys: The position table's keys, or nil when the table could not be read.
    ///     Without it every running app is offered, including ones with no menu bar item.
    static func candidates(
        running: [Running],
        tableKeys: [String]?,
        isOwn: (String) -> Bool
    ) -> [ReducedModeApp] {
        var names = [String: String]()
        for app in running {
            guard let bundleID = app.bundleID, !app.isBackgroundOnly,
                  !isOwn(bundleID), !bundleID.hasPrefix("com.apple.")
            else { continue }
            if let tableKeys, !tableKeys.contains(where: { $0.hasPrefix("status:\(bundleID)::") }) {
                continue
            }
            if names[bundleID] == nil || names[bundleID] == bundleID {
                names[bundleID] = app.name ?? bundleID
            }
        }
        return names
            .map { ReducedModeApp(bundleID: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
