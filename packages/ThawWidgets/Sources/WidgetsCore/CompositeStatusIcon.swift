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
    var style = StatusIconStyle()

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let layout = StatusIconGeometry(side: side, outer: composition.outer, style: style)
            ZStack {
                if composition.outer != .none {
                    indicator(progress: 1, layout: layout)
                        .stroke(.primary.opacity(0.2), style: stroke(layout))
                    if samples[composition.outerSource] > 0 {
                        indicator(progress: samples[composition.outerSource], layout: layout)
                            .stroke(ink(for: composition.outerSource), style: stroke(layout))
                    }
                }
                let showsNetwork = composition.center.showsNetwork(for: samples)
                if showsNetwork, samples.network == .ethernet {
                    EthernetPacketGlyph()
                        .frame(width: layout.glyphSize.width, height: layout.glyphSize.width / 1.972)
                        .position(layout.center)
                } else if let symbolName = composition.center.symbolName(for: samples) {
                    Image(systemName: symbolName, variableValue: wifiVariableValue(showsNetwork: showsNetwork))
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.glyphSize.width, height: layout.glyphSize.height)
                        .position(layout.center)
                }
                if composition.bottom != .none {
                    segments(layout)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func indicator(progress: Double, layout: StatusIconGeometry) -> StatusIconArc {
        StatusIconArc(isRing: composition.outer == .ring, progress: progress, center: layout.center, radius: layout.radius)
    }

    private func stroke(_ layout: StatusIconGeometry) -> StrokeStyle {
        StrokeStyle(lineWidth: layout.lineWidth, lineCap: .round)
    }

    private func ink(for source: StatusIconComposition.Source) -> Color {
        switch style.tint(for: source, samples: samples) {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .blue: .blue
        case nil: .primary
        }
    }

    /// Whole bars, as macOS shows them, for the Wi-Fi symbol; nil for every other symbol.
    private func wifiVariableValue(showsNetwork: Bool) -> Double? {
        guard showsNetwork, samples.network == .wifi else { return nil }
        return StatusIconSignal.variableValue(bars: StatusIconSignal.bars(strength: samples[.wifi]))
    }

    /// Dots sit on their centres; bars grow upward from the same baseline as the dots.
    private func segments(_ layout: StatusIconGeometry) -> some View {
        let size = layout.dotDiameter
        // These IDs identify the four fixed segment positions, not mutable readings.
        return ForEach(0 ..< 4) { segment in
            let height = composition.bottom == .dots ? size : size * (0.7 + Double(segment) * 0.35)
            RoundedRectangle(cornerRadius: size / 2)
                .fill(segment < samples.litSegments(for: composition.bottomSource)
                    ? ink(for: composition.bottomSource) : .primary.opacity(0.2))
                .frame(width: size, height: height)
                .position(x: layout.dots[segment].x, y: layout.dots[segment].y + size / 2 - height / 2)
        }
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
    let center: CGPoint
    let radius: CGFloat

    func path(in _: CGRect) -> Path {
        let gap = StatusIconGeometry.arcGapDegrees
        let start = isRing ? -90.0 : 90 + gap / 2
        let sweep = isRing ? 360.0 : 360 - gap
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
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
