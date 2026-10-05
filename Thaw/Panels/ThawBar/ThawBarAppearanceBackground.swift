//
//  ThawBarAppearanceBackground.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

struct ThawBarAppearanceBackground: View {
    let appearance: ResolvedThawBarAppearance
    let sampledColor: CGColor?
    let adaptiveColor: CGColor?
    let palette: WallpaperPalette?
    let shape: ThawBarBorderShape

    private var sample: Color {
        sampledColor.map { Color(cgColor: $0) } ?? Color.defaultLayoutBar
    }

    private var adaptive: Color {
        adaptiveColor.map { Color(cgColor: $0) } ?? sample
    }

    var body: some View {
        ZStack {
            if appearance.backgroundKind != .glass, appearance.tintKind != .glass {
                sample
            }
            backgroundFill
            tintFill
        }
        .overlay {
            if appearance.backgroundHasBorder {
                shape.strokeBorder(
                    Color(cgColor: appearance.backgroundBorderColor),
                    lineWidth: appearance.backgroundBorderWidth
                )
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backgroundFill: some View {
        switch appearance.backgroundKind {
        case .none:
            Color.clear
        case .solid:
            Color(cgColor: appearance.backgroundColor).opacity(appearance.backgroundOpacity)
        case .gradient:
            appearance.backgroundGradient.withAlpha(appearance.backgroundOpacity).swiftUIView(using: .displayP3)
        case .adaptive:
            adaptive.opacity(appearance.backgroundOpacity)
        case .glass:
            glass(
                style: appearance.backgroundGlassStyle,
                colored: appearance.backgroundGlassIsColored,
                color: appearance.backgroundColor,
                opacity: appearance.backgroundOpacity
            )
        }
    }

    @ViewBuilder
    private var tintFill: some View {
        switch appearance.tintKind {
        case .noTint:
            Color.clear
        case .solid:
            Color(cgColor: appearance.tintColor).opacity(appearance.tintOpacity)
        case .gradient:
            appearance.tintGradient.withAlpha(appearance.tintOpacity).swiftUIView(using: .displayP3)
        case .adaptive:
            adaptive.opacity(appearance.tintOpacity)
        case .adaptiveGradient:
            if let primary = palette?.primary, let secondary = palette?.secondary {
                LinearGradient(
                    colors: [
                        Color(.displayP3, red: primary.red, green: primary.green, blue: primary.blue),
                        Color(.displayP3, red: secondary.red, green: secondary.green, blue: secondary.blue),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ).opacity(appearance.tintOpacity)
            } else {
                adaptive.opacity(appearance.tintOpacity)
            }
        case .glass:
            glass(
                style: appearance.tintGlassStyle,
                colored: appearance.tintGlassIsColored,
                color: appearance.tintColor,
                opacity: appearance.tintOpacity
            )
        }
    }

    private func glass(style: MenuBarGlassStyle, colored: Bool, color: CGColor, opacity: Double) -> some View {
        ThawBarGlassSurface(style: style, colored: colored, color: color, opacity: opacity, shape: shape)
    }
}

private struct ThawBarGlassSurface: NSViewRepresentable, Equatable {
    let style: MenuBarGlassStyle
    let colored: Bool
    let color: CGColor
    let opacity: Double
    let shape: ThawBarBorderShape

    /// ThawBarBorderShape is outside this file, so its fields are compared
    /// directly rather than conforming it to Equatable from here.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style
            && lhs.colored == rhs.colored
            && lhs.color == rhs.color
            && lhs.opacity == rhs.opacity
            && lhs.shape.cornerRadius == rhs.shape.cornerRadius
            && lhs.shape.cornerStyle == rhs.shape.cornerStyle
            && lhs.shape.omitTopEdge == rhs.shape.omitTopEdge
            && lhs.shape.insetAmount == rhs.shape.insetAmount
    }

    func makeNSView(context _: Context) -> SurfaceView {
        SurfaceView()
    }

    func updateNSView(_ view: SurfaceView, context _: Context) {
        guard view.configuration != self else { return }
        view.configuration = self
        view.needsLayout = true
    }

    final class SurfaceView: NSView {
        var configuration: ThawBarGlassSurface?
        private let regular = NSGlassEffectView()
        private let liquid = MenuBarLiquidGlassContainerView()

        override init(frame: NSRect) {
            super.init(frame: frame)
            addSubview(regular)
            addSubview(liquid)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            guard let config = configuration else { return }
            regular.frame = bounds
            liquid.frame = bounds
            regular.isHidden = config.style.usesShapeAwareSurface
            liquid.isHidden = !config.style.usesShapeAwareSurface
            if config.style.usesShapeAwareSurface {
                liquid.update(
                    path: config.shape.path(in: bounds).cgPath,
                    isColored: config.colored,
                    tintColor: config.color,
                    tintOpacity: config.opacity,
                    effectOpacity: config.style.effectOpacity,
                    usesDarkFade: config.style.usesDarkFade,
                    borderColor: nil,
                    borderWidth: 0
                )
            } else {
                regular.style = config.style.nsGlassStyle
                regular.cornerRadius = config.shape.cornerRadius
                regular.tintColor = nil
            }
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
