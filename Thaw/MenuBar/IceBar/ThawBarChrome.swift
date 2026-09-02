//
//  ThawBarChrome.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Draws the Thaw Bar's background fill, tint overlay, clip, and border from
/// a ``ThawBarAppearancePartialConfiguration``.
///
/// Replaces the shared ``MenuBarItemContainer`` path for the Thaw Bar so its
/// fill and tint are independent of the menu bar overlay settings.
///
/// ``ThawBarBackgroundKind/adaptive`` ("Match Menu Bar") paints the live
/// average of the menu bar / wallpaper strip from ``IceBarColorManager``,
/// with optional brightness and liquid-glass blend from the appearance editor.
struct ThawBarChrome<Content: View>: View {
    let configuration: ThawBarAppearancePartialConfiguration
    let colorInfo: MenuBarAverageColorInfo?
    let contentHeight: CGFloat
    let screen: NSScreen
    let content: Content

    init(
        configuration: ThawBarAppearancePartialConfiguration,
        colorInfo: MenuBarAverageColorInfo?,
        contentHeight: CGFloat,
        screen: NSScreen,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.colorInfo = colorInfo
        self.contentHeight = contentHeight
        self.screen = screen
        self.content = content()
    }

    private var cornerRadius: CGFloat {
        configuration.cornerRadius(contentHeight: contentHeight)
    }

    private var clipShape: RoundedRectangle {
        if configuration.cornerStyle.isFullyRounded {
            RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        }
    }

    private var prefersDarkForeground: Bool {
        configuration.prefersDarkForeground(
            sampledColor: colorInfo?.color,
            sampledBrightness: colorInfo?.brightness,
            screenHasNotch: screen.hasNotch
        )
    }

    var body: some View {
        ZStack {
            content
                .foregroundStyle(prefersDarkForeground ? Color.black : Color.white)
                .background {
                    fillLayer
                }
                .overlay {
                    tintLayer
                }
                .clipShape(clipShape)
                .modifier(ThawBarGlassModifier(
                    isEnabled: configuration.appliesLiquidGlass,
                    style: glassStyle,
                    shape: clipShape
                ))

            if configuration.hasBorder {
                borderOverlay
            }
        }
    }

    private var glassStyle: MenuBarGlassStyle {
        switch configuration.backgroundKind {
        case .glass:
            configuration.backgroundGlassStyle
        case .adaptive:
            // Clear keeps more of the sampled fill visible under the glass blend.
            .clear
        case .solid, .gradient, .none, .sampled:
            configuration.backgroundGlassStyle
        }
    }

    @ViewBuilder
    private var fillLayer: some View {
        switch configuration.backgroundKind {
        case .adaptive:
            if let colorInfo {
                Color(cgColor: configuration.brightnessAdjustedSample(from: colorInfo.color))
                    .opacity(configuration.adaptiveFillOpacity)
            } else {
                Color.defaultLayoutBar
            }
        case .sampled:
            if let colorInfo {
                Color(cgColor: colorInfo.color)
                    .opacity(configuration.backgroundOpacity)
            } else {
                Color.defaultLayoutBar
            }
        case .solid:
            Color(cgColor: configuration.backgroundColor)
                .opacity(configuration.backgroundOpacity)
        case .gradient:
            configuration.backgroundGradient
                .withAlpha(configuration.backgroundOpacity)
                .swiftUIView(using: .displayP3)
        case .glass:
            Color.clear
        case .none:
            Color.clear
        }
    }

    @ViewBuilder
    private var tintLayer: some View {
        switch configuration.tintKind {
        case .noTint, .glass:
            EmptyView()
        case .solid:
            Color(cgColor: configuration.tintColor)
                .opacity(configuration.tintOpacity)
                .allowsHitTesting(false)
        case .gradient:
            configuration.tintGradient
                .withAlpha(configuration.tintOpacity)
                .swiftUIView(using: .displayP3)
                .allowsHitTesting(false)
        case .adaptive:
            if let colorInfo {
                Color(cgColor: colorInfo.color)
                    .opacity(configuration.tintOpacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var borderOverlay: some View {
        ThawBarBorderShape(
            cornerRadius: cornerRadius,
            cornerStyle: configuration.cornerStyle.isFullyRounded ? .circular : .continuous,
            omitTopEdge: configuration.shouldOmitTopBorder,
            inset: configuration.borderWidth / 2
        )
        .stroke(
            Color(cgColor: configuration.borderColor),
            lineWidth: configuration.borderWidth
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Glass modifier

/// Applies SwiftUI liquid glass when the Thaw Bar background opts into glass.
private struct ThawBarGlassModifier<S: InsettableShape>: ViewModifier {
    let isEnabled: Bool
    let style: MenuBarGlassStyle
    let shape: S

    func body(content: Content) -> some View {
        if isEnabled {
            switch style {
            case .regular:
                content.glassEffect(.regular, in: shape)
            case .clear:
                content.glassEffect(.clear, in: shape)
            }
        } else {
            content
        }
    }
}
