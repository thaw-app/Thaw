//
//  ControlItemIdentifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Raw identifiers for the control items that mark section boundaries.
/// Lives here so MenuBarItemTag does not depend on the app-only ControlItem.
public enum ControlItemIdentifier: String, CaseIterable, Sendable {
    case visible = "Thaw.ControlItem.Visible"
    case hidden = "Thaw.ControlItem.Hidden"
    case alwaysHidden = "Thaw.ControlItem.AlwaysHidden"

    /// Prefix of every control-item autosave name, spacers included. Marks a
    /// preference key as a Thaw control item whichever owner registered it.
    public static let autosavePrefix = "Thaw.ControlItem."

    public var tag: MenuBarItemTag {
        switch self {
        case .visible: .visibleControlItem
        case .hidden: .hiddenControlItem
        case .alwaysHidden: .alwaysHiddenControlItem
        }
    }
}
