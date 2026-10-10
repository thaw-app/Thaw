//
//  WelcomeMockup.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Observation
import SwiftUI

/// SF Symbol stand-ins for menu bar glyphs, one array per orbit ring. Real
/// app icons would need Accessibility, since `CGWindowListCopyWindowInfo` no
/// longer lists status items as separate windows.
///
/// No "bluetooth": it isn't an SF Symbol, so it silently renders nothing.
private let ring1Symbols = ["wifi", "battery.100", "speaker.wave.2"]
private let ring2Symbols = ["antenna.radiowaves.left.and.right", "moon.fill", "airpods", "mic.fill"]
private let ring3Symbols = ["sun.max.fill", "lock.fill", "personalhotspot", "airplane", "keyboard"]

/// Drives the welcome scene: glyphs orbit out from the Thaw icon, then hide
/// behind it. Clicking the icon toggles show/hide.
@MainActor
@Observable
final class ThawWelcomeModel {
    var iconAppeared = false
    var itemsHidden = true
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    func restart() {
        iconAppeared = false
        itemsHidden = true

        replaceRestartTask(&restartTask) {
            try? await Task.sleep(for: .seconds(0.05))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { self.iconAppeared = true }

            try? await Task.sleep(for: .seconds(0.55))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { self.itemsHidden = false }

            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.55, bounce: 0.1)) { self.itemsHidden = true }
        }
    }

    /// Toggles hidden/shown, as if the icon had just been clicked.
    func toggle() {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { itemsHidden.toggle() }
    }
}

/// One glyph on a squashed elliptical ring, scaled and dimmed by depth.
private struct OrbitingGlyph: View {
    let symbol: String
    let size: CGFloat
    let radiusX: CGFloat
    let radiusY: CGFloat
    let phaseDegrees: Double
    let orbitDegrees: Double
    let visible: Bool

    private var totalAngle: Double {
        orbitDegrees + phaseDegrees
    }

    private var radians: Double {
        totalAngle * .pi / 180
    }

    /// 0 at the back (top) of the ring, 1 at the front (bottom).
    private var depth: Double {
        (sin(radians) + 1) / 2
    }

    private var dimensionalScale: CGFloat {
        0.6 + 0.55 * depth
    }

    private var dimensionalOpacity: Double {
        0.55 + 0.45 * depth
    }

    var body: some View {
        GlassIconBubble(symbol: symbol, size: size)
            .scaleEffect(visible ? dimensionalScale : 0.2)
            .offset(
                x: visible ? cos(radians) * radiusX : 0,
                y: visible ? sin(radians) * radiusY : 0
            )
            .opacity(visible ? dimensionalOpacity : 0)
            // The ring radius already clears the icon; this is a guarantee.
            .zIndex(-1)
    }
}

/// One ring of glyphs with its own radius, speed, direction, and squash.
///
/// Rotation comes from `TimelineView` elapsed time. Animating an angle from 0
/// to 360 with `withAnimation` stays frozen, since both endpoints are equal.
private struct OrbitRing: View {
    let symbols: [String]
    let glyphSize: CGFloat
    let radiusX: CGFloat
    let squash: CGFloat
    let duration: Double
    let reversed: Bool
    let visible: Bool
    let phaseShift: Double
    let reduceMotion: Bool

    @State private var startDate = Date()

    private var radiusY: CGFloat {
        radiusX * squash
    }

    var body: some View {
        TimelineView(.animation(paused: !visible || reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let progress = elapsed.truncatingRemainder(dividingBy: duration) / duration
            let orbitDegrees = reduceMotion ? 0 : (reversed ? -1.0 : 1.0) * progress * 360

            ZStack {
                ForEach(symbols, id: \.self) { symbol in
                    let index = symbols.firstIndex(of: symbol) ?? 0
                    let phase = Double(index) / Double(symbols.count) * 360 + phaseShift
                    let springDuration = reduceMotion ? 0.2 : 0.5
                    let bounce = if reduceMotion {
                        0.0
                    } else if visible {
                        0.4
                    } else {
                        0.1
                    }
                    OrbitingGlyph(
                        symbol: symbol,
                        size: glyphSize,
                        radiusX: radiusX,
                        radiusY: radiusY,
                        phaseDegrees: phase,
                        orbitDegrees: orbitDegrees,
                        visible: visible
                    )
                    .animation(
                        .spring(duration: springDuration, bounce: bounce)
                            .delay(Double(index) * 0.04),
                        value: visible
                    )
                }
            }
        }
    }
}

/// The welcome slide's mockup. Glyphs float out or collapse behind the icon
/// as `model.itemsHidden` changes; the icon toggles it.
struct ThawWelcomeMockup: View {
    let model: ThawWelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Keeps the innermost ring's radiusY above the icon's 46.5pt half-height.
    private let squash: CGFloat = 0.5
    private let ring1Radius: CGFloat = 96
    private let ring2Radius: CGFloat = 136
    private let ring3Radius: CGFloat = 176

    var body: some View {
        ZStack {
            OrbitRing(
                symbols: ring1Symbols,
                glyphSize: 27,
                radiusX: ring1Radius,
                squash: squash,
                duration: 14,
                reversed: false,
                visible: !model.itemsHidden,
                phaseShift: 0,
                reduceMotion: reduceMotion
            )
            OrbitRing(
                symbols: ring2Symbols,
                glyphSize: 30,
                radiusX: ring2Radius,
                squash: squash,
                duration: 22,
                reversed: true,
                visible: !model.itemsHidden,
                phaseShift: 25,
                reduceMotion: reduceMotion
            )
            OrbitRing(
                symbols: ring3Symbols,
                glyphSize: 34,
                radiusX: ring3Radius,
                squash: squash,
                duration: 32,
                reversed: false,
                visible: !model.itemsHidden,
                phaseShift: 50,
                reduceMotion: reduceMotion
            )

            Button {
                model.toggle()
            } label: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 93, height: 93)
                    .thawShadow(.hero)
                    .scaleEffect(model.iconAppeared ? 1 : 0.85)
                    .opacity(model.iconAppeared ? 1 : 0)
            }
            .buttonStyle(.plain)
            // Icon-only button: describe what tapping does right now.
            .accessibilityLabel(
                model.itemsHidden
                    ? String(localized: "Show menu bar items")
                    : String(localized: "Hide menu bar items")
            )
            .zIndex(0)
        }
        .frame(width: 400, height: 272)
    }
}
