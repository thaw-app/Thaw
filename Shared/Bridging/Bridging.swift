//
//  Bridging.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Bridging

/// A namespace for bridged or wrapped APIs.
enum Bridging {
    private static let diagLog = DiagLog(category: "Bridging")
}

// MARK: - CGSConnection

extension Bridging {
    // MARK: Private Connection Helpers

    /// The identifier for the `null` window server connection.
    private static let nullConnection: CGSConnectionID = 0

    /// Returns the identifier for the main window server connection.
    private static func getMainConnection() -> CGSConnectionID {
        CGSMainConnectionID()
    }

    /// Returns the identifier for the window server connection
    /// for the current thread.
    private static func getConnectionForThread() -> CGSConnectionID {
        CGSDefaultConnectionForThread()
    }

    // MARK: Public Connection API

    /// Returns a value from the main window server connection.
    ///
    /// - Parameter key: A key associated with a value in the main
    ///   window server connection.
    static func getConnectionProperty(forKey key: String) -> Any? {
        var value: Unmanaged<CFTypeRef>?
        let result = CGSCopyConnectionProperty(
            getMainConnection(),
            getMainConnection(),
            key as CFString,
            &value
        )
        if result != .success {
            diagLog.error("CGSCopyConnectionProperty failed with error \(result.logString)")
        }
        return value?.takeRetainedValue()
    }

    /// Sets a value in the main window server connection.
    ///
    /// - Parameters:
    ///   - value: A value to set.
    ///   - key: A key to associate with `value` as a property in the
    ///     main window server connection.
    static func setConnectionProperty(_ value: Any?, forKey key: String) {
        let result = CGSSetConnectionProperty(
            getMainConnection(),
            getMainConnection(),
            key as CFString,
            value as CFTypeRef
        )
        if result != .success {
            diagLog.error("CGSSetConnectionProperty failed with error \(result.logString)")
        }
    }
}

// MARK: - CGDisplay / CGSDisplay

extension Bridging {
    // MARK: Private Display Helpers

    private static func getActiveDisplayCount() -> UInt32? {
        var count: UInt32 = 0
        let result = CGGetActiveDisplayList(0, nil, &count)
        guard result == .success else {
            diagLog.error("CGGetActiveDisplayList failed with error \(result.logString)")
            return nil
        }
        return count
    }

    private static func getActiveDisplayList() -> [CGDirectDisplayID] {
        guard let count = getActiveDisplayCount() else {
            return []
        }
        var list = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let result = CGGetActiveDisplayList(count, &list, nil)
        guard result == .success else {
            diagLog.error("CGGetActiveDisplayList failed with error \(result.logString)")
            return []
        }
        return list
    }

    private static func getDisplayUUID(for displayID: CGDirectDisplayID) -> CFUUID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            diagLog.error("CGDisplayCreateUUIDFromDisplayID returned nil for display \(displayID)")
            return nil
        }
        return uuid.takeRetainedValue()
    }

    // MARK: Public Display API

    /// Returns the UUID string for a given display ID.
    /// - Parameter displayID: The display identifier.
    /// - Returns: The UUID string for display, or nil if unavailable.
    static func getDisplayUUIDString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = getDisplayUUID(for: displayID) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Returns the display ID for a given UUID string.
    /// - Parameter uuidString: The UUID string of the display.
    /// - Returns: The display ID, or nil if not found.
    static func getDisplayID(for uuidString: String) -> CGDirectDisplayID? {
        guard let uuid = CFUUIDCreateFromString(nil, uuidString as CFString) else {
            return nil
        }
        return getActiveDisplayList().first { displayID in
            guard let displayUUID = getDisplayUUID(for: displayID) else {
                return false
            }
            return CFEqual(displayUUID, uuid)
        }
    }

    /// Returns the UUID string for the display with active menu bar.
    /// - Returns: The UUID string of the active menu bar display, or nil if unavailable.
    static func getActiveMenuBarDisplayUUID() -> String? {
        guard let displayID = getActiveMenuBarDisplayID() else {
            return nil
        }
        return getDisplayUUIDString(for: displayID)
    }

    /// Returns the identifier of the display with the active menu bar.
    static func getActiveMenuBarDisplayID() -> CGDirectDisplayID? {
        guard
            let string = CGSCopyActiveMenuBarDisplayIdentifier(getMainConnection()),
            let uuid = CFUUIDCreateFromString(nil, string.takeRetainedValue()),
            let displayID = getActiveDisplayList().first(where: {
                guard let displayUUID = getDisplayUUID(for: $0) else {
                    return false
                }
                return CFEqual(displayUUID, uuid)
            })
        else {
            return CGMainDisplayID()
        }
        return displayID
    }
}

