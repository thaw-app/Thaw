//
//  WelcomeMockup.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Observation
import SwiftUI

/// Real macOS menu bar glyphs used to dress the welcome scene — the same
/// kind of status items Thaw actually manages. Split across three rings so
/// they orbit at different radii and speeds, like planets at different
/// orbits.
///
/// These are SF Symbol stand-ins rather than real menu bar app icons: on
/// current macOS, individual status items no longer show up as separate
/// windows in `CGWindowListCopyWindowInfo` (the whole bar is one composited
/// surface), so the permission-free discovery path doesn't actually return
/// per-app icons here. Getting the real ones back would need Accessibility
/// permission and `AXUIElement` introspection instead.
///
/// Note: "bluetooth" is deliberately not in this list — it isn't a real SF
/// Symbol (Apple doesn't ship a Bluetooth glyph, likely a trademark reason),
/// so `Image(systemName: "bluetooth")` silently renders nothing.
private let ring1Symbols = ["wifi", "battery.100", "speaker.wave.2"]
private let ring2Symbols = ["antenna.radiowaves.left.and.right", "moon.fill", "airpods", "mic.fill"]
private let ring3Symbols = ["sun.max.fill", "lock.fill", "personalhotspot", "airplane", "keyboard"]

/// Drives the welcome scene: the Thaw icon appears, menu bar glyphs orbit
/// out around it like little planets, then collapse back in and hide behind
/// the icon — a small preview of what Thaw actually does to the real menu
/// bar. Clicking the icon toggles the same show/hide at any time.
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

/// A single menu bar glyph orbiting the icon on a tilted, perspective ring:
/// the vertical axis is squashed into an ellipse, and each glyph's scale and
/// opacity shift with its position on that ellipse — larger and brighter at
/// the bottom of the ring, smaller and dimmer at the top — for a sense of
/// depth. The glyph itself always draws behind the center icon (never in
/// front of it), and the ring radius is kept large enough that it clears the
/// icon's bounds entirely, so there's no visible overlap either way.
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
            // Always behind the center icon — the ring radius (set by the
            // parent) is large enough that this never actually clips through
            // the icon; this is just a guarantee against it.
            .zIndex(-1)
    }
}

/// One ring of glyphs: its own radius, speed/direction, and squash, so each
/// ring reads as a distinct orbit rather than a flat repeated pattern.
///
/// The continuous rotation is driven by `TimelineView`, recomputing the
/// angle from real elapsed time on every frame — NOT by animating a state
/// variable from 0 to 360 with `withAnimation`. That approach looks
/// reasonable but is a no-op: SwiftUI's animation system interpolates
/// between the *start* and *end* snapshot of whatever the angle feeds into,
/// and a full revolution's start and end position are identical
/// (`cos(0°) == cos(360°)`), so it would animate between two identical
/// values forever — visually frozen despite "running".
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

/// The welcome slide's mockup: three rings of menu bar glyphs continuously
/// orbit the icon on tilted, perspective ellipses — at different radii and
/// speeds, like little planets — floating out or collapsing back behind it
/// as `model.itemsHidden` changes. The icon itself is a button that toggles
/// that state.
struct ThawWelcomeMockup: View {
    let model: ThawWelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Squash is chosen so that even the innermost ring's radiusY (its
    // closest approach to center, at the top/bottom of the ellipse) clears
    // the icon's own half-height (46.5pt for a 93pt icon) — so the "always
    // behind" glyphs never have to visibly clip through it.
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
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .scaleEffect(model.iconAppeared ? 1 : 0.85)
                    .opacity(model.iconAppeared ? 1 : 0)
            }
            .buttonStyle(.plain)
            // The button is icon-only; without a label VoiceOver has nothing
            // to announce for it. Describe what tapping it does right now.
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
