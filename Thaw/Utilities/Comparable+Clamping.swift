//
//  Comparable+Clamping.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension Comparable {
    /// Returns this value pulled into the given range.
    ///
    /// - Parameter range: The range to pull the value into; its bounds act as
    ///   the lowest and highest values that may be returned.
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound {
            return range.lowerBound
        }
        if self > range.upperBound {
            return range.upperBound
        }
        return self
    }

    /// Returns this value pulled into the range bounded by the given values.
    ///
    /// - Parameters:
    ///   - min: The lowest value that may be returned.
    ///   - max: The highest value that may be returned.
    ///
    /// - Precondition: min <= max
    nonisolated func clamped(min: Self, max: Self) -> Self {
        clamped(to: min ... max)
    }
}
