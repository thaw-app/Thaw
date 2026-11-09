//
//  ThawHaptics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// Force Touch trackpad taps. Macs without one, and people who turned feedback off, feel nothing.
@MainActor
enum ThawHaptics {
    /// A light tap: a drag reaching another section, a slider reaching its default.
    static func snap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A firmer tap: a drop landing.
    static func land() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Passes a drop's result through, tapping when it landed.
    static func landing(_ landed: Bool) -> Bool {
        if landed {
            land()
        }
        return landed
    }
}

/// The section a drag was last over, so it taps once on entering another and not on every update.
nonisolated struct SectionCrossing: Equatable {
    private(set) var current: MenuBarSectionName?

    init(startingIn section: MenuBarSectionName? = nil) {
        current = section
    }

    /// Whether entering section crosses out of the one the drag was over.
    mutating func enter(_ section: MenuBarSectionName) -> Bool {
        defer { current = section }
        return current != nil && current != section
    }
}

/// One crossing for every Layout drag, from the bars or the Layout window's list.
@MainActor
enum LayoutDragHaptics {
    private static var crossing = SectionCrossing()

    static func begin(in section: MenuBarSectionName?) {
        crossing = SectionCrossing(startingIn: section)
    }

    static func enter(_ section: MenuBarSectionName) {
        if crossing.enter(section) {
            ThawHaptics.snap()
        }
    }
}

nonisolated enum SliderDetent {
    /// Whether moving from old to new lands on detent, within tolerance.
    static func reached(_ detent: Double, from old: Double, to new: Double, tolerance: Double) -> Bool {
        abs(new - detent) <= tolerance && abs(old - detent) > tolerance
    }
}

extension View {
    /// Rolls a count's digits when it changes; with Reduce Motion it changes at once.
    func rollingNumber(_ value: Int) -> some View {
        contentTransition(.numericText(value: Double(value)))
            .thawAnimation(ThawMotion.quick, value: value)
    }

    /// Taps when value lands on detent, such as a slider reaching its default.
    func snapHaptic(_ value: Double, at detent: Double, tolerance: Double = 0.0001) -> some View {
        onChange(of: value) { old, new in
            if SliderDetent.reached(detent, from: old, to: new, tolerance: tolerance) {
                ThawHaptics.snap()
            }
        }
    }
}
