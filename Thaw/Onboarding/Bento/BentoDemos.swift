//
//  BentoDemos.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The eight cards of the onboarding bento, and the settings pane each one
/// opens.
///
/// Every animated card is a loop driven by a single phase in 0..<1, and
/// the tile computes that phase from wall-clock time (see BentoTile).
/// The demos therefore never own state and never schedule anything; they are
/// pure functions of the phase, which is what lets eight of them run at once
/// on one TimelineView each, freeze cleanly when the window is not key, and
/// collapse to a still frame under Reduce Motion by passing phase == 1.
///
/// phaseOffset staggers the loops so the grid never pulses in unison: with
/// every card starting at phase zero the reveals, drops and switches would
/// all land on the same frame and the page would read as one big blink.
enum BentoDemo: CaseIterable {
    case find
    case style
    case reveal
    case thawBar
    case triggers
    case profiles
    case zen
    case integrations

    /// The pane a click on the card lands on.
    var pane: SettingsNavigationIdentifier {
        switch self {
        case .find: .general
        case .style: .menuBarAppearance
        case .reveal: .general
        case .thawBar: .displays
        case .triggers: .automation
        case .profiles: .profiles
        case .zen: .hotkeys
        case .integrations: .automation
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .find: "Find anything"
        case .style: "Style the bar"
        case .reveal: "Reveal"
        case .thawBar: "Thaw Bar"
        case .triggers: "Rules"
        case .profiles: "Profiles"
        case .zen: "Zen Mode"
        case .integrations: "Control it from other apps"
        }
    }

    var caption: LocalizedStringKey {
        switch self {
        case .find: "Search your menu bar from the keyboard"
        case .style: "Tint, gradient, shape, per light and dark"
        case .reveal: "Click, hover, scroll or a keyboard shortcut"
        case .thawBar: "Hidden items in a bar of their own"
        case .triggers: "Reveal an item when a condition is met"
        case .profiles: "Switch layouts by display, Space or Focus"
        case .zen: "One action, an empty bar"
        case .integrations: "Raycast, Droppy, Shortcuts and any thaw:// link"
        }
    }

    /// One loop of the demo, in seconds.
    var period: TimeInterval {
        switch self {
        case .find: 4.0
        case .style: 6.0
        case .reveal: 3.0
        case .thawBar: 5.0
        case .triggers: 4.5
        case .profiles: 5.5
        case .zen: 3.5
        case .integrations: 1.0
        }
    }

    /// Where in its loop the demo starts, so neighbours are out of step.
    var phaseOffset: Double {
        switch self {
        case .find: 0
        case .style: 0.5
        case .reveal: 0.2
        case .thawBar: 0.7
        case .triggers: 0.35
        case .profiles: 0.85
        case .zen: 0.1
        case .integrations: 0
        }
    }

    /// Whether the demo changes with the phase at all. A still card keeps
    /// its timeline paused rather than redrawing sixty times a second for
    /// nothing.
    var isAnimated: Bool {
        self != .integrations
    }
}

// MARK: - Easing

/// Zero before start, one after end, and a smoothstep in between.
///
/// Every demo is written against these two curves rather than SwiftUI's
/// animation system because the timeline hands each frame a phase, not a
/// state change: there is nothing for .animation to interpolate between,
/// so the easing has to be a function of the phase itself. Smoothstep is
/// enough. A spring here would need a solver per frame for a bounce nobody
/// reads at this size.
private nonisolated func ramp(_ phase: Double, _ start: Double, _ end: Double) -> Double {
    guard end > start else { return phase >= end ? 1 : 0 }
    let t = ((phase - start) / (end - start)).clamped(to: 0 ... 1)
    return t * t * (3 - 2 * t)
}

/// One between start + edge and end - edge, easing in and out of zero on
/// either side.
private nonisolated func window(_ phase: Double, _ start: Double, _ end: Double, edge: Double = 0.06) -> Double {
    ramp(phase, start, start + edge) * (1 - ramp(phase, end - edge, end))
}