// MARK: - CGSEvent

extension Bridging {
    /// Returns a Boolean value indicating whether the given process
    /// is unresponsive.
    ///
    /// - Parameter pid: An identifier for a process.
    static func isProcessUnresponsive(_ pid: pid_t) -> Bool {
        var psn = ProcessSerialNumber()
        let result = GetProcessForPID(pid, &psn)
        guard result == noErr else {
            diagLog.error("GetProcessForPID failed with error \(result)")
            return false
        }
        return CGSEventIsAppUnresponsive(getMainConnection(), &psn)
    }

    /// Sets the timeout used to determine if a process is unresponsive.
    ///
    /// - Parameter timeout: An amount of time in seconds.
    static func setProcessUnresponsiveTimeout(_ timeout: TimeInterval) {
        let result = CGSEventSetAppIsUnresponsiveNotificationTimeout(getMainConnection(), timeout)
        if result != .success {
            diagLog.error("CGSEventSetAppIsUnresponsiveNotificationTimeout failed with error \(result.logString)")
        }
    }
}

// MARK: - CGSSpace

extension Bridging {
    /// Returns the identifier for the active space.
    static func getActiveSpaceID() -> CGSSpaceID {
        CGSGetActiveSpace(getMainConnection())
    }

    /// Returns the identifier for the current space on the given
    /// display.
    ///
    /// - Parameter displayID: An identifier for a display.
    static func getCurrentSpaceID(for displayID: CGDirectDisplayID) -> CGSSpaceID? {
        guard let uuid = getDisplayUUID(for: displayID) else {
            return nil
        }
        guard let uuidString = CFUUIDCreateString(nil, uuid) else {
            diagLog.error("CFUUIDCreateString returned nil for display \(displayID)")
            return nil
        }
        return CGSManagedDisplayGetCurrentSpace(getMainConnection(), uuidString)
    }

    /// Returns a list of identifiers for the spaces that contain the
    /// given window.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - visibleSpacesOnly: A Boolean value that determines whether
    ///     the returned list should only include visible spaces.
    static func getSpaceList(for windowID: CGWindowID, visibleSpacesOnly: Bool = false) -> [CGSSpaceID] {
        let mask: CGSSpaceMask = visibleSpacesOnly ? .allVisibleSpacesMask : .allSpacesMask
        guard let spaces = CGSCopySpacesForWindows(getMainConnection(), mask, [windowID] as CFArray) else {
            diagLog.error("CGSCopySpacesForWindows returned nil")
            return []
        }
        guard let list = spaces.takeRetainedValue() as? [CGSSpaceID] else {
            diagLog.error("CGSCopySpacesForWindows returned array of unexpected type")
            return []
        }
        return list
    }

    /// Returns a Boolean value that indicates whether the given space
    /// is fullscreen.
    ///
    /// - Parameter spaceID: An identifier for a space.
    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        let type = CGSSpaceGetType(getMainConnection(), spaceID)
        return type == .fullscreen
    }
}

// MARK: - CGSWindow

