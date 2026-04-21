//
//  MenuBarItemContainer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
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

    @ObservedObject private var appState: AppState
    @ObservedObject private var appearanceManager: MenuBarAppearanceManager
    @ObservedObject private var menuBarManager: MenuBarManager

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
        colorInfo?.isBright(for: screen) == true ? .black : .white
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
            }
            .overlay {
                contentOverlay
                    .opacity(0.2)
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
            if case .solid = configuration.tintKind {
                Color(cgColor: configuration.tintColor)
            } else if
                case .gradient = configuration.tintKind,
                let color = configuration.tintGradient.averageColor()
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
    func menuBarItemContainer(appState: AppState, colorInfo: MenuBarAverageColorInfo?, screen: NSScreen? = nil) -> some View {
        MenuBarItemContainer(appState: appState, accessor: .manual(colorInfo), screen: screen) { self }
    }
}