// MARK: - Stage

/// Lays a demo out at scale inside whatever slot the tile gives it.
///
/// The demo bar's glyph, clock and label sizes are fixed points because it
/// replicates the real bar. Rather than fork a compact bar per tile size, the
/// stage lays the demo out at natural size in a frame the inverse of the
/// scale, then scales it down as one transform, which is free to composite.
/// alignment picks what survives when content is wider than the frame: small
/// tiles align trailing so the hidden cluster, divider and clock stay in view
/// and the Finder label is cut.
private struct DemoStage<Content: View>: View {
    let scale: CGFloat
    var alignment: Alignment = .center
    var overflow: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            content
                .offset(x: overflow)
                .frame(
                    width: proxy.size.width / scale,
                    height: proxy.size.height / scale,
                    alignment: alignment
                )
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}

// MARK: - Content

/// The looping micro-demo for one card, drawn from phase.
///
/// Motion is transforms and opacity only. Blur, brightness and material
/// changes each install an offscreen pass per view they touch, and with
/// seven loops running side by side the compositor would pay that on every
/// frame of every card.
///
/// phase == 1 never arrives from a running timeline (the remainder stays
/// below one) and is the tile's signal that motion is off: each demo shows
/// its resolved state there instead of its starting frame, so a Reduce
/// Motion user sees the bar revealed, the strip filled, the mode on.
struct BentoDemoContent: View {
    let demo: BentoDemo
    let phase: Double

    /// The scale the small tiles show the shared bar at. The tile is 166pt
    /// wide and the bar's natural width is near 390pt, so the bar is drawn
    /// trailing-aligned and lets its leading end run off the card.
    private static let compactScale: CGFloat = 0.68
    /// How far the compact bar is pushed past the tile's trailing edge, so
    /// the capsule's rounded end is cut rather than floating inside the
    /// card with a margin. The HUD under each compact bar is trailing-padded
    /// by this plus half the visible width less half its own width, which
    /// centres it under the part of the bar the card shows.
    private static let compactOverflow: CGFloat = 36

    private var isStill: Bool {
        phase >= 1
    }

    var body: some View {
        switch demo {
        case .find: find
        case .style: style
        case .reveal: reveal
        case .thawBar: thawBar
        case .triggers: triggers
        case .profiles: profiles
        case .zen: zen
        case .integrations: integrations
        }
    }

    // MARK: Find

    /// A magnifier sweeps the hidden cluster while the query types itself
    /// out; the glyph under the magnifier grows, the way the search panel
    /// highlights the item the query has narrowed to.
    private var find: some View {
        let sweep = ramp(phase, 0.1, 0.7)
        let query = String(localized: "Sound")
        let typed = Int((ramp(phase, 0.12, 0.6) * Double(query.count)).rounded(.down))

        return DemoStage(scale: 0.9) {
            VStack(spacing: ThawSpacing.inset) {
                DemoMenuBar(
                    hiddenSymbols: ["wifi", "battery.100", "speaker.wave.2"],
                    hiddenShown: true,
                    trailingSymbols: ["bolt.horizontal"],
                    searchSweep: sweep
                )
                SlideHUD {
                    HStack(spacing: ThawSpacing.base) {
                        Image(systemName: "magnifyingglass")
                            .font(ThawType.symbol)
                            .foregroundStyle(.secondary)
                        // A fixed slot for the query so the capsule does not
                        // grow a pixel per letter.
                        Text(verbatim: String(query.prefix(typed)))
                            .font(ThawType.detail)
                            .frame(width: 64, alignment: .leading)
                        KeyCapView(systemImage: "return")
                    }
                }
            }
        }
    }

    // MARK: Style

