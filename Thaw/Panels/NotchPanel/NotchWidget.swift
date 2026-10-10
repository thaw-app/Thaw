//
//  NotchWidget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI

/// How often a widget's data source may refresh.
nonisolated enum NotchWidgetRefreshPolicy {
    case onDemand
    case whileRevealed
}

/// Match the hovered item, not the panel; unmatched items have no descender.
/// AnyView allows a heterogeneous registry of matchers, views, and data sources.
@MainActor
protocol NotchWidget: AnyObject {
    var id: String { get }

    func matches(_ item: MenuBarItem) -> Bool

    /// Binds the item before isAvailable or view construction.
    func prepare(for item: MenuBarItem)

    /// Availability for the last prepared item, checked only while the pointer is on it.
    func isAvailable() -> Bool

    /// Body size excludes attachment shoulders; each widget chooses its own geometry.
    var bodySize: CGSize { get }

    @ViewBuilder var body: AnyView { get }

    var refreshPolicy: NotchWidgetRefreshPolicy { get }

    /// Called before revealing the descender and after any widget command.
    func refresh()
}

extension NotchWidget {
    func prepare(for _: MenuBarItem) {}
}

// MARK: - NotchWidgetRegistry

/// Registry order is precedence: app integrations precede the catch-all accessibility reader.
@MainActor
final class NotchWidgetRegistry {
    private let widgets: [any NotchWidget]

    init(widgets: [any NotchWidget]) {
        self.widgets = widgets
    }

    /// Returns the first matching, available widget, or nil.
    func widget(for item: MenuBarItem) -> (any NotchWidget)? {
        for widget in widgets where widget.matches(item) {
            widget.prepare(for: item)
            if widget.isAvailable() {
                return widget
            }
        }
        return nil
    }
}
