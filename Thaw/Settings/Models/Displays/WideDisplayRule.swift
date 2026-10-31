//
//  WideDisplayRule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Observation

/// Shows every hidden item while the menu bar is active on a display at
/// least a chosen width, as if "Always show hidden items" were on for it.
@MainActor
@Observable
final class WideDisplayRule {
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            Defaults.set(isEnabled, forKey: .showEveryItemOnWideDisplays)
        }
    }

    /// The narrowest display, in points, that shows every item.
    var minimumWidth: Double {
        didSet {
            guard oldValue != minimumWidth else { return }
            Defaults.set(minimumWidth, forKey: .wideDisplayMinimumWidth)
        }
    }

    /// The widths offered in Settings, in points.
    static let widthRange: ClosedRange<Double> = 1280 ... 5120

    @ObservationIgnored private let screenWidth: (CGDirectDisplayID) -> CGFloat?

    init(screenWidth: @escaping (CGDirectDisplayID) -> CGFloat? = { NSScreen.screen(for: $0)?.frame.width }) {
        self.screenWidth = screenWidth
        isEnabled = Defaults.bool(forKey: .showEveryItemOnWideDisplays)
        minimumWidth = Defaults.double(forKey: .wideDisplayMinimumWidth)
    }

    func showsEveryItem(on displayID: CGDirectDisplayID) -> Bool {
        Self.applies(isEnabled: isEnabled, screenWidth: screenWidth(displayID), minimumWidth: minimumWidth)
    }

    static nonisolated func applies(isEnabled: Bool, screenWidth: CGFloat?, minimumWidth: Double) -> Bool {
        guard isEnabled, let screenWidth else { return false }
        return Double(screenWidth) >= minimumWidth
    }
}
