//
//  MenuBarItemContainer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The tint a MenuBarItemContainer draws over its background, for a
/// surface that has been given its own instead of the menu bar's.
nonisolated struct MenuBarContainerTint: Hashable {
    var kind: MenuBarTintKind
    var color: CGColor
    var gradient: IceGradient
    var opacity: Double
    /// Draws the tint under the content instead of over it, so a strong
    /// tint colors the background without hiding the items.
    var isBehindContent = false
}

@MainActor
extension MenuBarContainerTint {
    /// The single color the tint draws, or nil when it draws none.
    var fillColor: CGColor? {
        switch kind {
        case .solid: color
        case .gradient: gradient.averageColor()
        case .noTint, .glass, .adaptive, .adaptiveGradient: nil
        }
    }

    /// The color that results from drawing the tint at its opacity over base.
    func composited(over base: CGColor) -> CGColor {
        guard let top = fillColor?.sRGBComponents, let bottom = base.sRGBComponents else {
            return base
        }
        let alpha = (top[3] * CGFloat(opacity)).clamped(to: 0 ... 1)
        func mix(_ index: Int) -> CGFloat {
            bottom[index] + (top[index] - bottom[index]) * alpha
        }
        return CGColor(srgbRed: mix(0), green: mix(1), blue: mix(2), alpha: bottom[3])
    }

    /// The color info of what the content sits on: the sampled color, with
    /// the tint mixed in when the tint is drawn behind the content.
    func backgroundColorInfo(over colorInfo: MenuBarAverageColorInfo?) -> MenuBarAverageColorInfo? {
        guard isBehindContent, let colorInfo else {
            return colorInfo
        }
        return MenuBarAverageColorInfo(color: composited(over: colorInfo.color), source: colorInfo.source)
    }
}

private extension CGColor {
    /// Red, green, blue and alpha in sRGB, or nil when the color can't be converted.
    var sRGBComponents: [CGFloat]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let components = converted(to: space, intent: .defaultIntent, options: nil)?.components
        return components?.count == 4 ? components : nil
    }
}

/// A view that is drawn in the style of the menu bar.
///
/// This view performs drawing on layers above and
/// below the content view. The resulting view will probably look
/// incorrect if the content view's background is not transparent.
struct MenuBarItemContainer<Content: View>: View {
    enum ColorInfoAccessor {
        case automatic
        case manual(MenuBarAverageColorInfo?)
    }

    private var appState: AppState
    private var appearanceManager: MenuBarAppearanceManager
    private var menuBarManager: MenuBarManager

    private let accessor: ColorInfoAccessor
    private let screen: NSScreen?
    private let tintOverride: MenuBarContainerTint?
    private let content: Content

    private var colorInfo: MenuBarAverageColorInfo? {
        switch accessor {
        case .automatic:
            menuBarManager.averageColorInfo
        case let .manual(colorInfo):
            colorInfo
        }
    }

    private var foreground: Color {
        tint.backgroundColorInfo(over: colorInfo)?.isBright(for: screen) == true ? .black : .white
    }

    private var configuration: MenuBarAppearancePartialConfiguration {
        appearanceManager.configuration.current
    }

    /// The tint to draw, from the override if one was given.
    ///
    /// Without an override, keep the original hardcoded opacity rather than the
    /// menu bar's tintOpacity.
    private var tint: MenuBarContainerTint {
        tintOverride ?? MenuBarContainerTint(
            kind: configuration.tintKind,
            color: configuration.tintColor,
            gradient: configuration.tintGradient,
            opacity: ThawBarAppearance.inheritedTintOpacity
        )
    }

    init(
        appState: AppState,
        accessor: ColorInfoAccessor,
        screen: NSScreen? = nil,
        tintOverride: MenuBarContainerTint? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.appState = appState
        self.appearanceManager = appState.appearanceManager
        self.menuBarManager = appState.menuBarManager
        self.accessor = accessor
        self.screen = screen
        self.tintOverride = tintOverride
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(foreground)
            .background {
                contentBackground
                if tint.isBehindContent {
                    tintLayer
                }
            }
            .overlay {
                if !tint.isBehindContent {
                    tintLayer
                }
            }
    }

    private var tintLayer: some View {
        tintFill
            .opacity(tint.opacity)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var contentBackground: some View {
        if let colorInfo {
            // Trust sampled color when available - it reflects the actual
            // space where the window is displayed.
            Color(cgColor: colorInfo.color)
        } else if appState.activeSpace.isFullscreen {
            Color.black
        } else {
            Color.defaultLayoutBar
        }
    }

    @ViewBuilder
    private var tintFill: some View {
        // Show tint when we have sampled color info (window on non-fullscreen space)
        // or when activeSpace is not fullscreen.
        if colorInfo != nil || !appState.activeSpace.isFullscreen, let fillColor = tint.fillColor {
            Color(cgColor: fillColor)
        }
    }
}

extension View {
    /// Draws the view in the style of the menu bar.
    ///
    /// This modifier performs drawing on layers above and
    /// below the current view. The resulting view will probably look
    /// incorrect if the current view's background is not transparent.
    func menuBarItemContainer(appState: AppState) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .automatic) { self }
    }

    /// Draws the view in the style of the menu bar.
    ///
    /// This modifier ignores the MenuBarManager/averageColorInfo
    /// property, and instead uses the provided color information.
    ///
    /// This modifier performs drawing on layers above and
    /// below the current view. The resulting view will probably look
    /// incorrect if the current view's background is not transparent.
    ///
    /// appState: The shared AppState object.
    /// colorInfo: Information for the average color of the menu bar.
    /// screen: The screen where the container is displayed, used to determine
    /// the appropriate brightness threshold for notched displays.
    /// tintOverride: A tint to draw in place of the menu bar's. Pass nil
    /// to follow the menu bar.
    func menuBarItemContainer(
        appState: AppState,
        colorInfo: MenuBarAverageColorInfo?,
        screen: NSScreen? = nil,
        tintOverride: MenuBarContainerTint? = nil
    ) -> some View {
        MenuBarItemContainer(
            appState: appState,
            accessor: .manual(colorInfo),
            screen: screen,
            tintOverride: tintOverride
        ) { self }
    }
}
