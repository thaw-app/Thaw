//
//  MenuBarBackdrop+StripKey.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

extension MenuBarBackdrop {
    /// What a strip was composited from. Includes each window's bounds, in
    /// front-to-back order, so a window that moves or comes to the front invalidates the strip.
    nonisolated static func stripKey(rect: CGRect, windows: [(id: CGWindowID, bounds: CGRect)]) -> String {
        let parts = windows.map { "\($0.id)@\($0.bounds)" }
        return "\(rect)|\(parts.joined(separator: ","))"
    }
}
