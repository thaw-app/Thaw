//
//  MenuBarItemService.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel

nonisolated enum MenuBarItemService {
    static let name = "com.stonerl.Thaw.MenuBarItemService"
}

extension MenuBarItemService {
    nonisolated enum Request: Codable {
        case start
        case configureLogging(filePath: String)
        // MARK: macOS <=26 — SkyLight source-PID resolution
        case sourcePID(WindowInfo)
        case sourcePIDs([WindowInfo])
        // MARK: macOS 27 — out-of-process Accessibility reads
        /// Reads the menu-bar item snapshots owned by the given process
        /// identifiers, so a wedged owner blocks the helper instead of Thaw's
        /// main actor.
        case menuBarItemSnapshots([pid_t])
    }

    nonisolated enum Response: Codable {
        case start
        case configureLogging
        case sourcePID(pid_t?)
        case sourcePIDs([pid_t?])
        case menuBarItemSnapshots([MenuBarItemAXSnapshot])
    }

    /// A read-only snapshot of one menu-bar item's Accessibility attributes,
    /// gathered out of process (macOS 27). Plain values only — no live element
    /// handles cross the XPC boundary.
    nonisolated struct MenuBarItemAXSnapshot: Codable, Sendable {
        let ownerPID: pid_t
        let identifier: String?
        let role: String?
        let axDescription: String?
        let title: String?
        let frame: CGRect?
    }
}
