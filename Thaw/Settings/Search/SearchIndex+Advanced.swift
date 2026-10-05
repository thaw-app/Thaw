//
//  SearchIndex+Advanced.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Advanced Settings

    static let advancedEntries: [SearchEntry] = [
        SearchEntry(
            id: "lab.enableMenuBarItemDescenders",
            title: "Show item details on hover",
            descriptionText: String(localized: "Hangs a small readout below a menu bar item while the pointer rests on it."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["hover", "details", "readout", "descender", "notch", "tooltip", "weather"],
            property: .advanced("enableMenuBarItemDescenders")
        ),
        SearchEntry(
            id: "lab.zenModeWhileRecording",
            title: "Collapse the menu bar while recording",
            descriptionText: String(localized: "Enters Zen Mode while the camera or microphone is in use, then restores the bar when recording stops."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["presenter", "presentation", "recording", "screen", "capture", "zen", "collapse", "hide", "camera", "microphone", "call", "meeting", "clean"],
            property: .advanced("zenModeWhileRecording")
        ),
        SearchEntry(
            id: "lab.enableRecordingWatch",
            title: "Camera and microphone watch",
            descriptionText: String(localized: "Names the app that just took the microphone, and says when a camera turns on."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["camera", "microphone", "mic", "privacy", "indicator", "recording", "watch", "dot", "spy", "webcam"],
            property: .advanced("enableRecordingWatch")
        ),
        SearchEntry(
            id: "lab.enableModuleStandIns",
            title: "Replace Control Center items while hidden",
            descriptionText: String(localized: "Puts Thaw icons in place of Focus, AirDrop, Now Playing and Fast User Switching while they sit in Hidden."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["focus", "do not disturb", "dnd", "moon", "airdrop", "now playing", "music", "user", "fast user switching", "menu extra", "system item", "replace", "stand-in"],
            property: .advanced("enableModuleStandIns")
        ),
        SearchEntry(
            id: "lab.enableTimeMachineTakeover",
            title: "Replace Time Machine",
            descriptionText: String(localized: "Removes Apple's Time Machine icon, which cannot be hidden, and puts a Thaw icon you can hide in its place."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["time machine", "backup", "menu extra", "system item", "replace", "stand-in", "timemachine"],
            property: .advanced("enableTimeMachineTakeover")
        ),
        SearchEntry(
            id: "lab.enableTextInputTakeover",
            title: "Replace Input Menu",
            descriptionText: String(localized: "Removes Apple's Input menu and puts a Thaw icon you can hide in its place, with the same input sources."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["input menu", "text input", "keyboard", "input source", "language", "layout", "menu extra", "system item", "replace", "stand-in"],
            property: .advanced("enableTextInputTakeover")
        ),
        SearchEntry(
            id: "lab.recordingWatchScreen",
            title: "Recording announcement screen",
            descriptionText: String(localized: "Chooses which display shows the banner when an app takes the microphone or the camera."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["camera", "microphone", "recording", "announcement", "screen", "display", "banner", "hud", "where", "monitor", "privacy"],
            property: .advanced("recordingWatchScreen")
        ),
        SearchEntry(
            id: "lab.recordingWatchPlacement",
            title: "Place announcements",
            descriptionText: String(localized: "Chooses where along the top of the display the recording banners sit."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["camera", "microphone", "recording", "announcement", "banner", "placement", "corner", "center", "hud", "where"],
            property: .advanced("recordingWatchPlacement")
        ),
        SearchEntry(
            id: "lab.enableDesktopMenuHiding",
            title: "Hide Finder menus on the desktop",
            descriptionText: String(localized: "Covers the Finder's menu titles while the desktop is frontmost. The Apple menu stays."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["finder", "desktop", "menus", "menu titles", "hide", "app menus", "cover", "clean"],
            property: .advanced("enableDesktopMenuHiding")
        ),
        SearchEntry(
            id: "lab.enableControlItemPanel",
            title: "Panel instead of the status menu",
            descriptionText: String(localized: "Right-click \(Constants.displayName)’s icon to get a panel of controls instead of a menu of text."),
            pane: .theLab,
            section: "Experiments",
            keywords: ["panel", "status menu", "menu", "right-click", "icon", "controls", "sections", "zen", "profile", "swap"],
            property: .advanced("enableControlItemPanel")
        ),
        SearchEntry(
            id: "general.menuBarSearchPresentation",
            title: "Where the search panel opens",
            descriptionText: String(localized: "Open the search panel where you left it, centered like Spotlight, or at the pointer in large type."),
            pane: .visibility,
            section: "Menu bar search",
            keywords: [
                "search", "panel", "open", "position", "placement", "centered", "center", "spotlight",
                "launcher", "palette", "pointer", "cursor", "large text", "accessibility", "low vision",
                "big", "reach",
            ],
            property: .advanced("menuBarSearchPresentation")
        ),
        SearchEntry(
            id: "general.searchSectionOrder",
            title: "Search section ordering",
            descriptionText: String(localized: "Choose which menu bar sections appear in the search panel, and in what order."),
            pane: .visibility,
            section: "Menu bar search",
            keywords: ["search", "section", "order", "panel", "reorder"],
            property: .advanced("searchSectionOrder")
        ),
        SearchEntry(
            id: "general.searchIncludeVisible",
            title: "Include visible section in search",
            descriptionText: nil,
            pane: .visibility,
            section: "Menu bar search",
            keywords: ["search", "visible", "include", "section"],
            property: .advanced("searchIncludeVisible")
        ),
        SearchEntry(
            id: "general.searchIncludeHidden",
            title: "Include hidden section in search",
            descriptionText: nil,
            pane: .visibility,
            section: "Menu bar search",
            keywords: ["search", "hidden", "include", "section"],
            property: .advanced("searchIncludeHidden")
        ),
        SearchEntry(
            id: "general.searchIncludeAlwaysHidden",
            title: "Include Always Hidden in search",
            descriptionText: nil,
            pane: .visibility,
            section: "Menu bar search",
            keywords: ["search", "always hidden", "include", "section"],
            property: .advanced("searchIncludeAlwaysHidden")
        ),
        SearchEntry(
            id: "general.showMenuBarTooltips",
            title: "Show tooltips in the menu bar",
            descriptionText: String(localized: "Show a tooltip when hovering over menu bar items in the actual menu bar."),
            pane: .visibility,
            section: "Tooltips",
            keywords: ["tooltip", "hover", "menu bar"],
            property: .advanced("showMenuBarTooltips")
        ),
        SearchEntry(
            id: "advanced.autoZenWhileSharingScreen",
            title: "Enter Zen Mode while presenting",
            descriptionText: String(localized: "Hides your Hidden and Always Hidden items while a display is mirrored or your screen is shared, then brings them back."),
            pane: .automation,
            section: "Presentation",
            keywords: ["zen", "presenting", "present", "share", "sharing", "mirror", "screen", "projector", "meeting"],
            property: .advanced("autoZenWhileSharingScreen")
        ),
        SearchEntry(
            id: "automation.menuBarItemAlertReveals",
            title: "Reveal on icon change",
            descriptionText: String(localized: "Briefly shows a hidden item in the menu bar when its icon changes, so you see its alert."),
            pane: .automation,
            section: "Reveal on icon change",
            keywords: ["reveal", "alert", "icon", "change", "badge", "notification", "hidden", "temporarily"],
            property: nil
        ),
        SearchEntry(
            id: "automation.menuBarItemAlertRevealCooldown",
            title: "Reveal cooldown",
            descriptionText: String(localized: "Minimum wait before the same item can reveal itself again. Stops an icon that animates nonstop from bouncing in and out of the menu bar."),
            pane: .automation,
            section: "Reveal on icon change",
            keywords: ["reveal", "cooldown", "alert", "icon", "throttle", "seconds"],
            property: .advanced("menuBarItemAlertRevealCooldown")
        ),
        SearchEntry(
            id: "advanced.enableMenuBarItemOverflow",
            title: "Move items that don’t fit into Hidden",
            descriptionText: String(localized: "When the menu bar is full, move the Visible items that don’t fit into Hidden, so they stay reachable instead of going behind macOS’s » button."),
            pane: .menuBarLayout,
            section: "More layout options",
            keywords: ["overflow", "notch", "fit", "visible", "hidden", "advanced layout controls"],
            property: .advanced("enableMenuBarItemOverflow")
        ),
        SearchEntry(
            id: "advanced.hideApplicationMenus",
            title: "Hide app menus when showing menu bar items",
            descriptionText: String(localized: "Make more room in the menu bar by hiding the current app menus if needed."),
            pane: .general,
            section: "Menu bar behavior",
            keywords: ["app menus", "hide", "application", "menu bar"],
            property: .advanced("hideApplicationMenus")
        ),
        SearchEntry(
            id: "advanced.enableSecondaryContextMenu",
            titleKey: "Right-click the menu bar for the \(Constants.displayName) menu",
            titleText: "Right-click the menu bar for the \(Constants.displayName) menu",
            descriptionText: String(localized: "Right-click in an empty area of the menu bar to display a minimal version of \(Constants.displayName)'s menu."),
            pane: .general,
            sectionKey: "Menu bar behavior",
            sectionText: "Menu bar behavior",
            keywords: ["context menu", "right click", "right-click", "secondary", "secondary context menu"],
            property: .advanced("enableSecondaryContextMenu")
        ),
        SearchEntry(
            id: "advanced.enableNativeAppHiding",
            title: "Show Live Activities and the camera indicator",
            descriptionText: String(localized: "Keeps Live Activities and the camera indicator on the menu bar while apps are hidden, and stops hidden items from flashing when Notification Center opens."),
            pane: .general,
            section: "Menu bar behavior",
            keywords: ["live activities", "camera", "microphone", "indicator", "native", "hiding", "beta", "notification center"],
            property: .advanced("enableNativeAppHiding")
        ),
        SearchEntry(
            id: "general.appLanguage",
            title: "App language",
            descriptionText: String(localized: "Use the app in a different language than the system."),
            pane: .general,
            keywords: ["language", "locale", "translation", "localization", "override"],
            property: nil
        ),
    ]
}
