//
//  WindowInfo.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import OSLog

/// Information for a window.
struct WindowInfo {
    /// The window's identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the window.
    let ownerPID: pid_t

    /// The window's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The window's layer number.
    let layer: Int

    /// The window's title.
    let title: String?

    /// The name of the process that owns the window.
    ///
    /// This may have a value when ``owningApplication`` does not have
    /// a localized name.
    let ownerName: String?

    /// A Boolean value that indicates whether the window is on screen.
    let isOnScreen: Bool

    /// The application that owns the window.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// A Boolean value that indicates whether the window belongs to the
    /// window server.
    var isWindowServerWindow: Bool {
        ownerName == "Window Server"
    }

    /// A Boolean value that indicates whether the window is a menu-related window.
    ///
    /// This property returns `true` if the window's layer corresponds to a
    /// pop-up menu, status window, or main menu, or if it belongs to the
    /// Window Server (which often owns the actual menu windows for apps).
    var isMenuRelated: Bool {
        let level = CGWindowLevel(Int32(layer))
        return level == CGWindowLevelForKey(.popUpMenuWindow) ||
            level == CGWindowLevelForKey(.popUpMenuWindow) - 1 || // Some menus are slightly below
            level == CGWindowLevelForKey(.statusWindow) ||
            level == CGWindowLevelForKey(.mainMenuWindow) ||
            isWindowServerWindow
    }

    /// Creates a window with the given dictionary.
    private init?(dictionary: CFDictionary) {
        guard
            let info = dictionary as? [CFString: Any],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
            let boundsDict = info[kCGWindowBounds] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            let layer = info[kCGWindowLayer] as? Int
        else {
            return nil
        }
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        self.title = info[kCGWindowName] as? String
        self.ownerName = info[kCGWindowOwnerName] as? String
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }

    /// Creates a window with the given window identifier.
    ///
    /// - Parameter windowID: A window identifier.
    init?(windowID: CGWindowID) {
        guard let window = WindowInfo.createWindows(from: [windowID]).first else {
            return nil
        }
        self = window
    }

    /// Returns the current bounds of the window.
    func currentBounds() -> CGRect? {
        Bridging.getWindowBounds(for: windowID)
    }
}

// MARK: - Window List

extension WindowInfo {
    private static let diagLog = DiagLog(category: "WindowInfo")

    /// Creates a list of windows from the given list of window identifiers.
    ///
    /// - Parameter windowIDs: A list of window identifiers.
    static func createWindows(from windowIDs: [CGWindowID]) -> [WindowInfo] {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            diagLog.warning("createWindows: createCGWindowArray returned nil for \(windowIDs.count) window IDs")
            return []
        }
        guard let list = CGWindowListCreateDescriptionFromArray(array) as? [CFDictionary] else {
            diagLog.warning("createWindows: CGWindowListCreateDescriptionFromArray returned nil for \(windowIDs.count) window IDs")
            return []
        }
        let windows = list.compactMap { WindowInfo(dictionary: $0) }
        if windows.count != windowIDs.count {
            diagLog.debug("createWindows: \(windowIDs.count) IDs -> \(list.count) descriptions -> \(windows.count) WindowInfo objects (some may have failed init)")
        }
        return windows
    }

    /// Creates a list of windows using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func createWindows(option: Bridging.WindowListOption = []) -> [WindowInfo] {
        createWindows(from: Bridging.getWindowList(option: option))
    }

    /// Creates a list of windows for the elements in the menu bar
    /// using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func createMenuBarWindows(option: Bridging.MenuBarWindowListOption = []) -> [WindowInfo] {
        createWindows(from: Bridging.getMenuBarWindowList(option: option))
    }
}

// MARK: - Specific Windows

extension WindowInfo {
    /// Returns the wallpaper window for the given display from the
    /// given list of windows.
    static func wallpaperWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        let displayBounds = CGDisplayBounds(display)
        return windows.first { window in
            // Wallpaper window belongs to the Dock process.
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
                window.title?.hasPrefix("Wallpaper") == true &&
                displayBounds.contains(window.bounds)
        }
    }

    /// Creates and returns the wallpaper window for the given display.
    static func wallpaperWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        wallpaperWindow(from: createWindows(option: .onScreen), for: display)
    }

    // MARK: Menu Bar Window

    /// Returns the menu bar window for the given display from the
    /// given list of windows.
    static func menuBarWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        let displayBounds = CGDisplayBounds(display)
        return windows.first { window in
            // Menu bar window belongs to the WindowServer process.
            window.isWindowServerWindow &&
                window.isOnScreen &&
                window.layer == kCGMainMenuWindowLevel &&
                window.title == "Menubar" &&
                displayBounds.contains(window.bounds)
        }
    }

    /// Creates and returns the menu bar window for the given display.
    static func menuBarWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        menuBarWindow(from: createMenuBarWindows(option: .onScreen), for: display)
    }
}

// MARK: WindowInfo: Codable

extension WindowInfo: Codable {}

// MARK: WindowInfo: Equatable

extension WindowInfo: Equatable {
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.windowID == rhs.windowID &&
            lhs.ownerPID == rhs.ownerPID &&
            lhs.bounds == rhs.bounds &&
            lhs.layer == rhs.layer &&
            lhs.title == rhs.title &&
            lhs.ownerName == rhs.ownerName &&
            lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: WindowInfo: Hashable

extension WindowInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(bounds.origin.x)
        hasher.combine(bounds.origin.y)
        hasher.combine(bounds.size.width)
        hasher.combine(bounds.size.height)
        hasher.combine(layer)
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(isOnScreen)
    }
}
