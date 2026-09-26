//
//  MenuBarItemService.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated enum MenuBarItemService {
    static let name = "com.stonerl.Thaw.MenuBarItemService"
}

nonisolated extension MenuBarItemService {
    enum Request: Codable {
        case start
        /// Points the service's diagnostic logger at `filePath`, or turns file
        /// logging off when `nil`. Sent at startup, on rotation, and when the
        /// user toggles logging. `rotationPolicy` makes the service prune by the app's rules.
        case configureLogging(filePath: String?, rotationPolicy: DiagnosticLogger.RotationPolicy?)
        case sourcePIDs([WindowInfo])
    }

    enum Response: Codable {
        case start
        case configureLogging
        case sourcePIDs([pid_t?])
    }
}
