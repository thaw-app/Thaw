//
//  ThawShadow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The depths surfaces float at. Use these over a bare .shadow, whose default is black at full strength.
public enum ThawElevation {
    /// A small control lying on a pane, such as a gradient track or a swatch.
    case control
    /// Cards and strips that sit on a pane.
    case raised
    /// Panels over arbitrary desktops; what ThawGlass.panel uses.
    case floating
    /// The one large object on a page, such as an onboarding mockup.
    case hero

    var opacity: CGFloat {
        switch self {
        case .control: 0.18
        case .raised: 0.18
        case .floating: 0.18
        case .hero: 0.25
        }
    }

    var radius: CGFloat {
        switch self {
        case .control: 3
        case .raised: 10
        case .floating: 12
        case .hero: 20
        }
    }

    var y: CGFloat {
        switch self {
        case .control: 1
        case .raised: 3
        case .floating: 4
        case .hero: 8
        }
    }
}

public extension View {
    /// Drops the shared shadow for elevation under this view.
    /// isVisible lets a surface fade its shadow in with itself without leaving the token for a literal.
    func thawShadow(_ elevation: ThawElevation, isVisible: Bool = true) -> some View {
        shadow(
            color: .black.opacity(isVisible ? elevation.opacity : 0),
            radius: elevation.radius,
            y: elevation.y
        )
    }
}
