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
        case configureLogging(filePath: String)
        case sourcePIDs([WindowInfo])
    }

    enum Response: Codable {
        case start
        case configureLogging
        case sourcePIDs([pid_t?])
    }
}
