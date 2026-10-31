//
//  ThawTheme.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import SwiftUI

/// Where an app's shared controls differ from the default, set once on each window's root with thawTheme(_:).
/// A window without it looks like Thaw. The accent colour itself comes from the app's asset catalog.
public struct ThawTheme: Equatable, Sendable {
    /// The fill of a selected row: ThawSidebar's, and selectedRowBackground's.
    public var selection: ThawSidebarColors.Selection
    /// The wash under the pointer on a search result.
    public var hoverTint: Color

    public init(
        selection: ThawSidebarColors.Selection = .tinted(.accentColor),
        hoverTint: Color = .accentColor
    ) {
        self.selection = selection
        self.hoverTint = hoverTint
    }
}

extension EnvironmentValues {
    @Entry public var thawTheme = ThawTheme()
}

public extension View {
    /// Sets the theme for this view and the shared controls in it. A window hosted from AppKit starts with a new
    /// environment, so it goes on each hosting root.
    func thawTheme(_ theme: ThawTheme) -> some View {
        environment(\.thawTheme, theme)
    }
}
