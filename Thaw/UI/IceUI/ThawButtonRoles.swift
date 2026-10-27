//
//  ThawButtonRoles.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// Buttons take one of three roles below. Menus and views that draw their own controls
// keep their own styles.

/// The main action of a sheet, step or notice.
struct ThawPrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
        }
        .thawGlassButtonStyle(prominent: true)
    }
}

/// Any other action in a settings pane.
struct ThawSecondaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
                .padding(.horizontal, 16)
        }
        .thawGlassButtonStyle()
        .buttonBorderShape(.roundedRectangle(radius: ThawRadius.card))
    }
}

extension PrimitiveButtonStyle where Self == ThawPrimaryButtonStyle {
    static var thawPrimary: ThawPrimaryButtonStyle {
        .init()
    }
}

extension PrimitiveButtonStyle where Self == ThawSecondaryButtonStyle {
    static var thawSecondary: ThawSecondaryButtonStyle {
        .init()
    }
}

extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    /// An icon or text button inside a row. Give it a help tag and, for an icon, an
    /// accessibility label.
    static var thawInline: BorderlessButtonStyle {
        .borderless
    }
}
