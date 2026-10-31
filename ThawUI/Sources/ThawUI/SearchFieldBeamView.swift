//
//  SearchFieldBeamView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// Draws the beam inside an outline as a hairline, a glow into the field and a glint. Core Animation runs the
/// windows, so the launcher does no work while the beam goes round. With Reduce Motion the window stands still.
public struct SearchFieldBeamView<Outline: InsettableShape>: View {
    /// The beam is drawn in two layers, one over the field and one under its text.
    public init(
        outline: Outline,
        beam: SearchFieldBeam,
        part: Part = .edge
    ) {
        self.outline = outline
        self.beam = beam
        self.part = part
    }

    public enum Part {
        /// The hairline on the border and its glint. Over the field.
        case edge
        /// The glow into the field. Under the text, so what is typed is never tinted.
        case spill
    }

    public let outline: Outline
    public let beam: SearchFieldBeam
    public var part = Part.edge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.searchFieldBeamFrameRate) private var frameRate
    @State private var isShown = false

    /// Seconds for the window to go once round.
    public static var turn: Double {
        3.2
    }

    /// How bright the whole beam is: every layer's strength is a share of it.
    private static var intensity: Double {
        1
    }

    /// How far the light reaches in from the border, as a share of its full size: every width, blur and patch
    /// is scaled by it, so the field keeps its room.
    private static var reach: CGFloat {
        0.5
    }

    /// Seconds for the colours to drift one way and back, and how far, in degrees of hue.
    public static var drift: (period: Double, range: Double) {
        (12, 30)
    }

    public var body: some View {
        GeometryReader { proxy in
            let key = BeamLayerView.Key(
                size: proxy.size,
                scale: displayScale,
                outline: outline.path(in: CGRect(origin: .zero, size: proxy.size)),
                beam: beam,
                isEdge: part == .edge,
                isDark: isDark,
                isStill: reduceMotion,
                frameRate: Float(frameRate)
            )
            BeamLayers(key: key) { layers(size: proxy.size) }
        }
        .opacity(isShown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { isShown = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    /// The part's layers for a field of that size, with their still parts drawn.
    private func layers(size: CGSize) -> [BeamLayer] {
        // Mono's greys are weaker, or they read as a grey smudge.
        let strength = Float((beam == .mono ? 0.6 : 1) * Self.intensity)
        let light = (isDark ? NSColor.white : NSColor.black).cgColor
        // Two hues to drift between, or the one the colours have when they stand still.
        let hues: [Angle] = reduceMotion ? [.zero] : [.degrees(-Self.drift.range), .degrees(Self.drift.range)]
        func drawn(_ content: some View) -> CGImage? {
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
            renderer.scale = displayScale
            return renderer.cgImage
        }
        switch part {
        case .edge:
            // The rim: the colours just inside the border, soft, so the field looks lit from its edge.
            let rim = BeamLayer(
                colour: hues.compactMap { drawn(colour(hue: $0).mask(outline.stroke(lineWidth: 8 * Self.reach)).blur(radius: 6 * Self.reach)) },
                window: BeamLight.glowWindow,
                opacity: (isDark ? 0.75 : 0.6) * strength
            )
            let hairline = BeamLayer(
                colour: hues.compactMap { drawn(colour(hue: $0).mask(self.hairline)) },
                glint: drawn(self.hairline).map { BeamLayer.Glint(stops: BeamLight.glint, light: light, mask: $0) },
                window: BeamLight.hairlineWindow,
                opacity: (isDark ? 1 : 0.8) * strength
            )
            // The glint again, softened, which is what makes the hairline seem to give off light.
            let bloom = BeamLayer(
                glint: drawn(outline.stroke(lineWidth: 2).blur(radius: 6 * Self.reach)).map { BeamLayer.Glint(stops: BeamLight.bloom, light: light, mask: $0) },
                opacity: (isDark ? 0.6 : 0.45) * strength
            )
            return [rim, hairline, bloom]
        case .spill:
            let band = hues.compactMap { hue in
                drawn(
                    ZStack {
                        colour(hue: hue)
                            .opacity(0.7)
                        outline
                            .stroke(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.14), lineWidth: 2)
                            .blur(radius: 5 * Self.reach)
                    }
                    // A band along the border: the middle is the text's.
                    .mask(outline.stroke(lineWidth: 32 * Self.reach).blur(radius: 12 * Self.reach))
                )
            }
            return [BeamLayer(colour: band, window: BeamLight.glowWindow, opacity: (isDark ? 0.7 : 0.5) * strength)]
        }
    }

    private var hairline: some View {
        outline.inset(by: 0.75).stroke(lineWidth: 1.5)
    }

    /// The colours of each side: the set's colours all the way round, so no stretch of the border is left dark,
    /// and brighter patches where the beam puts them.
    private func colour(hue: Angle) -> some View {
        ZStack {
            AngularGradient(colors: beam.ring, center: .center)
                .opacity(0.6)
            patches
        }
        .hueRotation(hue)
        .saturation(isDark ? 1.3 : 1.6)
    }

    private var patches: some View {
        Canvas { context, size in
            for blob in beam.blobs {
                let center = CGPoint(x: blob.center.x * size.width, y: blob.center.y * size.height)
                var patch = context
                // Squashed from a circle, so the patch is as wide and as tall as the beam asks.
                patch.translateBy(x: center.x, y: center.y)
                patch.scaleBy(x: 1, y: blob.radii.height / blob.radii.width)
                let reach = blob.radii.width * Self.reach
                patch.fill(
                    Path(ellipseIn: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)),
                    with: .radialGradient(Gradient(colors: [blob.color, blob.color.opacity(0)]), center: .zero, startRadius: 0, endRadius: reach)
                )
            }
        }
    }
}

/// How the beam's light falls along the border, as stops from nothing to full and back: each a part of the lap
/// and how strong the light is there.
public enum BeamLight {
    /// Where the glint and its bloom are brightest, so the two travel together.
    public static let glintCenter = 0.66

    /// Where round the field the hairline shows, from nothing to full and back, as parts of the lap.
    public static let hairlineWindow: [(Double, Double)] = [
        (0, 0), (0.3, 0), (0.36, 0.1), (0.44, 0.35), (0.52, 1), (0.8, 1), (0.86, 0.35), (0.92, 0.1), (0.95, 0), (1, 0),
    ]

    /// The same for the glow, a little wider.
    public static let glowWindow: [(Double, Double)] = [
        (0, 0), (0.22, 0), (0.28, 0.12), (0.36, 0.4), (0.46, 1), (0.82, 1), (0.88, 0.4), (0.94, 0.12), (0.97, 0), (1, 0),
    ]

    /// The bright place on the hairline, near the window's leading end.
    public static let glint: [(Double, Double)] = [
        (0, 0), (0.54, 0), (0.57, 0.1), (0.6, 0.3), (0.63, 0.6), (glintCenter, 0.75), (0.69, 0.6), (0.72, 0.3), (0.75, 0.1), (0.78, 0), (1, 0),
    ]

    /// The glint's softer twin, which the blur spreads.
    public static let bloom: [(Double, Double)] = [
        (0, 0), (0.54, 0), (0.59, 0.08), (0.63, 0.45), (glintCenter, 0.85), (0.69, 0.45), (0.73, 0.08), (0.78, 0), (1, 0),
    ]
}
