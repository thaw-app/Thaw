//
//  MenuBarDisplayCache.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Cached menu geometry and the generation that an outstanding read belongs to.
nonisolated struct MenuBarDisplayCache {
    private(set) var menuFrames = [CGDirectDisplayID: CGRect]()
    private(set) var menuBarHeights = [CGDirectDisplayID: CGFloat]()
    private(set) var generation: UInt64 = 0
    private var menuFramePID: pid_t?

    mutating func applicationDidChange(to pid: pid_t?) {
        guard pid != menuFramePID else { return }
        menuFrames.removeAll()
        menuFramePID = pid
        generation &+= 1
    }

    mutating func geometryDidChange() {
        menuFrames.removeAll()
        menuBarHeights.removeAll()
        generation &+= 1
    }

    mutating func removeDisconnectedDisplays(keeping ids: Set<CGDirectDisplayID>) {
        menuFrames = menuFrames.filter { ids.contains($0.key) }
        menuBarHeights = menuBarHeights.filter { ids.contains($0.key) }
    }

    mutating func storeMenuFrame(_ frame: CGRect, for display: CGDirectDisplayID, generation: UInt64) {
        guard generation == self.generation else { return }
        menuFrames[display] = frame
    }

    @discardableResult
    mutating func storeHeight(_ height: CGFloat, for display: CGDirectDisplayID, generation: UInt64) -> Bool {
        guard generation == self.generation else { return false }
        menuBarHeights[display] = height
        return true
    }
}
