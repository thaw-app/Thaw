//
//  ThawShadow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The depths Thaw's surfaces float at.
///
/// A small closed set, not one shadow per view: the same role carrying
/// slightly different shadows reads as several kinds of object. Nothing
/// should reach for a bare .shadow, whose default is black at full strength,
/// a different physics from every tokenised drop in the app.
public enum ThawElevation {
    /// A small control lying on a pane (a gradient track, a swatch): just
    /// enough edge to lift it off the surface it sits on.
    case control
    /// Cards and strips that sit on a pane: the layout bar, the folded bar,
    /// the notch descender.
    case raised
    /// Panels over arbitrary desktops; what ThawGlass.panel uses.
    case floating
    /// The one large object on a page (the onboarding mockups), lifted
    /// further than anything that is merely a control.
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
    ///
    /// isVisible lets a surface fade its shadow in with itself (the notch
    /// descender while it reveals) without leaving the token for a literal.
    func thawShadow(_ elevation: ThawElevation, isVisible: Bool = true) -> some View {
        shadow(
            color: .black.opacity(isVisible ? elevation.opacity : 0),
            radius: elevation.radius,
            y: elevation.y
        )
    }
}
