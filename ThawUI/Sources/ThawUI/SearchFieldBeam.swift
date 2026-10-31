//
//  SearchFieldBeam.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// The light inside the search field's border, in one of a few sets of colours. The technique is border-beam's, by
/// Jakub Antalik: soft colour fixed on each side, shown through a wide turning window, all of it inside the field.
public nonisolated enum SearchFieldBeam: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case colorful
    case mono
    case ocean
    case sunset

    /// A soft patch of colour on the field's edge.
    public struct Blob: Equatable {
        public var color: Color
        /// Where its middle is, as a part of the field's width and height: an edge is 0 or 1.
        public var center: UnitPoint
        /// How far it reaches across and down, in points.
        public var radii: CGSize
    }

    public var id: String {
        rawValue
    }

    /// The same places for every set: along the top, down the left, along the bottom and down the right.
    private static let places: [(center: UnitPoint, radii: CGSize)] = [
        (UnitPoint(x: 0.3, y: 0), CGSize(width: 80, height: 30)),
        (UnitPoint(x: 0.08, y: 0.05), CGSize(width: 50, height: 28)),
        (UnitPoint(x: 0, y: 0.7), CGSize(width: 34, height: 56)),
        (UnitPoint(x: 0, y: 0.7), CGSize(width: 18, height: 30)),
        (UnitPoint(x: 0.72, y: 1), CGSize(width: 160, height: 28)),
        (UnitPoint(x: 0.5, y: 1), CGSize(width: 80, height: 24)),
        (UnitPoint(x: 0.93, y: 0), CGSize(width: 70, height: 30)),
        (UnitPoint(x: 1, y: 0.3), CGSize(width: 26, height: 40)),
        (UnitPoint(x: 1, y: 0.3), CGSize(width: 50, height: 44)),
    ]

    /// One colour for each place, in the same order.
    private var palette: [Color] {
        switch self {
        case .off: []
        case .colorful: [rgb(255, 60, 110), rgb(50, 140, 255), rgb(60, 200, 90), rgb(30, 190, 175), rgb(110, 75, 255), rgb(50, 140, 255), rgb(255, 125, 45), rgb(240, 55, 180), rgb(180, 45, 240)]
        case .mono: [175, 140, 160, 130, 170, 150, 190, 145, 165].map { rgb($0, $0, $0) }
        case .ocean: [rgb(100, 85, 225), rgb(60, 120, 255), rgb(80, 105, 205), rgb(50, 145, 225), rgb(120, 85, 255), rgb(70, 130, 255), rgb(140, 105, 240), rgb(90, 115, 230), rgb(130, 75, 255)]
        case .sunset: [rgb(255, 85, 55), rgb(255, 160, 45), rgb(255, 125, 65), rgb(255, 200, 55), rgb(255, 105, 85), rgb(255, 145, 50), rgb(250, 70, 120), rgb(255, 180, 60), rgb(235, 60, 95)]
        }
    }

    /// The set's colours round the field, the first again at the end so they meet without a seam.
    public var ring: [Color] {
        palette.first.map { palette + [$0] } ?? []
    }

    public var blobs: [Blob] {
        zip(Self.places, palette).map { Blob(color: $1, center: $0.center, radii: $0.radii) }
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
