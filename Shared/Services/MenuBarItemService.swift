//
//  MenuBarItemService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

enum MenuBarItemService {
    static let name = "com.stonerl.Thaw.MenuBarItemService"
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case configureLogging(filePath: String)
        case sourcePID(WindowInfo)
        case sourcePIDs([WindowInfo])
    }

    enum Response: Codable {
        case start
        case configureLogging
        case sourcePID(pid_t?)
        case sourcePIDs([pid_t?])
    }
}
