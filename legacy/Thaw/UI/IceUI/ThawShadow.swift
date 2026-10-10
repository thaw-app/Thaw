//
//  ThawShadow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The depths Thaw's surfaces float at. One tier per kind of object, so the
/// same role never carries two different shadows.
enum ThawElevation {
    /// Cards and strips lying on a pane.
    case raised
    /// The one large object on a page, such as an onboarding mockup.
    case hero

    var opacity: CGFloat {
        switch self {
        case .raised: 0.18
        case .hero: 0.25
        }
    }

    var radius: CGFloat {
        switch self {
        case .raised: 10
        case .hero: 20
        }
    }

    var y: CGFloat {
        switch self {
        case .raised: 3
        case .hero: 8
        }
    }
}

/// Corner radii for Thaw's rounded surfaces.
enum ThawRadius {
    /// Cards, pills, and panels inside the settings window.
    static let card: CGFloat = 16
}

extension View {
    /// Drops the shared shadow for `elevation` under this view.
    func thawShadow(_ elevation: ThawElevation) -> some View {
        shadow(color: .black.opacity(elevation.opacity), radius: elevation.radius, y: elevation.y)
    }
}
