//
//  ItemEnumerationDump+HelperFrame.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import ThawAXCore

extension ItemEnumerationDump {
    /// The frame the AX helper reads for an item the in-process walk found no AXFrame for, or nil when it has one.
    static func helperFrame(of child: AXElement, appFrame: CGRect?) -> HelperFrame? {
        appFrame == nil ? AXPrimitives.frame(of: child.raw).map(HelperFrame.init) : nil
    }

    static func helperFramedCount(_ apps: [DumpedApp]) -> Int {
        apps.reduce(0) { total, app in total + app.items.count { $0.helperFrame != nil } }
    }

    /// A frame read through AXPosition and AXSize, as the AX helper reads an item without AXFrame.
    struct HelperFrame: Codable, Equatable {
        let frameX: Double
        let frameY: Double
        let frameWidth: Double
        let frameHeight: Double

        init(_ frame: CGRect) {
            frameX = frame.minX
            frameY = frame.minY
            frameWidth = frame.width
            frameHeight = frame.height
        }
    }
}
