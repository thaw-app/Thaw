//
//  ThawGlass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Glass tiers

/// Thaw's shared Liquid Glass treatments.
///
/// Calibrated against Apple's visionOS apps (Music on visionOS being the
/// reference): their windows are thick, tinted glass, never clear. Clear
/// glass is the wrong material for .panel: it reads as a grey film over the
/// desktop and washes out entirely in light mode.
///
/// Every tier pairs its material with the same border discipline. Nothing in
/// Thaw should apply bare .glassEffect without going through here, so a
/// future re-skin is a change to this file, not to twenty call sites.
public enum ThawGlass {
    /// Containers that float over arbitrary desktops (search panel, palettes,
    /// popover chrome, notch descender). Regular glass.
    case panel
    /// Interactive elements inside a panel: fields, pickers, key caps, slider
    /// tracks. Interactive glass so controls respond as surfaces.
    case control
    /// A control that takes keyboard focus, like the search capsule or a
    /// gradient handle. Same glass as .control, with a border that brightens
    /// while focused so the focused field reads one step more solid.
    case field(isFocused: Bool)
    /// Emphasis surfaces (warnings, the selected sidebar row): clear glass
    /// washed with the accent, the one place thin glass is correct, because
    /// it carries a tint of its own.
    case accent(Color)
    /// The accent wash, graded: .selected is a flat neutral-and-accent fill
    /// for rows inside a list that already floats, .hover is the lighter,
    /// strokeless step the pointer leaves behind. Every "this one" in the app
    /// is one of these two.
    case selection(Color, strength: SelectionStrength)

    /// How strongly a selection surface reads.
    public enum SelectionStrength {
        /// The pointer is over it.
        case hover
        /// It is the chosen one.
        case selected
    }
}

// MARK: - Modifiers

public extension View {
    /// Applies the shared glass treatment for level, clipped to shape.
    ///
    /// The radius belongs to the caller via shape, tiers govern material,
    /// border, and depth, while geometry stays contextual.
    func thawGlass(_ level: ThawGlass, in shape: some InsettableShape) -> some View {
        modifier(ThawGlassModifier(level: level, shape: shape))
    }
}

/// The one place the accessibility display preferences meet the glass.
///
/// Reduce Transparency swaps every tier's glass for the system's regular
/// material, flat, opaque enough to read on, still appearance-aware, and
/// brightens the hairline so the edge is not lost with the depth. Increase
/// Contrast thickens the hairline to a full point and draws it in the label
/// colour rather than the separator, which is too faint to count as a
/// boundary at 3:1. Handling both here means no surface in the app needs
/// its own branch, and a surface that goes through the tiers is correct
/// under those settings by construction.
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

    /// The tier's separator hairline at opacity, adjusted for the display
    /// preferences: one and a half times as strong once the glass is gone,
    /// and in the label colour when contrast is increased.
    private func hairline(_ opacity: Double) -> AnyShapeStyle {
        let strength = reduceTransparency ? min(opacity * 1.5, 1) : opacity
        if increasedContrast {
            return AnyShapeStyle(Color.primary.opacity(max(strength, 0.35)))
        }
        return AnyShapeStyle(.separator.opacity(strength))
    }

    func body(content: Content) -> some View {
        switch level {
        // Liquid Glass draws its own rim, specular edge and depth. An extra
        // hairline and drop shadow would make every surface read as a bordered
        // card sitting on glass rather than as glass. The strokes stay only
        // where the system has no glass to draw: Reduce Transparency, and
        // Increase Contrast, where an edge must be visible.
        case .panel:
            surface(content, interactive: false)
                .overlay(fallbackEdge(0.5))
        case .control:
            surface(content, interactive: true)
                .overlay(fallbackEdge(0.65))
        case let .field(isFocused):
            surface(content, interactive: true)
                .overlay(isFocused ? AnyView(shape.strokeBorder(.tint, lineWidth: 1)) : AnyView(fallbackEdge(0.35)))
        case let .accent(tint):
            // Kept custom on purpose: the system's tinted glass fills the whole
            // surface with the tint, which turns a warning into a solid slab.
            accentSurface(content, tint: tint)
                .overlay(shape.strokeBorder(tint.opacity(reduceTransparency ? 0.42 : 0.28), lineWidth: max(hairlineWidth, 1)))
        case let .selection(tint, .selected):
            // Flat, like hover. A clear glass lens over a list that already
            // floats refracts the row it marks, and an 18% tint through it is
            // too faint to read as the chosen one, which is what the search
            // results showed. The neutral floor keeps it legible over glass.
            content
                .background(
                    shape
                        .fill(.quaternary.opacity(reduceTransparency ? 0.65 : 0.45))
                        .overlay(shape.fill(tint.opacity(reduceTransparency ? 0.35 : 0.22)))
                )
                .overlay(shape.strokeBorder(tint.opacity(reduceTransparency ? 0.42 : 0.28), lineWidth: max(hairlineWidth, 1)))
        case let .selection(tint, .hover):
            // Flat, not glass: a hover fill comes and goes with the pointer,
            // and standing up a glass layer for each pass is cost without
            // depth anyone reads.
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

    /// Clear glass washed with the tint, or, without transparency, a flat
    /// wash twice as strong, since there is no glass left to carry it.
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

/// A slight scale-up on hover for interactive rows and buttons, settling back
/// on exit. Reduce Motion turns off both the scale and its animation.
struct ThawHoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        // Scale only. A brightness filter installs an offscreen render pass
        // on every view it touches, hovered or not, and a window with a few
        // dozen lifted rows pays that in memory and in pane-switch time. The
        // transform is free; the lift is the part people notice.
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
            .thawAnimation(ThawMotion.interactive, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

public extension View {
    /// Applies the shared hover-lift focus response. No-op under
    /// Reduce Motion.
    func thawHoverLift() -> some View {
        modifier(ThawHoverLift())
    }
}

// MARK: - Radius scale

/// The corner radii Thaw's glass surfaces share, so a control, a card and a
/// floating panel read as one family instead of each picking its own.
///
/// Larger than the platform defaults on purpose: glass wants generous
/// rounding, and the difference between a 10pt and a 16pt card is most of
/// what makes a surface feel like it floats rather than sits.
public enum ThawRadius {
    /// Fields, pickers, small buttons, and strips inside a panel.
    public static let control: CGFloat = 12
    /// Grouped cards and hand-built card containers on a pane.
    public static let card: CGFloat = 16
    /// Free-floating panels over the desktop.
    public static let panel: CGFloat = 24
}
