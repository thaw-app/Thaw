//
//  ThawWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - ThawWindowConfiguration

/// Shared AppKit configuration for Thaw's managed windows.
@MainActor
enum ThawWindowConfiguration {
    /// Applies shared non-restorable, active-space, non-tabbed window behavior.
    static func configureCommon(_ window: NSWindow, id: ThawWindowIdentifier) {
        window.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        window.title = id.titleString
        // None of Thaw's windows is a workspace; the green button zooms.
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenNone])
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
    }

    /// Applies the shared UI zoom and glass button shape modifiers to a window's root content.
    static func configuredContent(_ content: some View) -> some View {
        content
            .modifier(AppUIZoomModifier())
            // Glass buttons are capsules, as in macOS's own glass windows.
            .buttonBorderShape(.capsule)
    }
}

// MARK: - ThawWindowIdentifier

/// Custom identifier constants used to create Thaw's windows.
enum ThawWindowIdentifier: String, CustomStringConvertible {
    /// The identifier for Thaw's main settings window.
    case settings = "SettingsWindow"

    /// The identifier for Thaw's permissions window.
    case permissions = "PermissionsWindow"

    case whatsNew = "WhatsNewWindow"
    case acknowledgements = "AcknowledgementsWindow"

    /// The non-localized title of the corresponding window.
    var titleString: String {
        switch self {
        case .settings: "\(Constants.displayName)"
        case .permissions: String(localized: "Permissions")
        case .whatsNew: String(localized: "What’s New")
        case .acknowledgements: String(localized: "Acknowledgements")
        }
    }

    /// A textual representation of the identifier.
    var description: String {
        rawValue
    }
}
