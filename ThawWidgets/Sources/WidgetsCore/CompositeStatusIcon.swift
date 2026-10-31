//
//  CompositeStatusIcon.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The same vector drawing is used for the enlarged and menu-bar-size previews.
/// Its caller supplies the accessible description and identifies live versus sample data.
struct CompositeStatusIcon: View {
    let composition: StatusIconComposition
    let samples: StatusIconSamples

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                if composition.outer != .none {
                    indicator(progress: 1)
                        .stroke(.primary.opacity(0.2), style: stroke(side: side))
                    if samples[composition.outerSource] > 0 {
                        indicator(progress: samples[composition.outerSource])
                            .stroke(.primary, style: stroke(side: side))
                    }
                }
                if composition.center == .wifi, samples.network == .ethernet {
                    EthernetPacketGlyph()
                        .frame(width: side * 0.48, height: side * 0.48 / 1.972)
                        .position(x: side * 0.5, y: side * 0.43)
                } else if let symbolName = composition.center.symbolName(for: samples) {
                    Image(
                        systemName: symbolName,
                        variableValue: composition.center == .wifi && samples.network == .wifi ? samples[.wifi] : nil
                    )
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.4, height: side * 0.35)
                    .position(x: side * 0.5, y: side * 0.43)
                }
                if composition.bottom != .none {
                    segments(side: side)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func indicator(progress: Double) -> StatusIconArc {
        StatusIconArc(isRing: composition.outer == .ring, progress: progress)
    }

    private func stroke(side: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: side * 0.065, lineCap: .round)
    }

    private func segments(side: CGFloat) -> some View {
        // These IDs identify the four fixed segment positions, not mutable readings.
        HStack(alignment: .bottom, spacing: side * 0.055) {
            ForEach(0 ..< 4) { segment in
                RoundedRectangle(cornerRadius: side * 0.045)
                    .fill(.primary.opacity(segment < samples.litSegments(for: composition.bottomSource) ? 1 : 0.2))
                    .frame(
                        width: side * 0.085,
                        height: composition.bottom == .dots ? side * 0.085 : side * (0.06 + Double(segment) * 0.03)
                    )
            }
        }
        .position(x: side * 0.5, y: side * 0.875)
    }
}

/// Ethernet, drawn after Apple's classic Ethernet port symbol: two 45°
/// brackets pointing outward around three dots ("<· · ·>"). Proportions trace
/// the symbol's 221:112 outline; the bracket stroke is normalized thicker so
/// it stays legible at menu-bar size.
private nonisolated struct EthernetPacketGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let width = geometry.size.width
            let stroke = height * 0.16
            let cap = stroke / 2
            let arm = width * 0.25
            let midY = height / 2
            let dotRadius = height * 0.132
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: arm + cap, y: cap))
                    path.addLine(to: CGPoint(x: cap, y: midY))
                    path.addLine(to: CGPoint(x: arm + cap, y: height - cap))
                    path.move(to: CGPoint(x: width - arm - cap, y: cap))
                    path.addLine(to: CGPoint(x: width - cap, y: midY))
                    path.addLine(to: CGPoint(x: width - arm - cap, y: height - cap))
                }
                .stroke(.primary, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                Path { path in
                    for fraction in [0.3122, 0.5, 0.6847] {
                        path.addEllipse(in: CGRect(
                            x: width * fraction - dotRadius,
                            y: midY - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        ))
                    }
                }
                .fill(.primary)
            }
        }
        .accessibilityHidden(true)
    }
}

private nonisolated struct StatusIconArc: Shape {
    let isRing: Bool
    let progress: Double

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let start = isRing ? -90.0 : 150.0
        let sweep = isRing ? 360.0 : 240.0
        var path = Path()
        path.addArc(
            center: CGPoint(x: side * 0.5, y: side * 0.43),
            radius: side * 0.35,
            startAngle: .degrees(start),
            endAngle: .degrees(start + sweep * progress),
            clockwise: false
        )
        return path
    }
}

#Preview("Combined status icon") {
    HStack(spacing: 24) {
        CompositeStatusIcon(composition: .init(), samples: .init())
            .frame(width: 120, height: 120)
        CompositeStatusIcon(composition: .init(), samples: .init())
            .frame(width: 22, height: 22)
    }
    .padding()
}
