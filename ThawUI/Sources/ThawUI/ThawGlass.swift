//
//  ThawGlass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Glass tiers

/// Shared Liquid Glass tiers; use these instead of a bare .glassEffect.
/// Clear glass is wrong for .panel: a grey film over the desktop that washes out in light mode.
public enum ThawGlass {
    /// Containers that float over arbitrary desktops. Regular glass.
    case panel
    /// A .panel with no edge, even under Reduce Transparency or Increase Contrast, for glass
    /// that already draws its rim; a hairline would read as a broken dark border.
    case borderlessPanel
    /// Elements inside a panel: fields, pickers, key caps, slider tracks. Interactive glass.
    case control
    /// A control that takes keyboard focus. Same glass as .control, with a tinted border while focused.
    case field(isFocused: Bool)
    /// Emphasis surfaces such as warnings: clear glass washed with the
    /// accent. Thin glass is correct only here, because it carries its own tint.
    case accent(Color)
    /// The accent wash, graded: .selected is a flat neutral-and-accent fill for rows in a list
    /// that already floats, .hover the lighter, strokeless step.
    case selection(Color, strength: SelectionStrength)

    public enum SelectionStrength {
        case hover
        case selected
    }
}

// MARK: - Modifiers

public extension View {
    /// Applies the glass tier, clipped to shape. The caller's shape sets the radius.
    func thawGlass(_ level: ThawGlass, in shape: some InsettableShape) -> some View {
        modifier(ThawGlassModifier(level: level, shape: shape))
    }
}

/// Reduce Transparency swaps every tier's glass for the regular material and brightens the hairline.
/// Increase Contrast makes it a full point in the label colour; the separator is too faint for 3:1.
private struct ThawGlassModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let level: ThawGlass
    let shape: S

    private var increasedContrast: Bool {
        contrast == .increased
    }

    private var hairlineWidth: CGFloat {
        increasedContrast ? 1 : 0.5
    }

    /// Separator hairline at opacity: 1.5x once the glass is gone, label colour under increased contrast.
    private func hairline(_ opacity: Double) -> AnyShapeStyle {
        let strength = reduceTransparency ? min(opacity * 1.5, 1) : opacity
        if increasedContrast {
            return AnyShapeStyle(Color.primary.opacity(max(strength, 0.35)))
        }
        return AnyShapeStyle(.separator.opacity(strength))
    }

    func body(content: Content) -> some View {
        switch level {
        // Liquid Glass draws its own rim and depth; an extra hairline and shadow read as a bordered card.
        // Strokes stay only for Reduce Transparency and Increase Contrast.
        case .panel:
            surface(content, interactive: false)
                .overlay(fallbackEdge(0.5))
        case .borderlessPanel:
            surface(content, interactive: false)
        case .control:
            surface(content, interactive: true)
                .overlay(fallbackEdge(0.65))
        case let .field(isFocused):
            surface(content, interactive: true)
                .overlay(isFocused ? AnyView(shape.strokeBorder(.tint, lineWidth: 1)) : AnyView(fallbackEdge(0.35)))
        case let .accent(tint):
            // Custom: the system's tinted glass fills the whole surface, turning a warning into a solid slab.
            accentSurface(content, tint: tint)
                .overlay(shape.strokeBorder(tint.opacity(reduceTransparency ? 0.42 : 0.28), lineWidth: max(hairlineWidth, 1)))
        case let .selection(tint, .selected):
            // Flat: a clear glass lens over a floating list refracts the row, and an 18% tint through it
            // is too faint to read as selected. The neutral floor keeps it legible over glass.
            content
                .background(
                    shape
                        .fill(.quaternary.opacity(reduceTransparency ? 0.65 : 0.45))
                        .overlay(shape.fill(tint.opacity(reduceTransparency ? 0.35 : 0.22)))
                )
                .overlay(shape.strokeBorder(tint.opacity(reduceTransparency ? 0.42 : 0.28), lineWidth: max(hairlineWidth, 1)))
        case let .selection(tint, .hover):
            // Flat: a glass layer for each hover pass costs more than the depth is worth.
            content.background(shape.fill(tint.opacity(reduceTransparency ? 0.2 : 0.1)))
        }
    }

    @ViewBuilder
    private func fallbackEdge(_ opacity: Double) -> some View {
        if reduceTransparency || increasedContrast {
            shape.strokeBorder(hairline(opacity), lineWidth: hairlineWidth)
        }
    }

    @ViewBuilder
    private func surface(_ content: Content, interactive: Bool) -> some View {
        if reduceTransparency {
            content.background(shape.fill(.regularMaterial))
        } else if interactive {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }

    /// Clear glass washed with the tint; without transparency, a flat wash twice as strong.
    @ViewBuilder
    private func accentSurface(_ content: Content, tint: Color) -> some View {
        if reduceTransparency {
            content.background(shape.fill(tint.opacity(0.35)))
        } else {
            content.glassEffect(.clear.tint(tint.opacity(0.18)), in: shape)
        }
    }
}

// MARK: - Hover lift

/// A slight scale-up on hover for rows and buttons. Reduce Motion turns it off.
struct ThawHoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        // Scale only: a brightness filter installs an offscreen render pass on every view it touches,
        // which a window of lifted rows pays for in memory and pane-switch time.
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
            .thawAnimation(ThawMotion.interactive, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

public extension View {
    /// Applies the hover lift. No-op under Reduce Motion.
    func thawHoverLift() -> some View {
        modifier(ThawHoverLift())
    }
}

// MARK: - Radius scale

/// Corner radii for glass surfaces, larger than the platform defaults: glass wants generous rounding.
public enum ThawRadius {
    /// A small mark inside a control, such as a checkbox.
    public static let small: CGFloat = 4
    /// A selectable row in a list, such as the sidebar's pages.
    public static let row: CGFloat = 8
    /// Fields, pickers, small buttons, and strips inside a panel.
    public static let control: CGFloat = 12
    /// Grouped cards and hand-built card containers on a pane.
    public static let card: CGFloat = 16
    /// Free-floating panels over the desktop.
    public static let panel: CGFloat = 24
}
