//
//  ThawSettingsShell.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import SwiftUI

/// The settings window's split view. The detail column names itself in the toolbar and fades its content under it.
/// Search goes on the shell with settingsSearchField; sidebarMaxWidth lets the sidebar be dragged out to that width.
public struct ThawSettingsShell<Sidebar: View, Detail: View, Toolbar: ToolbarContent>: View {
    private let title: Text
    private let subtitle: Text?
    private let sidebarMaxWidth: CGFloat?
    private let sidebar: Sidebar
    private let detail: Detail
    private let toolbar: Toolbar?

    public init(
        title: Text,
        subtitle: Text? = nil,
        sidebarMaxWidth: CGFloat? = nil,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail,
        @ToolbarContentBuilder toolbar: () -> Toolbar
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sidebarMaxWidth = sidebarMaxWidth
        self.sidebar = sidebar()
        self.detail = detail()
        self.toolbar = toolbar()
    }

    public var body: some View {
        NavigationSplitView {
            sidebarColumn
        } detail: {
            detailColumn
                // Content fades under the glass toolbar instead of stopping at a hard band.
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        let width = ThawSidebar<Never, EmptyView>.width
        if let sidebarMaxWidth {
            sidebar.navigationSplitViewColumnWidth(min: width, ideal: width, max: sidebarMaxWidth)
        } else {
            sidebar.navigationSplitViewColumnWidth(width)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        // Fill the column so a form's scrollbar sits on the window's trailing edge.
        let filled = detail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(title)
        if let subtitle {
            toolbarItems(on: filled.navigationSubtitle(subtitle))
        } else {
            toolbarItems(on: filled)
        }
    }

    /// No toolbar modifier at all without items, so an app with none gets only the system's own.
    @ViewBuilder
    private func toolbarItems(on content: some View) -> some View {
        if let toolbar {
            content.toolbar { toolbar }
        } else {
            content
        }
    }
}

public extension ThawSettingsShell where Toolbar == ToolbarItem<Void, EmptyView> {
    init(
        title: Text,
        subtitle: Text? = nil,
        sidebarMaxWidth: CGFloat? = nil,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sidebarMaxWidth = sidebarMaxWidth
        self.sidebar = sidebar()
        self.detail = detail()
        toolbar = nil
    }
}
