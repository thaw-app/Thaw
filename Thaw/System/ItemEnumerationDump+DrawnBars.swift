//
//  ItemEnumerationDump+DrawnBars.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ThawAXCore

extension ItemEnumerationDump {
    /// One display's bar as MenuBarAgent draws it, to compare with the frames the apps report. A hidden
    /// item put back on the bar can report a seat beside the one it is drawn in.
    struct DrawnBar: Codable, Equatable {
        /// The bar window's frame, which says which display it is on. Nil when it could not be read.
        let frameX: Double?
        let frameY: Double?
        let frameWidth: Double?
        let frameHeight: Double?
        let items: [DrawnItem]
    }

    /// One item on a drawn bar, with the app that owns it. Apple's own items belong to MenuBarAgent.
    struct DrawnItem: Codable, Equatable {
        let bundleIdentifier: String?
        let processIdentifier: Int
        let frameX: Double
        let frameY: Double
        let frameWidth: Double
        let frameHeight: Double
    }

    /// The bars as the report records them, left to right on each.
    static func drawnBars(from bars: [MenuBarAgentWindow.Bar], bundleIdentifier: (pid_t) -> String?) -> [DrawnBar] {
        bars.map { bar in
            DrawnBar(
                frameX: bar.frame.map { Double($0.minX) },
                frameY: bar.frame.map { Double($0.minY) },
                frameWidth: bar.frame.map { Double($0.width) },
                frameHeight: bar.frame.map { Double($0.height) },
                items: bar.entries.sorted { $0.frame.minX < $1.frame.minX }.map { entry in
                    DrawnItem(
                        bundleIdentifier: bundleIdentifier(entry.ownerPID),
                        processIdentifier: Int(entry.ownerPID),
                        frameX: entry.frame.minX,
                        frameY: entry.frame.minY,
                        frameWidth: entry.frame.width,
                        frameHeight: entry.frame.height
                    )
                }
            )
        }
    }

    /// Reads every bar MenuBarAgent draws now. Nil when the agent could not be read.
    static func readDrawnBars() -> [DrawnBar]? {
        AXPrimitives.menuBarAgentBars().map { bars in
            drawnBars(from: bars) { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        }
    }
}
