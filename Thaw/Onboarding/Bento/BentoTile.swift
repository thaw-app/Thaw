//
//  BentoTile.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Flat fills and hairlines avoid per-tile glass offscreen passes over the window's existing vibrancy.
/// Pause demos behind Settings to spare the GPU; Reduce Motion shows the resolved frame.
struct BentoTile: View {
    let demo: BentoDemo
    let index: Int
    let appeared: Bool
    /// Whether a click opens the card's pane; under Simple Mode it only finishes setup.
    var opensPane = true
    let action: () -> Void

    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The loop's origin, captured once so the phase is elapsed time from
    /// the card's first frame rather than from an arbitrary epoch.
    @State private var startDate = Date()
    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
    }

    private var isPaused: Bool {
        !demo.isAnimated || !appearsActive || reduceMotion
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThawSpacing.compact) {
                demoSlot
                caption
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                shape.fill(Color("BrandSurface"))
                if isHovered {
                    Color.clear.thawGlass(.selection(.accentColor, strength: .hover), in: shape)
                }
            }
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            .clipShape(shape)
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .thawAnimation(ThawMotion.quick, value: isHovered)
        .thawHoverLift()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .thawAnimation(ThawMotion.settle.delay(BentoTile.entranceDelay(index: index)), value: appeared)
        .accessibilityLabel(opensPane ? Text("\(Text(demo.title)), opens \(Text(demo.pane.localized))") : Text(demo.title))
    }

    /// Captions shrink the demo stage, not the card; clip compact bars that intentionally extend past its edges.
    private var demoSlot: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let phase = reduceMotion
                ? 1
                : ((elapsed / demo.period) + demo.phaseOffset).truncatingRemainder(dividingBy: 1)
            BentoDemoContent(demo: demo, phase: phase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            HStack(spacing: ThawSpacing.base) {
                SettingsPaneIconTile(identifier: demo.pane, side: 22)
                Text(demo.title)
                    .font(ThawType.heading)
                    .lineLimit(1)
            }
            Text(demo.caption)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.bottom, ThawSpacing.row)
    }
}

extension BentoTile {
    /// Each tile starts a little sooner after the one before, so the grid settles as one motion instead of
    /// ticking in at even steps. Tiles past the list start with the last one.
    static func entranceDelay(index: Int) -> Double {
        let delays = [0, 0.03, 0.055, 0.075, 0.09, 0.1, 0.11, 0.12]
        return delays[min(max(index, 0), delays.count - 1)]
    }
}
