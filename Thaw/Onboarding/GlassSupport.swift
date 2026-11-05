//
//  GlassSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// A plain monochrome SF Symbol, drawn like a real status item so the mockup
/// bars read as a menu bar rather than a row of buttons.
struct GlassIconBubble: View {
    let symbol: String
    var size: CGFloat = 30
    var tint: Color = .primary
    /// Ignored; kept so existing call sites still compile.
    var showBackground: Bool = false

    var body: some View {
        // Resizable, not font-sized: a font symbol centers its line box, so
        // the glyph sits high. Scaling its own bounds centers the ink.
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .foregroundStyle(tint.opacity(0.75))
            .frame(width: size * 0.46, height: size * 0.46)
            .frame(width: size, height: size)
    }
}