    /// The same bar in each of the three shape treatments, crossfaded at the
    /// thirds of the loop, with the HUD's highlight following.
    private var style: some View {
        // Regular holds the first third and returns at the wrap, so the loop
        // closes on the style it opened with and the still frame is the
        // default look.
        let toGradient = ramp(phase, 0.30, 0.36)
        let toPills = ramp(phase, 0.63, 0.69)
        let toRegular = ramp(phase, 0.95, 1.0)
        let weights: [(DemoBarStyle, Double)] = [
            (.regular, max(1 - toGradient, toRegular)),
            (.gradient, toGradient * (1 - toPills)),
            (.pills, toPills * (1 - toRegular)),
        ]
        let labels: [(DemoBarStyle, LocalizedStringKey)] = [
            (.regular, "Default"),
            (.gradient, "Gradient"),
            (.pills, "Pills"),
        ]

        return DemoStage(scale: 0.9) {
            VStack(spacing: ThawSpacing.inset) {
                ZStack {
                    ForEach(Array(weights.enumerated()), id: \.offset) { _, entry in
                        DemoMenuBar(
                            hiddenSymbols: [],
                            hiddenShown: false,
                            trailingSymbols: ["wifi", "battery.100"],
                            style: entry.0
                        )
                        .opacity(entry.1)
                    }
                }
                SlideHUD {
                    HStack(spacing: 0) {
                        ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                            let weight = weights[index].1
                            Text(label.1)
                                .font(ThawType.detail)
                                .fontWeight(weight > 0.5 ? .semibold : .regular)
                                .foregroundStyle(weight > 0.5 ? Color.primary : Color.secondary)
                                .padding(.horizontal, ThawSpacing.row)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.1 * weight), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: Reveal

    /// The divider is clicked halfway through and the hidden cluster slides
    /// in. The HUD stays, and only dips like a pressed key at the click.
    private var reveal: some View {
        let press = window(phase, 0.42, 0.56, edge: 0.05)

        return DemoStage(scale: Self.compactScale, alignment: .trailing, overflow: Self.compactOverflow) {
            VStack(alignment: .trailing, spacing: ThawSpacing.base) {
                DemoMenuBar(
                    hiddenSymbols: ["wifi", "battery.100", "speaker.wave.2"],
                    hiddenShown: phase > 0.5,
                    trailingSymbols: ["magnifyingglass"]
                )
                .fixedSize(horizontal: true, vertical: false)
                SlideHUD {
                    Label("Click", systemImage: "hand.tap")
                        .font(ThawType.detail)
                        .foregroundStyle(.secondary)
                }
                .scaleEffect(1 - 0.08 * press)
                .padding(.trailing, Self.compactOverflow + 88)
            }
        }
    }

    // MARK: Thaw Bar

    /// A notch at the top of the card with a glass strip beneath it; three
    /// glyphs drop into the strip one after another.
    private var thawBar: some View {
        let symbols = ["wifi", "battery.100", "speaker.wave.2"]

        return DemoStage(scale: 1, alignment: .top) {
            VStack(spacing: ThawSpacing.compact) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(height: 16)
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 7,
                        bottomTrailingRadius: 7,
                        style: .continuous
                    )
                    .fill(.black)
                    .overlay(
                        UnevenRoundedRectangle(
                            bottomLeadingRadius: 7,
                            bottomTrailingRadius: 7,
                            style: .continuous
                        )
                        .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .frame(width: 64, height: 20)
                }
                HStack(spacing: ThawSpacing.base) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                        let start = 0.3 + Double(index) * 0.15
                        let drop = ramp(phase, start, start + 0.15)
                        GlassIconBubble(symbol: symbol, size: 18, showBackground: false)
                            .offset(y: -18 * (1 - drop))
                            .opacity(drop)
                    }
                }
                .padding(.horizontal, ThawSpacing.inset)
                .padding(.vertical, ThawSpacing.compact)
                .thawGlass(.panel, in: Capsule())
            }
        }
    }

    // MARK: Rules

