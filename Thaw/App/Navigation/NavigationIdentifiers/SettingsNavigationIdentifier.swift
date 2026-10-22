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
    case spaces = "Spaces"
    case menuBarAppearance = "Menu Bar Appearance"
    case hotkeys = "Hotkeys"
    case profiles = "Profiles"
    case advanced = "Advanced"
    case automation = "Automation"
    case triggers = "Triggers"
    case scripts = "Scripts"
    case widgets = "Widgets"
    case theLab = "The Lab"
    case tools = "Tools"
    case modules = "Modules"
    case privacy = "Privacy"
    case about = "About"

    /// Where a pane opens. Spaces moved into Displays, Automation split into Triggers and Scripts,
    /// and Experiments emptied into General, Visibility and Widgets, so links and saved panes
    /// that name Spaces, Automation or Experiments land on Displays, Triggers or General.
    var destination: SettingsNavigationIdentifier {
        switch self {
        case .spaces: .displays
        case .automation: .triggers
        case .theLab: .general
        default: self
        }
    }

    var localized: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .menuBarLayout: "Layout"
        case .visibility: "Visibility"
        case .thawBar: "\(Constants.displayName) Bar"
        case .displays: "Displays"
        case .spaces: "Spaces"
        case .menuBarAppearance: "Appearance"
        case .hotkeys: "Shortcuts"
        case .profiles: "Profiles"
        case .advanced: "Advanced"
        // Raw value stays "Automation" for thaw:// compatibility.
        case .automation: "Automation"
        case .triggers: "Triggers"
        case .scripts: "Scripts"
        case .widgets: "Widgets"
        case .theLab: "Experiments"
        case .tools: "Troubleshooting"
        case .modules: "Modules"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// One line under the pane's title in the toolbar saying what the pane
    /// is for, so the pane needs no description of its own.
    var subtitle: LocalizedStringKey {
        switch self {
        case .general: "Startup, language and icon"
        case .menuBarLayout: "Shown, hidden and always hidden"
        case .visibility: "How hidden items appear"
        case .thawBar: "Hidden items below the menu bar"
        case .displays: "Each display and Space"
        case .spaces: "Layouts for each space"
        case .menuBarAppearance: "Colour, shape and borders"
        case .hotkeys: "Keyboard shortcuts"
        case .profiles: "Saved layouts to switch between"
        case .advanced: "Advanced options"
        case .automation: "Triggers and scripts"
        case .triggers: "Show items when an app runs or an icon changes"
        case .scripts: "Run scripts before and after a profile switches"
        case .widgets: "The widget icon and \(Constants.displayName)'s panel"
        case .theLab: "Features still in testing"
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
        case .spaces: .systemSymbol("square.on.square.dashed")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .profiles: .systemSymbol("person.crop.rectangle.stack")
        case .advanced: .systemSymbol("gearshape.2")
        case .automation: .systemSymbol("app.badge.checkmark")
        case .triggers: .systemSymbol("app.connected.to.app.below.fill")
        case .scripts: .systemSymbol("curlybraces")
        case .widgets: .systemSymbol("square.grid.2x2")
        case .theLab: .systemSymbol("flask")
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
        case .menuBarLayout, .visibility, .thawBar, .menuBarAppearance, .displays, .spaces: .blue
        case .general, .hotkeys, .profiles, .privacy: .teal
        case .automation, .triggers, .scripts, .widgets, .modules: .indigo
        case .theLab, .advanced, .tools, .about: .gray
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
