//
//  MenuBarPrivateGlass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawUI

/// The private glass finishes on NSGlassEffectView, set only when the setter
/// exists and the value is one probed safe, then read back.
enum MenuBarPrivateGlass {
    static let variantKey = "_variant"

    private static let diagLog = DiagLog(category: "PrivateGlass")

    /// The variants that draw something of their own on macOS 27.2; from 22 up they all
    /// draw like 0. Some private glass settings abort AppKit outside their range, so nothing else is set.
    nonisolated static let safeVariants: ClosedRange<Int> = 0 ... 21

    /// Sets view to variant, or back to the default when variant is nil. Returns
    /// false when the finish couldn't be set, and the view keeps its public style.
    @discardableResult
    static func apply(_ variant: Int?, to view: NSGlassEffectView) -> Bool {
        guard view.responds(to: NSSelectorFromString("set\(variantKey):")) else {
            if variant != nil {
                diagLog.info("NSGlassEffectView has no \(variantKey) setter")
            }
            return variant == nil
        }
        let target = variant ?? 0
        guard safeVariants.contains(target) else {
            // An earlier finish is taken off too, so false always leaves the public style.
            if read(view) != 0 {
                view.setValue(0, forKey: variantKey)
            }
            return false
        }
        guard read(view) != target else { return true }
        view.setValue(target, forKey: variantKey)
        guard read(view) == target else {
            diagLog.info("\(variantKey) \(target) didn't stick; using the public style")
            view.setValue(0, forKey: variantKey)
            return false
        }
        return true
    }

    private static func read(_ view: NSGlassEffectView) -> Int? {
        (view.value(forKey: variantKey) as? NSNumber)?.intValue
    }
}