    /// A condition fires (a call joins), and the items the rule watches for
    /// come out of hiding.
    private var triggers: some View {
        let fired = ramp(phase, 0.15, 0.3)

        return DemoStage(scale: Self.compactScale, alignment: .trailing, overflow: Self.compactOverflow) {
            VStack(alignment: .trailing, spacing: ThawSpacing.base) {
                DemoMenuBar(
                    hiddenSymbols: ["mic.fill", "video.fill", "speaker.wave.2"],
                    hiddenShown: phase > 0.5,
                    trailingSymbols: ["wifi"]
                )
                .fixedSize(horizontal: true, vertical: false)
                SlideHUD {
                    Label("Zoom joined", systemImage: "video.fill")
                        .font(ThawType.detail)
                        .foregroundStyle(.secondary)
                }
                .scaleEffect(0.9 + 0.1 * fired)
                .opacity(fired)
                .padding(.trailing, Self.compactOverflow + 68)
            }
        }
    }

    // MARK: Profiles

    /// Two layouts under a pill naming the active profile; both crossfade
    /// at the half, and the loop closes on Work.
    private var profiles: some View {
        let home = ramp(phase, 0.47, 0.53) * (1 - ramp(phase, 0.96, 1.0))
        let sets: [(name: LocalizedStringKey, symbol: String, items: [String], weight: Double)] = [
            ("Work", "briefcase.fill", ["wifi", "airpods", "calendar", "battery.75"], 1 - home),
            ("Home", "house.fill", ["music.note", "speaker.wave.2", "tv", "wifi"], home),
        ]

        return DemoStage(scale: 0.95) {
            VStack(spacing: ThawSpacing.base) {
                ZStack {
                    ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                        SlideHUD {
                            Label(set.name, systemImage: set.symbol)
                                .font(ThawType.detail)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(set.weight)
                    }
                }
                ZStack {
                    ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                        HStack(spacing: ThawSpacing.row) {
                            ForEach(set.items, id: \.self) { symbol in
                                GlassIconBubble(symbol: symbol, size: 22, showBackground: false)
                            }
                        }
                        .opacity(set.weight)
                        .offset(x: 8 * (1 - set.weight))
                    }
                }
            }
        }
    }

    // MARK: Zen

    /// Every item leaves the bar but the clock, and a capsule says why.
    private var zen: some View {
        let badge = isStill ? 1 : window(phase, 0.42, 0.95)

        return DemoStage(scale: Self.compactScale, alignment: .trailing, overflow: Self.compactOverflow) {
            VStack(alignment: .trailing, spacing: ThawSpacing.base) {
                DemoMenuBar(
                    hiddenSymbols: ["wifi", "battery.100", "speaker.wave.2", "bell"],
                    hiddenShown: phase < 0.4,
                    trailingSymbols: []
                )
                .fixedSize(horizontal: true, vertical: false)
                SlideHUD {
                    Label("Zen Mode on", systemImage: "moon.fill")
                        .font(ThawType.detail)
                        .foregroundStyle(.secondary)
                }
                .scaleEffect(0.9 + 0.1 * badge)
                .opacity(badge)
                .padding(.trailing, Self.compactOverflow + 80)
            }
        }
    }

    // MARK: Integrations

    /// Still: three compact cards, each resolving its icon from the bundled
    /// asset, then Launch Services, then a symbol (see IntegrationCard).
    private var integrations: some View {
        HStack(spacing: ThawSpacing.inset) {
            IntegrationCard(
                appName: "Droppy",
                subtitle: String(localized: "Install as a Droplet"),
                bundledAssetName: "DroppyIcon",
                fallbackSymbol: "arrow.triangle.2.circlepath",
                isCompact: true
            )
            IntegrationCard(
                appName: "Raycast",
                subtitle: String(localized: "Toggle and search"),
                bundledAssetName: "RaycastIcon",
                bundleIdentifier: "com.raycast.macos",
                fallbackSymbol: "bolt.fill",
                isCompact: true
            )
            IntegrationCard(
                appName: "Shortcuts",
                subtitle: String(localized: "Run any action"),
                bundledAssetName: nil,
                bundleIdentifier: "com.apple.shortcuts",
                fallbackSymbol: "square.2.layers.3d",
                isCompact: true
            )
        }
        .padding(.horizontal, ThawSpacing.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
