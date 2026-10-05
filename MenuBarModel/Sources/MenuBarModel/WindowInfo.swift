//
//  WindowInfo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import os

/// A snapshot of one window, as the window server described it.
///
/// Fields are copies from read time and go stale; currentBounds() re-reads.
public struct WindowInfo: Sendable {
    /// Identifies the window to the window server.
    public let windowID: CGWindowID

    /// The process that owns the window.
    public let ownerPID: pid_t

    /// Where the window was, in global screen coordinates.
    public let bounds: CGRect

    /// The window's stacking layer.
    public let layer: Int

    /// The window's title, when it has one.
    public let title: String?

    /// The owning process's name, as the window server records it.
    ///
    /// Worth consulting when owningApplication is nil or unnamed: system
    /// processes that own windows are often not running applications at all.
    public let ownerName: String?

    /// Whether the window server considered the window on screen.
    public let isOnScreen: Bool

    /// The running application behind ownerPID, if it is still running.
    public var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// Whether the window belongs to the window server rather than to an
    /// application.
    ///
    /// The window server owns the menu bar backdrop and much of the system
    /// chrome, so this is how those are told apart from app windows.
    public var isWindowServerWindow: Bool {
        ownerName == "Window Server"
    }

    /// Whether this window draws the desktop picture: the Dock on macOS 26 and
    /// earlier, WindowManager on macOS 27.
    ///
    /// Falls back to the owner name because NSRunningApplication returns nil
    /// for these processes inside the XPC capture service.
    public var isWallpaperWindow: Bool {
        guard title?.hasPrefix("Wallpaper") == true else { return false }
        switch owningApplication?.bundleIdentifier {
        case "com.apple.dock", "com.apple.WindowManager":
            return true
        default:
            return ownerName == "Dock" || ownerName == "WindowManager"
        }
    }

    /// Whether the window sits at a menu, status or main menu level, or belongs
    /// to the window server, which often owns apps' actual menu windows.
    public var isMenuRelated: Bool {
        let level = CGWindowLevel(Int32(layer))
        return level == CGWindowLevelForKey(.popUpMenuWindow) ||
            level == CGWindowLevelForKey(.popUpMenuWindow) - 1 || // Some menus are slightly below
            level == CGWindowLevelForKey(.statusWindow) ||
            level == CGWindowLevelForKey(.mainMenuWindow) ||
            isWindowServerWindow
    }

    /// Reads one entry of a CoreGraphics window description.
    ///
    /// Identity, owner, geometry and layer are required; a placeholder would
    /// silently misplace the window. Title and owner name are often absent.
    ///
    /// - Parameter element: One element of a window description array.
    private init?(element: Any) {
        guard let description: [CFString: Any] = Bridging.dictionaryValue(of: element as CFTypeRef) else {
            return nil
        }
        guard
            let windowID = description[kCGWindowNumber] as? CGWindowID,
            let ownerPID = description[kCGWindowOwnerPID] as? pid_t,
            let boundsDescription = description[kCGWindowBounds] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDescription),
            let layer = description[kCGWindowLayer] as? Int
        else {
            return nil
        }
        self.init(
            windowID: windowID,
            ownerPID: ownerPID,
            bounds: bounds,
            layer: layer,
            title: description[kCGWindowName] as? String,
            ownerName: description[kCGWindowOwnerName] as? String,
            isOnScreen: description[kCGWindowIsOnscreen] as? Bool ?? false
        )
    }

    /// Looks one window up by identifier.
    ///
    /// - Parameter windowID: The window to describe.
    /// - Returns: nil when the window server has no description for it,
    ///   which is the normal answer for a window that has since closed.
    public init?(windowID: CGWindowID) {
        guard let described = WindowInfo.createWindows(from: [windowID]).first else {
            return nil
        }
        self = described
    }

    /// Creates a window from its properties, so the rules that read them can
    /// be tested without a live window server.
    public init(
        windowID: CGWindowID,
        ownerPID: pid_t,
        bounds: CGRect,
        layer: Int,
        title: String? = nil,
        ownerName: String? = nil,
        isOnScreen: Bool = true
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        self.title = title
        self.ownerName = ownerName
        self.isOnScreen = isOnScreen
    }

    /// Re-reads the window's frame from the window server.
    ///
    /// - Returns: nil when the window server will not answer, which usually
    ///   means the window is gone.
    public func currentBounds() -> CGRect? {
        Bridging.getWindowBounds(for: windowID)
    }
}

// MARK: - Reading Window Lists

public extension WindowInfo {
    private static let diagLog = DiagLog(category: "WindowInfo")
    private static let nilDescriptionLogged = OSAllocatedUnfairLock(initialState: false)

