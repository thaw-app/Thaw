//
//  MenuBarSectionName.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The name of a menu bar section.
///
/// Extracted from MenuBarSection.Name so the private hard-path package can
/// reference section identity without depending on the (app-only) MenuBarSection
/// class itself. Thaw.MenuBarSection.Name becomes a typealias to this type.
public enum MenuBarSectionName: String, CaseIterable, Codable, Sendable {
    case visible
    case hidden
    case alwaysHidden

    public var displayString: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }

    public var logString: String {
        switch self {
        case .visible: "visible section"
        case .hidden: "hidden section"
        case .alwaysHidden: "always-hidden section"
        }
    }
}
