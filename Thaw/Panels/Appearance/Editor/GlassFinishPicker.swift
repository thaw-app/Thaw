//
//  GlassFinishPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The glass Effect menu, with plain glass under Glass and the other finishes
/// under Liquid Glass, followed by the Tint switch while plain glass is chosen.
/// Only Edge, Sheer, Dim and Invert are Alpha, so the badge shows beside the
/// menu while one of them is chosen rather than heading the whole section.
struct GlassFinishPicker: View {
    @Binding var style: MenuBarGlassStyle
    @Binding var isTinted: Bool

    var body: some View {
        LabeledContent("Effect") {
            HStack(spacing: ThawSpacing.compact) {
                ThawPicker("Glass Style", selection: $style) {
                    Section("Glass") {
                        ForEach(MenuBarGlassStyle.glassFinishes, id: \.self) { style in
                            Text(style.localized).tag(style)
                        }
                    }
                    Section("Liquid Glass") {
                        ForEach(MenuBarGlassStyle.liquidGlassFinishes, id: \.self) { style in
                            Text(style.localized).tag(style)
                        }
                    }
                }
                .labelsHidden()
                if style.isExperimental {
                    ThawBadge.alpha
                }
            }
        }
        // Dynamic Glass always takes a tint and the Alpha finishes never do.
        if style == .regular {
            Toggle("Tint", isOn: $isTinted)
                .help("Makes the glass lighter so a tint color can show through.")
        }
    }
}
