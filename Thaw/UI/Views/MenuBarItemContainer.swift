//
//  MenuBarItemContainer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The tint a ``MenuBarItemContainer`` draws over its background, for a
/// surface that has been given its own instead of the menu bar's.
nonisolated struct MenuBarContainerTint: Hashable {
    var kind: MenuBarTintKind
    var color: CGColor
    var gradient: IceGradient
    var opacity: Double
}

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
        colorInfo?.isBright(for: screen) == true ? .black : .white
    }

    private var configuration: MenuBarAppearancePartialConfiguration {
        appearanceManager.configuration.current
    }

    /// The tint to draw, from the override if one was given.
    ///
    /// The fallback opacity is the one this view has hardcoded since it was
    /// written, so callers that pass no override keep drawing exactly as
    /// before rather than picking up the menu bar's `tintOpacity`.
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
            }
            .overlay {
                contentOverlay
                    .opacity(tint.opacity)
                    .allowsHitTesting(false)
            }
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
    private var contentOverlay: some View {
        // Show tint when we have sampled color info (window on non-fullscreen space)
        // or when activeSpace is not fullscreen.
        if colorInfo != nil || !appState.activeSpace.isFullscreen {
            if case .solid = tint.kind {
                Color(cgColor: tint.color)
            } else if
                case .gradient = tint.kind,
                let color = tint.gradient.averageColor()
            {
                Color(cgColor: color)
            }
        }
    }
}

extension View {
    /// Draws the view in the style of the menu bar.
    ///
    /// - Important: This modifier performs drawing on layers above and
    ///   below the current view. The resulting view will probably look
    ///   incorrect if the current view's background is not transparent.
    ///
    /// - Parameter appState: The shared ``AppState`` object.
    func menuBarItemContainer(appState: AppState) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .automatic) { self }
    }

    /// Draws the view in the style of the menu bar.
    ///
    /// This modifier ignores the ``MenuBarManager/averageColorInfo``
    /// property, and instead uses the provided color information.
    ///
    /// - Important: This modifier performs drawing on layers above and
    ///   below the current view. The resulting view will probably look
    ///   incorrect if the current view's background is not transparent.
    ///
    /// - Parameters:
    ///   - appState: The shared ``AppState`` object.
    ///   - colorInfo: Information for the average color of the menu bar.
    ///   - screen: The screen where the container is displayed, used to determine
    ///     the appropriate brightness threshold for notched displays.
    ///   - tintOverride: A tint to draw in place of the menu bar's. Pass `nil`
    ///     to follow the menu bar.
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