    /// Describes a specific set of windows.
    ///
    /// - Parameter windowIDs: The windows to describe.
    /// - Returns: Descriptions the window server still recognises, in its
    ///   order. Closed windows and unreadable descriptions are dropped.
    static func createWindows(from windowIDs: [CGWindowID]) -> [WindowInfo] {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            diagLog.warning("createWindows: createCGWindowArray returned nil for \(windowIDs.count) window IDs")
            return []
        }
        guard let raw = CGWindowListCreateDescriptionFromArray(array) else {
            // The window server answers nil for a whole process (the capture
            // service, for one), so the first refusal is the diagnostic.
            let firstRefusal = nilDescriptionLogged.withLock { logged -> Bool in
                defer { logged = true }
                return !logged
            }
            if firstRefusal {
                diagLog.warning("createWindows: CGWindowListCreateDescriptionFromArray returned nil for \(windowIDs.count) window IDs; further refusals log at debug")
            } else {
                diagLog.debug("createWindows: CGWindowListCreateDescriptionFromArray returned nil for \(windowIDs.count) window IDs")
            }
            return []
        }
        guard let list = Bridging.arrayValue(of: raw) else {
            let typeName = CFCopyTypeIDDescription(CFGetTypeID(raw)) as String? ?? "unknown"
            diagLog.warning("createWindows: CGWindowListCreateDescriptionFromArray returned a \(typeName), not an array, for \(windowIDs.count) window IDs")
            return []
        }
        let windows = list.compactMap { WindowInfo(element: $0) }
        if windows.count != windowIDs.count {
            diagLog.debug("createWindows: \(windowIDs.count) IDs -> \(list.count) descriptions -> \(windows.count) WindowInfo objects (some may have failed init)")
        }
        return windows
    }

    /// Describes every window, narrowed by option.
    ///
    /// - Parameter option: The filters to apply. An empty set describes
    ///   everything the window server will name.
    static func createWindows(option: Bridging.WindowListOption = []) -> [WindowInfo] {
        createWindows(from: Bridging.getWindowList(option: option))
    }

    /// Describes what is drawn in the menu bar, narrowed by option.
    ///
    /// - Parameter option: The filters to apply. An empty set describes
    ///   everything the window server will name.
    static func createMenuBarWindows(option: Bridging.MenuBarWindowListOption = []) -> [WindowInfo] {
        createWindows(from: Bridging.getMenuBarWindowList(option: option))
    }
}

// MARK: - Finding Particular Windows

public extension WindowInfo {
    /// Picks the wallpaper window for one display out of an already-read list.
    ///
    /// Takes the list so several lookups share one window server round trip.
    ///
    /// - Parameters:
    ///   - windows: The windows to search.
    ///   - display: The display whose wallpaper is wanted.
    static func wallpaperWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        let displayFrame = CGDisplayBounds(display)
        return windows.first { window in
            window.isWallpaperWindow && displayFrame.contains(window.bounds)
        }
    }

    // MARK: The Menu Bar Itself

    /// Picks the menu bar backdrop window for one display out of an
    /// already-read list.
    ///
    /// - Parameters:
    ///   - windows: The windows to search, normally a menu bar window list.
    ///   - display: The display whose menu bar is wanted.
    static func menuBarWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        let displayFrame = CGDisplayBounds(display)
        return windows.first { window in
            // WindowServer owns the backdrop on macOS 26; on 27 MenuBarAgent can too.
            let isMenuBarBackdropOwner = window.isWindowServerWindow
                || window.owningApplication?.bundleIdentifier == SharedConstants.menuBarHostingBundleID
            return isMenuBarBackdropOwner
                && window.isOnScreen
                && window.layer == kCGMainMenuWindowLevel
                && window.title == "Menubar"
                && displayFrame.contains(window.bounds)
        }
    }

    /// Reads the menu bar window list and picks out one display's backdrop.
    ///
    /// - Parameter display: The display whose menu bar is wanted.
    static func menuBarWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        menuBarWindow(from: createMenuBarWindows(option: .onScreen), for: display)
    }

    // MARK: Accessibility Hit Tests

    /// Frames of this process's windows that a systemwide AX hit test lands on.
    /// Overlays at the main menu level and above, and zero-alpha windows, pass it through.
    static func ownHitTestableWindowFrames() -> [CGRect] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        return windows.compactMap { window in
            guard
                window[kCGWindowOwnerPID] as? pid_t == ownPID,
                let layer = window[kCGWindowLayer] as? Int, layer < Int(kCGMainMenuWindowLevel),
                (window[kCGWindowAlpha] as? Double ?? 1) > 0,
                let boundsDescription = window[kCGWindowBounds] as? NSDictionary
            else {
                return nil
            }
            return CGRect(dictionaryRepresentation: boundsDescription)
        }
    }

    /// Whether a systemwide AX hit test at point would run this process's own
    /// AppKit hit testing off the main thread, where SwiftUI traps.
    static func isUnsafeAccessibilityHitTest(at point: CGPoint) -> Bool {
        !Thread.isMainThread && ownHitTestableWindowFrames().contains { $0.contains(point) }
    }
}

// MARK: - Conformances

// Synthesized on purpose, so a newly added property cannot be forgotten.

extension WindowInfo: Codable {}

extension WindowInfo: Equatable {}

extension WindowInfo: Hashable {}
