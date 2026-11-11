//
//  SettingsNavigationIdentifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, @MainActor NavigationIdentifier {
    case general = "General"
    case menuBarLayout = "Menu Bar Layout"
    case visibility = "Visibility"
    case thawBar = "Thaw Bar"
    case displays = "Displays"
    case menuBarAppearance = "Menu Bar Appearance"
    case hotkeys = "Hotkeys"
    case profiles = "Profiles"
    case triggers = "Triggers"
    case scripts = "Scripts"
    case widgets = "Widgets"
    case tools = "Tools"
    case modules = "Modules"
    case privacy = "Privacy"
    case about = "About"

    /// Reads a pane name from storage, a link or the settings process. The
    /// retired pages open where their settings went.
    init?(storedValue: String) {
        switch storedValue {
        case "Spaces": self = .displays
        case "Automation": self = .triggers
        case "The Lab": self = .general
        case "Advanced": self = .menuBarLayout
        default: self.init(rawValue: storedValue)
        }
    }

    var localized: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .menuBarLayout: "Layout"
        case .visibility: "Visibility"
        case .thawBar: "\(Constants.displayName) Bar"
        case .displays: "Displays"
        case .menuBarAppearance: "Appearance"
        case .hotkeys: "Shortcuts"
        case .profiles: "Profiles"
        // Raw value stays "Automation" for thaw:// compatibility.
        case .triggers: "Triggers"
        case .scripts: "Scripts"
        case .widgets: "Widgets"
        case .tools: "Troubleshooting"
        case .modules: "Modules"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// One line under the pane's title in the toolbar saying what the pane
    /// is for, so the pane needs no description of its own.
    var subtitle: LocalizedStringResource {
        switch self {
        case .general: "Startup, language and icon"
        case .menuBarLayout: "Visible, Hidden and Always Hidden"
        case .visibility: "How hidden items appear"
        case .thawBar: "Hidden items below the menu bar"
        case .displays: "Each display and Space"
        case .menuBarAppearance: "Colour, shape and borders"
        case .hotkeys: "Keyboard shortcuts"
        case .profiles: "Saved layouts to switch between"
        case .triggers: "Show items when an app runs or an icon changes"
        case .scripts: "Run scripts before and after a profile switches"
        case .widgets: "The widget icon and \(Constants.displayName)'s panel"
        case .tools: "Logs, backups and resets"
        case .modules: "Optional parts that run on their own"
        case .privacy: "Permissions and access"
        case .about: "Version, updates and credits"
        }
    }

    var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .visibility: .systemSymbol("eye")
        case .thawBar: .systemSymbol("rectangle.stack")
        case .displays: .systemSymbol("display")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .profiles: .systemSymbol("person.crop.rectangle.stack")
        case .triggers: .systemSymbol("app.connected.to.app.below.fill")
        case .scripts: .systemSymbol("curlybraces")
        case .widgets: .systemSymbol("square.grid.2x2")
        case .tools: .systemSymbol("wrench.and.screwdriver")
        case .modules: .systemSymbol("puzzlepiece.extension")
        case .privacy: .systemSymbol("hand.raised")
        case .about: .systemSymbol("cube")
        }
    }
}

extension SettingsNavigationIdentifier {
    /// The hue of the pane's icon tile: one cool blue per sidebar family (see
    /// SettingsSidebarPanes), gray for housekeeping panes.
    var tileColor: Color {
        switch self {
        case .menuBarLayout, .visibility, .thawBar, .menuBarAppearance, .displays: .blue
        case .general, .hotkeys, .profiles, .privacy: .teal
        case .triggers, .scripts, .widgets, .modules: .indigo
        case .tools, .about: .gray
        }
    }
}

// MARK: - SettingsPaneIconTile

/// System Settings-style icon tile: a small continuous-corner square filled
/// with the pane's hue behind a white glyph.
struct SettingsPaneIconTile: View {
    let identifier: SettingsNavigationIdentifier
    var side: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(identifier.tileColor.gradient)
            .frame(width: side, height: side)
            .overlay {
                // Resizable + scaled-to-fit inside a fixed inset box, not
                // font-sized: SF Symbol intrinsic proportions vary per glyph,
                // and font sizing lets wide or tall symbols overflow the tile.
                identifier.iconResource.image
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: side * 0.58, height: side * 0.58)
            }
    }
}
