//
//  LayoutSelectionHighlight.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// How a selected item looks and reads in the Layout pane.
@MainActor
enum LayoutSelectionHighlight {
    /// The drawing values, apart so they can be checked without a view.
    nonisolated struct Style: Equatable {
        static let cornerRadius: CGFloat = 5

        let fillAlpha: CGFloat
        let strokeAlpha: CGFloat
        let lineWidth: CGFloat

        /// Increase Contrast makes both the wash and the outline stronger.
        init(increasedContrast: Bool) {
            fillAlpha = increasedContrast ? 0.4 : 0.25
            strokeAlpha = increasedContrast ? 1 : 0.85
            lineWidth = increasedContrast ? 2 : 1.5
        }
    }

    /// An accent wash and outline on the view's layer, resolved for its light or dark appearance.
    static func apply(to view: NSView, isSelected: Bool) {
        guard isSelected else {
            guard let layer = view.layer, layer.borderWidth > 0 || layer.backgroundColor != nil else { return }
            layer.backgroundColor = nil
            layer.borderWidth = 0
            return
        }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let style = Style(increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(style.fillAlpha).cgColor
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(style.strokeAlpha).cgColor
        }
        layer.borderWidth = style.lineWidth
        layer.cornerRadius = Style.cornerRadius
    }

    /// The tile's value for VoiceOver: its section, and whether it is selected.
    nonisolated static func accessibilityValue(section: MenuBarSection.Name, isSelected: Bool) -> String {
        guard isSelected else { return section.localizedName }
        return String(
            localized: "\(section.localizedName), selected",
            comment: "VoiceOver value of a selected Layout item: its section name, then that it is selected"
        )
    }
}
