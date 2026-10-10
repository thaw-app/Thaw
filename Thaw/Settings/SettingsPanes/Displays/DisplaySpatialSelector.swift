//
//  DisplaySpatialSelector.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - Layout math

/// Pure geometry for the spatial selector, kept out of the view so the
/// normalization is readable (and unit-testable) on its own.
///
/// NSScreen.frame uses AppKit's global space (origin at the primary screen's
/// bottom-left, y up, negative origins allowed) while SwiftUI draws top-left
/// with y down. So the union of all frames is translated to the origin, y is
/// flipped, and everything is scaled by one factor so a 4K panel next to a
/// laptop screen keeps its relative size and aspect ratio.
nonisolated enum DisplayThumbnailLayout {
    /// One thumbnail's rect in canvas coordinates (top-left origin).
    struct Placement: Identifiable, Equatable {
        let id: String
        let rect: CGRect
    }

    /// Normalizes screen frames into a canvas no taller than canvasHeight
    /// and no wider than maxWidth.
    ///
    /// - Returns: the placements and the canvas size they occupy. An empty
    ///   input yields no placements and a zero canvas, which the view renders
    ///   as nothing rather than as an empty box.
    static func placements(
        for frames: [(id: String, frame: CGRect)],
        canvasHeight: CGFloat,
        maxWidth: CGFloat
    ) -> (placements: [Placement], size: CGSize) {
        guard !frames.isEmpty else { return ([], .zero) }

        let union = frames.dropFirst().reduce(frames[0].frame) { $0.union($1.frame) }
        guard union.width > 0, union.height > 0 else { return ([], .zero) }

        // Fit by height first, the canvas has a fixed height budget in the
        // form row, then clamp by width so a wide three-monitor desk shrinks
        // instead of overflowing the pane.
        let scale = min(canvasHeight / union.height, maxWidth / union.width)

        let placements = frames.map { entry in
            Placement(
                id: entry.id,
                rect: CGRect(
                    x: (entry.frame.minX - union.minX) * scale,
                    y: (union.maxY - entry.frame.maxY) * scale,
                    width: entry.frame.width * scale,
                    height: entry.frame.height * scale
                )
            )
        }
        return (placements, CGSize(width: union.width * scale, height: union.height * scale))
    }
}

// MARK: - Selector

/// Connected displays arranged to match their positions on the desk.
struct DisplaySpatialSelector: View {
    let displays: [DisplaySettingsManager.DisplayInfo]
    @Binding var selectedDisplayID: String?

    /// Height budget for the arrangement canvas.
    private static let canvasHeight: CGFloat = 66
    /// Width budget; a wide arrangement scales down rather than overflowing.
    private static let canvasMaxWidth: CGFloat = 320

    private var connected: [DisplaySettingsManager.DisplayInfo] {
        displays.filter(\.isConnected)
    }

    /// Screen frames for the connected displays, resolved through
    /// DisplayInfo.displayID, the CGDirectDisplayID the manager already
    /// carries alongside the UUID, which is the only mapping needed here.
    private var layout: (placements: [DisplayThumbnailLayout.Placement], size: CGSize) {
        let screens = NSScreen.managedScreens
        let frames: [(id: String, frame: CGRect)] = connected.compactMap { info in
            guard
                let cgID = info.displayID,
                let screen = screens.first(where: { $0.displayID == cgID })
            else { return nil }
            return (info.id, screen.frame)
        }
        return DisplayThumbnailLayout.placements(
            for: frames,
            canvasHeight: Self.canvasHeight,
            maxWidth: Self.canvasMaxWidth
        )
    }

