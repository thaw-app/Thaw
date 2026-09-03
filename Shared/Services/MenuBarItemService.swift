//
//  MenuBarItemService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated enum MenuBarItemService {
    static let name = "com.stonerl.Thaw.MenuBarItemService"
}

nonisolated extension MenuBarItemService {
    enum Request: Codable {
        case start
        /// Points the service's diagnostic logger at `filePath`, or turns its
        /// file logging off when `nil`. Sent at startup, again on every log
        /// rotation, and whenever the user toggles diagnostic logging.
        ///
        /// `rotationPolicy` carries the app's retention settings, so the
        /// service prunes the shared log directory by the same rules rather
        /// than by its own defaults.
        case configureLogging(filePath: String?, rotationPolicy: DiagnosticLogger.RotationPolicy?)
        case sourcePIDs([WindowInfo])
    }

    enum Response: Codable {
        case start
        case configureLogging
        case sourcePIDs([pid_t?])
    }
}
