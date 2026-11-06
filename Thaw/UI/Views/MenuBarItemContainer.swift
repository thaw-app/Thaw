//
//  MenuBarItemContainer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A view that is drawn in the style of the menu bar.
///
/// - Important: This view performs drawing on layers above and
///   below the content view. The resulting view will probably look
///   incorrect if the content view's background is not transparent.
struct MenuBarItemContainer<Content: View>: View {
    enum ColorInfoAccessor {
        case automatic
        case manual(MenuBarAverageColorInfo?)
    }

    private let appState: AppState
    private let appearanceManager: MenuBarAppearanceManager
    private let menuBarManager: MenuBarManager

    private let accessor: ColorInfoAccessor
    private let screen: NSScreen?
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
        MenuBarStyleTint.prefersDarkInk(colorInfo, tintedBy: configuration, screen: screen) ? .black : .white
    }

    /// The flat color of the appearance tint, or nil when none is painted.
    private var tintColor: CGColor? {
        // Tinted when there is sampled color info (window on a non-fullscreen
        // space), or when activeSpace is not fullscreen.
        guard colorInfo != nil || !appState.activeSpace.isFullscreen else {
            return nil
        }
        return MenuBarStyleTint.color(for: configuration)
    }

    private var configuration: MenuBarAppearancePartialConfiguration {
        appearanceManager.configuration.current
    }

    init(appState: AppState, accessor: ColorInfoAccessor, screen: NSScreen? = nil, @ViewBuilder content: () -> Content) {
        self.appState = appState
        self.appearanceManager = appState.appearanceManager
        self.menuBarManager = appState.menuBarManager
        self.accessor = accessor
        self.screen = screen
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(foreground)
            .background {
                contentBackground
                    // Under the content, not over it: the tint panel on the
                    // real menu bar sits below the status window, so the real
                    // items are never washed by it either. Over the content it
                    // muted the same glyphs whose color it was excluded from
                    // deciding.
                    .overlay {
                        contentTint
                            .opacity(MenuBarStyleTint.opacity)
                            .allowsHitTesting(false)
                    }
            }
    }

    @ViewBuilder
    private var contentBackground: some View {
        if let colorInfo {
            // Trust sampled color when available: it reflects the actual
            // space where the window is displayed.
            Color(cgColor: colorInfo.color)
        } else if appState.activeSpace.isFullscreen {
            Color.black
        } else {
            Color.defaultLayoutBar
        }
    }

    @ViewBuilder
    private var contentTint: some View {
        if let tintColor {
            Color(cgColor: tintColor)
        }
    }
}

// MARK: - MenuBarStyleTint

/// The appearance tint a menu-bar-styled surface paints, and the background it
/// leaves the content standing on.
///
/// MenuBarItemContainer paints the tint. Views hosted inside one that pick
/// their own colors (the layout bar draws its item glyphs with AppKit) have
/// to judge the same background it does, or the two disagree wherever the tint
/// is strong enough to move the decision. Twenty percent of black over a
/// #808080 bar lands on #666666, which is on the other side of the switch.
enum MenuBarStyleTint {
    /// Opacity the tint is painted at in a menu-bar-styled surface.
    ///
    /// The real bar draws its tint at the configured tintOpacity; the
    /// replicas have always drawn theirs at the default, which this is.
    static let opacity = 0.2

    /// The flat color of the tint configuration paints, or nil when it
    /// paints none here.
    ///
    /// A gradient flattens to its average, which is what the replicas draw.
    /// The wallpaper-derived kinds need a palette the replicas do not carry,
    /// so they go untinted and are reported as such.
    ///
    /// - Parameter configuration: The appearance in effect.
    static func color(for configuration: MenuBarAppearancePartialConfiguration) -> CGColor? {
        switch configuration.tintKind {
        case .solid:
            configuration.tintColor
        case .gradient:
            configuration.tintGradient.averageColor()
        case .noTint, .glass, .adaptive, .adaptiveGradient:
            nil
        }
    }

    /// Whether content on a menu-bar-styled surface reads in black rather
    /// than white: the sample with the tint composited in, judged for
    /// brightness. The one ink rule every such surface uses.
    static func prefersDarkInk(
        _ colorInfo: MenuBarAverageColorInfo?,
        tintedBy configuration: MenuBarAppearancePartialConfiguration,
        screen: NSScreen?
    ) -> Bool {
        background(colorInfo, tintedBy: configuration)?.isBright(for: screen) == true
    }

    /// The live sample with the live tint composited in.
    @MainActor
    static func currentBackground(appState: AppState) -> MenuBarAverageColorInfo? {
        background(
            appState.menuBarManager.averageColorInfo,
            tintedBy: appState.appearanceManager.configuration.current
        )
    }

    /// The sampled bar color with that tint composited in, the background
    /// menu-bar-styled content is read against, rather than the bare sample.
    ///
    /// - Parameters:
    ///   - colorInfo: The sample taken from behind the menu bar.
    ///   - configuration: The appearance in effect.
    /// - Returns: The composited sample, or nil when there is no sample.
    static func background(
        _ colorInfo: MenuBarAverageColorInfo?,
        tintedBy configuration: MenuBarAppearancePartialConfiguration
    ) -> MenuBarAverageColorInfo? {
        guard let colorInfo else {
            return nil
        }
        guard let tint = color(for: configuration) else {
            return colorInfo
        }
        return colorInfo.tinted(by: tint, opacity: opacity)
    }
}

extension View {
    /// Draws the view in the style of the menu bar.
    ///
    /// - Important: This modifier performs drawing on layers above and
    ///   below the current view. The resulting view will probably look
    ///   incorrect if the current view's background is not transparent.
    ///
    /// - Parameter appState: The shared AppState object.
    func menuBarItemContainer(appState: AppState) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .automatic) { self }
    }

    /// Draws the view in the style of the menu bar.
    ///
    /// This modifier ignores the MenuBarManager.averageColorInfo
    /// property, and instead uses the provided color information.
    ///
    /// - Important: This modifier performs drawing on layers above and
    ///   below the current view. The resulting view will probably look
    ///   incorrect if the current view's background is not transparent.
    ///
    /// - Parameters:
    ///   - appState: The shared AppState object.
    ///   - colorInfo: Information for the average color of the menu bar.
    ///   - screen: The screen where the container is displayed, used to determine
    ///     the appropriate brightness threshold for notched displays.
    func menuBarItemContainer(appState: AppState, colorInfo: MenuBarAverageColorInfo?, screen: NSScreen? = nil) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .manual(colorInfo), screen: screen) { self }
    }
}
