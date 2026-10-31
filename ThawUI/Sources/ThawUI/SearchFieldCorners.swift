//
//  SearchFieldCorners.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import SwiftUI

/// How round the launcher's search field is, as a slider's value: 0 is square, the middle has
/// the corners the rest of the panel has, and 1 is fully round. Stored as the plain number.
public nonisolated struct SearchFieldCorners: Codable, Hashable, Sendable {
    public static let range: ClosedRange<Double> = 0 ... 1

    public static let square = SearchFieldCorners(roundness: 0)
    public static let rounded = SearchFieldCorners(roundness: 0.5)
    public static let capsule = SearchFieldCorners(roundness: 1)

    public var roundness: Double {
        didSet { roundness = Self.clamped(roundness) }
    }

    public init(roundness: Double) {
        self.roundness = Self.clamped(roundness)
    }

    public init(_ shape: SearchFieldShape) {
        switch shape {
        case .square: self = .square
        case .rounded: self = .rounded
        case .capsule: self = .capsule
        }
    }

    public init(from decoder: any Decoder) throws {
        try self.init(roundness: decoder.singleValueContainer().decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(roundness)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// The shape an older Floe can show for this: each takes the part of the slider closest to it.
    public var nearestShape: SearchFieldShape {
        switch roundness {
        case ..<0.25: .square
        case ..<0.75: .rounded
        default: .capsule
        }
    }

    /// Up from square to the middle radius over the first half of the slider, then on to the full one over the second.
    private func radius(middle: CGFloat, full: CGFloat) -> CGFloat {
        let position = CGFloat(roundness)
        guard position > 0.5 else { return middle * position * 2 }
        let rest = (position - 0.5) * 2
        return middle * (1 - rest) + full * rest
    }

    /// The field inside the panel.
    public func cornerRadius(height: CGFloat) -> CGFloat {
        radius(middle: ThawRadius.control, full: height / 2)
    }

    /// Standing alone the field is a piece of the panel, so the middle takes the panel's corner and not a control's.
    public func fieldPieceRadius(height: CGFloat) -> CGFloat {
        radius(middle: ThawRadius.panel, full: height / 2)
    }

    /// The piece under a separate field, and a panel in one piece beside it: past the middle it stays the panel's.
    public var panelPieceRadius: CGFloat {
        radius(middle: ThawRadius.panel, full: ThawRadius.panel)
    }

    /// A continuous corner close to half the height leaves a nick, which starts near 0.87 of the way there.
    /// The whole capsule end of the slider is circular, which is short of that and past every middle corner in use.
    public var pieceCornerStyle: RoundedCornerStyle {
        nearestShape == .capsule ? .circular : .continuous
    }

    public var outline: SearchFieldOutline {
        SearchFieldOutline(corners: self)
    }
}