extension Bridging {
    /// Returns the bounds for the given window.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        var bounds = CGRect.zero
        let result = CGSGetScreenRectForWindow(getConnectionForThread(), windowID, &bounds)
        guard result == .success else {
            diagLog.error("CGSGetScreenRectForWindow failed with error \(result.logString)")
            return nil
        }
        return bounds
    }

    /// Returns the level for the given window.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
        var level: CGWindowLevel = 0
        let result = CGSGetWindowLevel(getMainConnection(), windowID, &level)
        guard result == .success else {
            diagLog.error("CGSGetWindowLevel failed with error \(result.logString)")
            return nil
        }
        return level
    }

    /// Returns a Boolean value that indicates whether the given window
    /// is on the given space.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - spaceID: An identifier for a space.
    static func isWindowOnSpace(_ windowID: CGWindowID, _ spaceID: CGSSpaceID) -> Bool {
        let list = getSpaceList(for: windowID, visibleSpacesOnly: false)
        return list.contains(spaceID)
    }

    /// Returns a Boolean value that indicates whether the given window
    /// intersects the given display bounds.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - displayBounds: The bounds of a display.
    static func windowIntersectsDisplayBounds(_ windowID: CGWindowID, _ displayBounds: CGRect) -> Bool {
        if let windowBounds = getWindowBounds(for: windowID) {
            return displayBounds.intersects(windowBounds)
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the given window
    /// is on the specified display.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - displayID: An identifier for a display.
    static func isWindowOnDisplay(_ windowID: CGWindowID, _ displayID: CGDirectDisplayID) -> Bool {
        let displayBounds = CGDisplayBounds(displayID)
        return windowIntersectsDisplayBounds(windowID, displayBounds)
    }

    /// Returns a Boolean value that indicates whether the given window
    /// is on screen.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func isWindowOnScreen(_ windowID: CGWindowID) -> Bool {
        // On screen window list could potentially include menu bar
        // items hidden via drag-and-drop (seems like a bug in macOS?).
        //
        // Checking individual displays could be relatively expensive,
        // so we can at least short circuit if the window is _not_ in
        // the list.
        if !getOnScreenWindowList().contains(windowID) {
            return false
        }
        guard let windowBounds = getWindowBounds(for: windowID) else {
            return false
        }
        return getActiveDisplayList().contains { displayID in
            let displayBounds = CGDisplayBounds(displayID)
            return displayBounds.intersects(windowBounds)
        }
    }

    // MARK: Private Window List Helpers

    private static func getWindowCount() -> Int32? {
        var count: Int32 = 0
        let result = CGSGetWindowCount(getMainConnection(), nullConnection, &count)
        guard result == .success else {
            diagLog.error("CGSGetWindowCount failed with error \(result.logString)")
            return nil
        }
        return count
    }

    private static func getOnScreenWindowCount() -> Int32? {
        var count: Int32 = 0
        let result = CGSGetOnScreenWindowCount(getMainConnection(), nullConnection, &count)
        guard result == .success else {
            diagLog.error("CGSGetOnScreenWindowCount failed with error \(result.logString)")
            return nil
        }
        return count
    }

    private static func getWindowList() -> [CGWindowID] {
        guard var count = getWindowCount() else {
            return []
        }
        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = CGSGetWindowList(getMainConnection(), nullConnection, count, &list, &count)
        guard result == .success else {
            diagLog.error("CGSGetWindowList failed with error \(result.logString)")
            return []
        }
        return [CGWindowID](list[..<Int(count)])
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        guard var count = getOnScreenWindowCount() else {
            return []
        }
        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = CGSGetOnScreenWindowList(getMainConnection(), nullConnection, count, &list, &count)
        guard result == .success else {
            diagLog.error("CGSGetOnScreenWindowList failed with error \(result.logString)")
            return []
        }
        return [CGWindowID](list[..<Int(count)])
    }

    private static func getProcessMenuBarWindowList() -> [CGWindowID] {
        guard var count = getWindowCount() else {
            diagLog.warning("getProcessMenuBarWindowList: getWindowCount() returned nil, cannot enumerate windows")
            return []
        }
        diagLog.debug("getProcessMenuBarWindowList: total window count = \(count)")
        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = CGSGetProcessMenuBarWindowList(getMainConnection(), nullConnection, count, &list, &count)
        guard result == .success else {
            diagLog.error("CGSGetProcessMenuBarWindowList failed with error \(result.logString)")
            return []
        }
        let windowList = [CGWindowID](list[..<Int(count)])
        diagLog.debug("getProcessMenuBarWindowList: returned \(windowList.count) menu bar windows")
        return windowList
    }

    // MARK: Public Window List API

    /// Options that specify the identifiers in a window list.
    struct WindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on screen.
        static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        static let activeSpace = WindowListOption(rawValue: 1 << 1)
    }

    /// Options that specify the identifiers in a menu bar window list.
    struct MenuBarWindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on screen.
        static let onScreen = MenuBarWindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        static let activeSpace = MenuBarWindowListOption(rawValue: 1 << 1)

        /// Specifies only windows that represent menu bar items.
        static let itemsOnly = MenuBarWindowListOption(rawValue: 1 << 2)
    }

    /// Returns a list of window identifiers.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        let list = if option.contains(.onScreen) {
            getOnScreenWindowList()
        } else {
            getWindowList()
        }
        if option.contains(.activeSpace) {
            let activeSpaceID = getActiveSpaceID()
            return list.filter { windowID in
                isWindowOnSpace(windowID, activeSpaceID)
            }
        }
        return list
    }

    /// Returns a list of window identifiers for elements in the
    /// menu bar.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func getMenuBarWindowList(option: MenuBarWindowListOption = []) -> [CGWindowID] {
        var predicates = [(CGWindowID) -> Bool]()

        if option.contains(.onScreen) {
            let onScreenList = Set(getOnScreenWindowList())
            diagLog.debug("getMenuBarWindowList: onScreen filter active, \(onScreenList.count) on-screen windows")
            predicates.append { windowID in
                onScreenList.contains(windowID)
            }
        }

        if option.contains(.activeSpace) {
            let activeSpaceID = getActiveSpaceID()
            diagLog.debug("getMenuBarWindowList: activeSpace filter active, spaceID = \(activeSpaceID)")
            predicates.append { windowID in
                isWindowOnSpace(windowID, activeSpaceID)
            }
        }

        if option.contains(.itemsOnly) {
            predicates.append { windowID in
                getWindowLevel(for: windowID) != kCGMainMenuWindowLevel
            }
        }

        let rawList = getProcessMenuBarWindowList()
        let filtered = rawList.filter { windowID in
            predicates.allSatisfy { predicate in
                predicate(windowID)
            }
        }
        diagLog.debug("getMenuBarWindowList: \(rawList.count) raw -> \(filtered.count) after filtering (options: onScreen=\(option.contains(.onScreen)), activeSpace=\(option.contains(.activeSpace)), itemsOnly=\(option.contains(.itemsOnly)))")
        return filtered
    }

    // MARK: - CGWindowList Helpers

    /// Creates an `NSArray` containing the bit patterns of the given
    /// window list.
    ///
    /// Pass the returned array into one of the `CGWindowList` APIs
    /// from `CoreGraphics`.
    ///
    /// - Parameter windowIDs: A list of window identifiers. If the
    ///   list is empty, or if none of its elements can represent a
    ///   valid bit pattern, this function returns `nil`.
    ///
    /// - Returns: An `NSArray` where each element is a memory address
    ///   with a bit pattern that matches an element from `windowIDs`,
    ///   or `nil` if the array cannot be created.
    static func createCGWindowArray(with windowIDs: [CGWindowID]) -> NSArray? {
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap { windowID in
            UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard !pointers.isEmpty else {
            return nil
        }
        var callbacks = CFArrayCallBacks(
            version: 0,
            retain: nil,
            release: nil,
            copyDescription: nil,
            equal: nil
        )
        let array = CFArrayCreate(nil, &pointers, pointers.count, &callbacks)
        return array as NSArray?
    }
}