    var body: some View {
        let numbers = DisplayIdentifyOverlay.displayNumbers()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                arrangement(numbers: numbers)

                Spacer(minLength: 8)

                Button("Identify") {
                    DisplayIdentifyOverlay.flash()
                }
                .buttonStyle(.settingsGlass)
                .help(Text("Briefly flash each connected display's name on that display"))
                .disabled(connected.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Display"))
    }

    @ViewBuilder
    private func arrangement(numbers: [CGDirectDisplayID: Int]) -> some View {
        let layout = self.layout
        if !layout.placements.isEmpty {
            ZStack(alignment: .topLeading) {
                ForEach(layout.placements) { placement in
                    if let display = connected.first(where: { $0.id == placement.id }) {
                        thumbnail(for: display, size: placement.rect.size, numbers: numbers)
                            .frame(width: placement.rect.width, height: placement.rect.height)
                            .offset(x: placement.rect.minX, y: placement.rect.minY)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        }
    }

    private func thumbnail(
        for display: DisplaySettingsManager.DisplayInfo,
        size: CGSize,
        numbers: [CGDirectDisplayID: Int]
    ) -> some View {
        let isSelected = display.id == selectedDisplayID

        return Button {
            selectedDisplayID = display.id
        } label: {
            DisplayThumbnailShape(
                isSelected: isSelected,
                isConnected: display.isConnected,
                hasNotch: display.hasNotch,
                number: display.displayID.flatMap { numbers[$0] },
                size: size
            )
        }
        .buttonStyle(.plain)
        .thawHoverLift()
        // The selection fill/stroke crossfade is the only motion here, and
        // under Reduce Motion it is dropped entirely rather than shortened,
        // which is what thawAnimation does.
        .thawAnimation(ThawMotion.quick, value: isSelected)
        .help(Text(display.name))
        .accessibilityLabel(Text(display.name))
        .accessibilityValue(Text(accessibilityValue(for: display, numbers: numbers)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// Badges are decorative capsules for sighted users; VoiceOver gets the
    /// same facts through the button's value instead.
    private func accessibilityValue(
        for display: DisplaySettingsManager.DisplayInfo,
        numbers: [CGDirectDisplayID: Int]
    ) -> String {
        var parts: [String] = []
        if display.hasNotch {
            parts.append(String(localized: "Notch"))
        }
        if !display.isConnected {
            parts.append(String(localized: "Disconnected"))
        }
        if let cgID = display.displayID, let number = numbers[cgID] {
            parts.append(String(localized: "Display \(number)"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Thumbnail

/// One mini display: a rounded panel, an optional notch tab, and the display
/// number Identify also flashes so the two can be matched at a glance.
private struct DisplayThumbnailShape: View {
    let isSelected: Bool
    let isConnected: Bool
    let hasNotch: Bool
    let number: Int?
    let size: CGSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(3, min(size.height * 0.14, 7)), style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(fill)
            shape.strokeBorder(stroke, style: strokeStyle)

            if hasNotch {
                // The notch is a cut into the panel: a small dark tab
                // centered on the top edge, scaled with the thumbnail so it
                // stays a hint rather than a feature.
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 2,
                    bottomTrailingRadius: 2,
                    style: .continuous
                )
                .fill(stroke)
                .frame(width: max(8, size.width * 0.2), height: max(3, size.height * 0.14))
            }

            if let number, isConnected {
                Text(verbatim: "\(number)")
                    .font(ThawType.metric)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(ThawInk.supporting))
                    .frame(maxHeight: .infinity)
            }
        }
        .contentShape(shape)
        // The wash and the 1.5pt stroke are both colour. Differentiate Without
        // Color gets the shared ring instead of a 0.5pt line-width delta.
        .thawSelectionCue(isSelected: isSelected, in: shape)
    }

    private var fill: AnyShapeStyle {
        if !isConnected {
            // Ghost: outline only, so "remembered" never reads as "present".
            return AnyShapeStyle(Color.clear)
        }
        // Flat accent wash, see the type's doc comment for why not glass.
        return isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.22))
            : AnyShapeStyle(Color.secondary.opacity(0.14))
    }

    private var stroke: Color {
        if isSelected {
            return .accentColor
        }
        return isConnected ? .primary.opacity(0.5) : .secondary.opacity(0.35)
    }

    private var strokeStyle: StrokeStyle {
        isConnected
            ? StrokeStyle(lineWidth: isSelected ? 1.5 : 1)
            : StrokeStyle(lineWidth: 1, dash: [3, 3])
    }
}
