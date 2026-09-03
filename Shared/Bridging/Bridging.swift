//
//  Bridging.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ScreenCaptureKit

// MARK: - Bridging

/// A namespace for bridged or wrapped APIs.
nonisolated enum Bridging {
    private static let diagLog = DiagLog(category: "Bridging")
}

// MARK: - CGSConnection

nonisolated extension Bridging {
    // MARK: Private Connection Helpers

    /// The identifier for the `null` window server connection.
    private static let nullConnection: CGSConnectionID = 0

    /// Returns the identifier for the main window server connection.
    private static func getMainConnection() -> CGSConnectionID {
        cgsMainConnectionID()
    }

    /// Returns the identifier for the window server connection
    /// for the current thread.
    private static func getConnectionForThread() -> CGSConnectionID {
        cgsDefaultConnectionForThread()
    }

    // MARK: Public Connection API

    /// Returns a value from the main window server connection.
    ///
    /// - Parameter key: A key associated with a value in the main
    ///   window server connection.
    static func getConnectionProperty(forKey key: String) -> Any? {
        var value: Unmanaged<CFTypeRef>?
        let result = cgsCopyConnectionProperty(
            getMainConnection(),
            getMainConnection(),
            key as CFString,
            &value
        )
        if result != .success {
            diagLog.error("cgsCopyConnectionProperty failed with error \(result.logString)")
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
        let result = cgsSetConnectionProperty(
            getMainConnection(),
            getMainConnection(),
            key as CFString,
            value as CFTypeRef
        )
        if result != .success {
            diagLog.error("cgsSetConnectionProperty failed with error \(result.logString)")
        }
    }
}

// MARK: - CGDisplay / CGSDisplay

nonisolated extension Bridging {
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
            let string = cgsCopyActiveMenuBarDisplayIdentifier(getMainConnection()),
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

nonisolated extension Bridging {
    /// Returns a Boolean value indicating whether the given process
    /// is unresponsive.
    ///
    /// - Parameter pid: An identifier for a process.
    static func isProcessUnresponsive(_ pid: pid_t) -> Bool {
        var psn = ProcessSerialNumber()
        let result = getProcessForPID(pid, &psn)
        guard result == noErr else {
            // procNotFound just means the owner has already quit — that is not
            // "unresponsive", and it is an expected, frequent condition (an
            // item's owner terminating while a view still polls it), so treat
            // it quietly instead of logging an error on every tick.
            if result != procNotFound {
                diagLog.error("getProcessForPID failed with error \(result)")
            }
            return false
        }
        return cgsEventIsAppUnresponsive(getMainConnection(), &psn)
    }

    /// Sets the timeout used to determine if a process is unresponsive.
    ///
    /// - Parameter timeout: An amount of time in seconds.
    static func setProcessUnresponsiveTimeout(_ timeout: TimeInterval) {
        let result = cgsEventSetAppIsUnresponsiveNotificationTimeout(getMainConnection(), timeout)
        if result != .success {
            diagLog.error("cgsEventSetAppIsUnresponsiveNotificationTimeout failed with error \(result.logString)")
        }
    }
}

// MARK: - CGSSpace

nonisolated extension Bridging {
    /// Returns the identifier for the active space.
    static func getActiveSpaceID() -> CGSSpaceID {
        cgsGetActiveSpace(getMainConnection())
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
        return cgsManagedDisplayGetCurrentSpace(getMainConnection(), uuidString)
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
        guard let spaces = cgsCopySpacesForWindows(getMainConnection(), mask, [windowID] as CFArray) else {
            diagLog.error("cgsCopySpacesForWindows returned nil")
            return []
        }
        guard let list = spaces.takeRetainedValue() as? [CGSSpaceID] else {
            diagLog.error("cgsCopySpacesForWindows returned array of unexpected type")
            return []
        }
        return list
    }

    /// Returns a Boolean value that indicates whether the given space
    /// is fullscreen.
    ///
    /// - Parameter spaceID: An identifier for a space.
    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        let type = cgsSpaceGetType(getMainConnection(), spaceID)
        return type == .fullscreen
    }

    /// A space as the window server currently reports it.
    nonisolated struct ManagedSpace: Hashable {
        /// The space's identifier. Renumbered across logout.
        let spaceID: CGSSpaceID
        /// A key that survives logout. Safe to persist.
        let persistentKey: String
        /// The display the space belongs to.
        let displayIdentifier: String
        /// The space's 1-based position within its display's list, which is
        /// how Mission Control numbers desktops.
        let ordinal: Int
    }

    /// Returns every space the window server currently knows about.
    ///
    /// A `CGSSpaceID` is renumbered across logout, so it cannot be
    /// persisted. The window server also carries a `uuid` per space,
    /// which survives reboot because the system stores it in
    /// `com.apple.spaces`. That uuid is the persistent key used here.
    ///
    /// The default space on each display reports an *empty* uuid rather
    /// than a real one, so it falls back to a key derived from the
    /// display it belongs to. There is only ever one empty-uuid space
    /// per display, which is what makes that fallback unambiguous.
    static func getManagedSpaces() -> [ManagedSpace] {
        guard let raw = cgsCopyManagedDisplaySpaces(getMainConnection()) else {
            diagLog.error("cgsCopyManagedDisplaySpaces returned nil")
            return []
        }
        guard let displays = raw.takeRetainedValue() as? [[String: Any]] else {
            diagLog.error("cgsCopyManagedDisplaySpaces returned array of unexpected type")
            return []
        }

        var result: [ManagedSpace] = []
        for display in displays {
            let displayIdentifier = display["Display Identifier"] as? String ?? "unknown"
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                // Entries without a `Spaces` array are collapsed records
                // for displays that are not currently attached.
                continue
            }
            for (index, space) in spaces.enumerated() {
                guard let spaceID = space["id64"] as? CGSSpaceID else {
                    continue
                }
                let uuid = space["uuid"] as? String ?? ""
                result.append(ManagedSpace(
                    spaceID: spaceID,
                    persistentKey: uuid.isEmpty ? "display:\(displayIdentifier)#default" : uuid,
                    displayIdentifier: displayIdentifier,
                    ordinal: index + 1
                ))
            }
        }
        return result
    }

    /// Returns a reboot-stable key for every space, keyed by space identifier.
    static func getSpacePersistentKeys() -> [CGSSpaceID: String] {
        var keys: [CGSSpaceID: String] = [:]
        for space in getManagedSpaces() {
            keys[space.spaceID] = space.persistentKey
        }
        return keys
    }

    /// Returns the reboot-stable key for the given space, if one is
    /// available.
    ///
    /// - Parameter spaceID: An identifier for a space.
    static func getSpacePersistentKey(for spaceID: CGSSpaceID) -> String? {
        getManagedSpaces().first { $0.spaceID == spaceID }?.persistentKey
    }
}

// MARK: - CGSWindow

nonisolated extension Bridging {
    /// Returns the bounds for the given window.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        var bounds = CGRect.zero
        let result = cgsGetScreenRectForWindow(getConnectionForThread(), windowID, &bounds)
        guard result == .success else {
            diagLog.error("cgsGetScreenRectForWindow failed with error \(result.logString)")
            return nil
        }
        return bounds
    }

    /// Returns the level for the given window.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
        var level: CGWindowLevel = 0
        let result = cgsGetWindowLevel(getMainConnection(), windowID, &level)
        guard result == .success else {
            diagLog.error("cgsGetWindowLevel failed with error \(result.logString)")
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
        let result = cgsGetWindowCount(getMainConnection(), nullConnection, &count)
        guard result == .success else {
            diagLog.error("cgsGetWindowCount failed with error \(result.logString)")
            return nil
        }
        return count
    }

    private static func getOnScreenWindowCount() -> Int32? {
        var count: Int32 = 0
        let result = cgsGetOnScreenWindowCount(getMainConnection(), nullConnection, &count)
        guard result == .success else {
            diagLog.error("cgsGetOnScreenWindowCount failed with error \(result.logString)")
            return nil
        }
        return count
    }

    private static func getWindowList() -> [CGWindowID] {
        guard var count = getWindowCount() else {
            return []
        }
        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = cgsGetWindowList(getMainConnection(), nullConnection, count, &list, &count)
        guard result == .success else {
            diagLog.error("cgsGetWindowList failed with error \(result.logString)")
            return []
        }
        return [CGWindowID](list[..<Int(count)])
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        guard var count = getOnScreenWindowCount() else {
            return []
        }
        var list = [CGWindowID](repeating: 0, count: Int(count))
        let result = cgsGetOnScreenWindowList(getMainConnection(), nullConnection, count, &list, &count)
        guard result == .success else {
            diagLog.error("cgsGetOnScreenWindowList failed with error \(result.logString)")
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
        let result = cgsGetProcessMenuBarWindowList(getMainConnection(), nullConnection, count, &list, &count)
        guard result == .success else {
            diagLog.error("cgsGetProcessMenuBarWindowList failed with error \(result.logString)")
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

// MARK: - SkyLight Window Capture

nonisolated extension Bridging {
    /// Captures a composite image of an array of windows using SkyLight's private API.
    ///
    /// This is the replacement for the deprecated `CGWindowListCreateImageFromArray` API,
    /// which is unavailable when targeting macOS 26+. SkyLight provides equivalent
    /// functionality through private APIs loaded dynamically at runtime.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - options: Options that specify which parts of the windows are captured.
    /// - Returns: The captured image, or `nil` if capture failed.
    static func captureWindowsImage(
        windowIDs: [CGWindowID],
        screenBounds: CGRect? = nil,
        options: CGWindowImageOption = []
    ) -> CGImage? {
        guard let fn = SkyLightAPI.createImageFromArray else {
            diagLog.error("captureWindowsImage: SkyLight API not available (SLWindowListCreateImageFromArray not found)")
            return nil
        }

        guard let windowArray = createCGWindowArray(with: windowIDs) else {
            diagLog.warning("captureWindowsImage: createCGWindowArray returned nil for \(windowIDs.count) window IDs")
            return nil
        }

        let bounds = screenBounds ?? .null
        let boundsDesc = bounds.isNull ? "null (auto)" : String(format: "(%.0f,%.0f %.0fx%.0f)", bounds.origin.x, bounds.origin.y, bounds.width, bounds.height)
        diagLog.debug("captureWindowsImage: using SkyLight API, bounds=\(boundsDesc), windowCount=\(windowIDs.count), options=\(options.rawValue)")

        let scale = maximumActiveDisplayScale()
        guard isValidCaptureBounds(bounds, scale: scale) else {
            diagLog.error("captureWindowsImage: refusing capture with invalid bounds \(boundsDesc) at scale \(scale) for \(windowIDs.count) windows — see issue #759")
            return nil
        }

        // Use SkyLight's private API instead of deprecated CGWindowListCreateImageFromArray
        guard let image = fn(bounds, windowArray as CFArray, options)?.takeRetainedValue() else {
            diagLog.warning("captureWindowsImage: SLWindowListCreateImageFromArray returned nil for \(windowIDs.count) windows (IDs: \(windowIDs.prefix(5)))")
            return nil
        }

        diagLog.debug("captureWindowsImage: captured \(windowIDs.count) windows → \(image.width)×\(image.height)px")
        return image
    }

    /// The largest point-to-pixel scale among the active displays, or `1`
    /// when none can be read.
    ///
    /// `SLWindowListCreateImageFromArray` allocates the *pixel* size of the
    /// rect it is handed, so a rect that is safe in points can still exceed
    /// ``maximumCaptureDimension`` in pixels on a Retina display — the check
    /// has to scale, the way both ScreenCaptureKit paths already do with
    /// their filter's `pointPixelScale`.
    ///
    /// The SkyLight path has no filter to ask, and cannot resolve the scale
    /// by intersecting the capture rect with a display: it exists precisely
    /// to capture status-item windows parked at large negative x, which
    /// intersect no display at all. Resolving that way would refuse exactly
    /// the captures this path is for. The largest scale in use is taken
    /// instead — it can only over-estimate the pixel size, which fails safe,
    /// and a menu-bar-sized rect is orders of magnitude below the limit
    /// either way.
    private static func maximumActiveDisplayScale() -> CGFloat {
        var maximum: CGFloat = 1
        for displayID in getActiveDisplayList() {
            guard
                let mode = CGDisplayCopyDisplayMode(displayID),
                mode.width > 0
            else {
                continue
            }
            maximum = max(maximum, CGFloat(mode.pixelWidth) / CGFloat(mode.width))
        }
        return maximum
    }

    /// The largest texture dimension the window server will accept for a
    /// capture, in pixels.
    ///
    /// Metal's texture limit on every Apple silicon family is 16384; the
    /// window server builds an `MTLTexture` for the requested capture size,
    /// and `-[MTLTextureDescriptorInternal validateWithDevice:]` calls
    /// `abort()` — inside **WindowServer**, taking down the whole graphical
    /// session — when the descriptor exceeds it. See issue #759.
    static let maximumCaptureDimension = 16384

    /// Returns `true` if `bounds` is safe to send to the window server as a
    /// capture rectangle.
    ///
    /// `CGRect.null` is explicitly allowed: both `SLWindowListCreateImageFromArray`
    /// and this file's ScreenCaptureKit path treat a null rect as "compute the
    /// bounds automatically", which is a legitimate and common request.
    ///
    /// Everything else must describe a real, drawable region. A degenerate
    /// rectangle does not fail gracefully — it crashes WindowServer for the
    /// whole machine (issue #759), so this is a hard precondition, not a
    /// tidiness check.
    ///
    /// - Parameters:
    ///   - bounds: The capture rectangle, in points.
    ///   - scale: The point-to-pixel scale that will be applied. The window
    ///     server allocates the *pixel* size, so the limit must be checked
    ///     after scaling.
    static func isValidCaptureBounds(_ bounds: CGRect, scale: CGFloat = 1.0) -> Bool {
        if bounds.isNull {
            return true
        }
        // NOTE: there is no public `CGRect.isFinite`. A member by that name
        // exists, but it is `package`-visibility inside SwiftUICore and is
        // inaccessible here. Check the four components instead —
        // `FloatingPoint.isFinite` is genuinely public and rejects both NaN
        // and infinity, which also covers the `CGRect.infinite` sentinel.
        guard
            bounds.origin.x.isFinite,
            bounds.origin.y.isFinite,
            bounds.size.width.isFinite,
            bounds.size.height.isFinite,
            scale.isFinite,
            scale > 0
        else {
            return false
        }
        // `width`/`height` return the standardized (absolute) extents, so a
        // negatively-sized rect would pass a `> 0` test against them. Check
        // the raw `size` components, which keep the sign.
        guard bounds.size.width > 0, bounds.size.height > 0 else {
            return false
        }
        let pixelWidth = (bounds.width * scale).rounded()
        let pixelHeight = (bounds.height * scale).rounded()
        guard
            pixelWidth <= CGFloat(maximumCaptureDimension),
            pixelHeight <= CGFloat(maximumCaptureDimension)
        else {
            return false
        }
        return true
    }
}

// MARK: - ScreenCaptureKit Window Capture

nonisolated extension Bridging {
    /// Captures a composite image of an array of windows using ScreenCaptureKit.
    ///
    /// Async, leak-free replacement for captureWindowsImage. Use this for any
    /// window set whose union bounds fit within a display. For menu-bar items
    /// in hidden / always-hidden sections (positioned at large negative x),
    /// stay on captureWindowsImage: SCK's display+including filter returns
    /// error -3812 for sourceRects outside display bounds, and the
    /// desktopIndependentWindow filter returns -3811 for those windows too.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass nil (or CGRect.null) to capture the minimum rectangle that
    ///     encloses the selected windows.
    ///   - options: Capture options. boundsIgnoreFraming maps to
    ///     ignoreShadowsDisplay; nominalResolution forces 1x scale.
    /// - Returns: The captured image, or nil if capture failed.
    static func captureWindowsImageSCK(
        windowIDs: [CGWindowID],
        screenBounds: CGRect? = nil,
        options: CGWindowImageOption = []
    ) async -> CGImage? {
        guard !windowIDs.isEmpty else {
            diagLog.warning("captureWindowsImageSCK: empty windowIDs")
            return nil
        }

        let content: SCShareableContent
        do {
            content = try await shareableContentIncludingOffscreen()
        } catch {
            diagLog.error("captureWindowsImageSCK: SCShareableContent failed: \(error)")
            return nil
        }

        // Everything derived from one shareable-content snapshot.
        //
        // Grouped so a refresh re-derives all of it together. The windows,
        // their union, and the host display all come from the same snapshot,
        // so recomputing only the display against a fresh one would match a
        // current display set against stale window frames — and hand stale
        // `SCWindow` objects to a filter built from a fresh `SCDisplay`.
        struct Resolved {
            let windows: [SCWindow]
            let unionBounds: CGRect
            let display: SCDisplay
        }

        func resolve(from content: SCShareableContent) -> Resolved? {
            // Preserve caller's z-order so the composite renders correctly.
            let scWindows = windowIDs.compactMap { id in
                content.windows.first { $0.windowID == id }
            }

            // Require an exact match. Partial captures are unsafe: cache
            // composites rely on the result covering every requested window's
            // bounds for the post-capture crop math, and color samplers rely
            // on every requested window being included for the averaged color
            // to mean anything.
            guard scWindows.count == windowIDs.count else {
                let matched = Set(scWindows.map(\.windowID))
                let missing = windowIDs.filter { !matched.contains($0) }
                diagLog.warning("captureWindowsImageSCK: SCK resolved \(scWindows.count)/\(windowIDs.count) requested windows; missing IDs: \(missing)")
                return nil
            }

            let unionBounds = scWindows.reduce(CGRect.null) { $0.union($1.frame) }

            // Pick the display holding the largest share of unionBounds. A
            // strict frame.contains check rejected status-item windows whose
            // bounds overshoot NSScreen.frame.maxX by a handful of pixels
            // (observed on the Clock and Thaw items: bounds = (1029, 0, 443,
            // 33) on a 1470-wide display), so the SCK capture never happened
            // and the icons disappeared from Settings / Search.
            // Largest-intersection wins the common edge-overshoot case, picks
            // the majority display for a cross-display span, and still fails
            // when no display overlaps at all.
            let host = content.displays
                .compactMap { display -> (SCDisplay, CGFloat)? in
                    let intersection = display.frame.intersection(unionBounds)
                    let area = intersection.isNull ? 0 : intersection.width * intersection.height
                    guard area > 0 else { return nil }
                    return (display, area)
                }
                .max { $0.1 < $1.1 }?.0
            guard let host else { return nil }

            return Resolved(windows: scWindows, unionBounds: unionBounds, display: host)
        }

        var resolved = resolve(from: content)

        // A failed resolve is not necessarily an orphan window. The content
        // above is served from a cache with a 150ms max age, so a display
        // arriving, leaving, or being rearranged inside that window leaves
        // real item positions being matched against a display set that no
        // longer describes the desktop. Every window then looks orphaned,
        // capture returns nil, and the appearance overlay reports "No valid
        // menu bar found" and stops updating (#794).
        //
        // Refresh once, and only on that failure, rather than charging an
        // uncached enumeration to the 4fps live-refresh path for everyone. A
        // genuinely orphaned window still falls through to nil, one
        // enumeration later.
        var usedRefreshedTopology = false
        if resolved == nil {
            diagLog.debug("captureWindowsImageSCK: could not resolve against cached content; refreshing topology once")
            if let fresh = try? await shareableContentIncludingOffscreen(maxAge: .zero) {
                resolved = resolve(from: fresh)
                if resolved != nil {
                    usedRefreshedTopology = true
                    diagLog.info("captureWindowsImageSCK: stale shareable content; recovered after refresh")
                }
            }
        }

        guard let resolved else {
            diagLog.warning("captureWindowsImageSCK: could not resolve requested windows to a display after refresh")
            return nil
        }

        let scWindows = resolved.windows
        let unionBounds = resolved.unionBounds
        let display = resolved.display

        // `screenBounds` is the caller's crop rect in the coordinate space it
        // observed. If the topology moved out from under us that rect may now
        // describe a different region, so it is only honoured when it still
        // overlaps the freshly resolved windows; otherwise fall back to their
        // union, which is by construction current.
        let effectiveBounds: CGRect = {
            guard let screenBounds, !screenBounds.isNull else {
                return unionBounds
            }
            // `isEmpty`, not `isNull`: CGRect.intersection only returns the
            // null rect when the rects are fully disjoint. Rects that merely
            // touch along an edge intersect to a zero-width or zero-height
            // rect that reports `isNull == false`, which let a stale caller
            // rect through as if it still overlapped. `isEmpty` covers the
            // null rect and the zero-area ones together.
            //
            // The rule below is about Set; these are CGRects, and CGRect has
            // no `isDisjoint(with:)`.
            // swiftlint:disable:next is_disjoint
            if usedRefreshedTopology, screenBounds.intersection(unionBounds).isEmpty {
                diagLog.warning("captureWindowsImageSCK: caller screenBounds=\(screenBounds) no longer overlaps refreshed unionBounds=\(unionBounds); using unionBounds")
                return unionBounds
            }
            return screenBounds
        }()

        guard isValidCaptureBounds(effectiveBounds) else {
            diagLog.error("captureWindowsImageSCK: refusing capture with invalid effectiveBounds=\(effectiveBounds) (screenBounds=\(String(describing: screenBounds)), unionBounds=\(unionBounds)) — see issue #759")
            return nil
        }

        let filter = SCContentFilter(display: display, including: scWindows)

        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        // boundsIgnoreFraming on the legacy API means "skip the window frame".
        // For a display+including filter the equivalent is ignoreShadowsDisplay;
        // no per-window shadow toggle exists on this filter shape. Empty
        // options matches the legacy SkyLight default of keeping framing, so
        // honor only the explicit flag here.
        configuration.ignoreShadowsDisplay = options.contains(.boundsIgnoreFraming)

        let scale: CGFloat = options.contains(.nominalResolution)
            ? 1.0
            : CGFloat(filter.pointPixelScale)

        guard isValidCaptureBounds(effectiveBounds, scale: scale) else {
            diagLog.error("captureWindowsImageSCK: refusing capture, scaled size exceeds \(maximumCaptureDimension)px: effectiveBounds=\(effectiveBounds) scale=\(scale) — see issue #759")
            return nil
        }

        configuration.sourceRect = CGRect(
            x: effectiveBounds.origin.x - display.frame.origin.x,
            y: effectiveBounds.origin.y - display.frame.origin.y,
            width: effectiveBounds.width,
            height: effectiveBounds.height
        )
        configuration.width = Int((effectiveBounds.width * scale).rounded())
        configuration.height = Int((effectiveBounds.height * scale).rounded())

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            diagLog.debug("captureWindowsImageSCK: captured \(windowIDs.count) windows → \(image.width)×\(image.height)px")
            return image
        } catch {
            diagLog.error("captureWindowsImageSCK: SCScreenshotManager.captureImage failed: \(error)")
            return nil
        }
    }

    /// Cached equivalent of `SCShareableContent.excludingDesktopWindows(false,
    /// onScreenWindowsOnly: false)`.
    ///
    /// `captureWindowsImageSCK` is a hot path — the 4 fps live-refresh loop
    /// and every other `captureWindowsAsync` call site fetch shareable
    /// content on each tick, each a full window/display enumeration.
    /// `ShareableContentCache` coalesces calls within `maxAge` of each other
    /// into a single underlying fetch.
    ///
    /// This is a *different* content shape than
    /// `ScreenCapture.getShareableContent()`, which wraps
    /// `SCShareableContent.getWithCompletionHandler`'s default (equivalent to
    /// `.current`, i.e. `excludingDesktopWindows: true, onScreenWindowsOnly:
    /// true`): this one explicitly asks for desktop windows and offscreen
    /// windows too, because captureWindowsImageSCK needs to be able to
    /// resolve menu-bar item windows that ScreenCaptureKit still enumerates
    /// while offscreen even though its capture path later rejects them.
    /// Since the two callers request genuinely different content, they are
    /// cached under separate `ShareableContentCache` instances (keys) rather
    /// than being coalesced into one fetch. `ShareableContentCache` lives
    /// here (rather than alongside `ScreenCapture.getShareableContent()`)
    /// because this file is shared between the Thaw and MenuBarItemService
    /// targets, and only the shared file's symbols are visible to both.
    private static func shareableContentIncludingOffscreen(maxAge: Duration = .milliseconds(150)) async throws -> SCShareableContent {
        let snapshot = try await shareableContentIncludingOffscreenCache.content(
            maxAge: maxAge,
            fetch: fetchShareableContentIncludingOffscreenUncached
        )
        return snapshot.content
    }

    private static let shareableContentIncludingOffscreenCache = ShareableContentCache<ShareableContentSnapshot>()

    private static func fetchShareableContentIncludingOffscreenUncached() async throws -> ShareableContentSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        return ShareableContentSnapshot(content: content)
    }
}

/// Coalesces concurrent/rapid shareable-content fetches into one underlying
/// fetch.
///
/// Holds the most recent result plus an in-flight fetch task. Callers that
/// arrive while a fetch is already running await the same task rather than
/// starting a second enumeration; only the caller that started the task
/// records the result and clears `inFlightTask`, so joiners never race each
/// other over the cache bookkeeping.
///
/// Generic over the cached payload so tests can exercise the coalescing
/// logic with a lightweight fake instead of a real `SCShareableContent`.
actor ShareableContentCache<Content: Sendable> {
    private var cached: (content: Content, timestamp: ContinuousClock.Instant)?
    private var inFlightTask: Task<Content, any Error>?

    func content(
        maxAge: Duration,
        fetch: @Sendable @escaping () async throws -> Content
    ) async throws -> Content {
        if let cached, ContinuousClock.now - cached.timestamp < maxAge {
            return cached.content
        }

        if let inFlightTask {
            return try await awaitWithoutCancelling(inFlightTask)
        }

        let task = Task<Content, any Error> {
            try await fetch()
        }
        inFlightTask = task
        do {
            let content = try await awaitWithoutCancelling(task)
            cached = (content, .now)
            inFlightTask = nil
            return content
        } catch {
            inFlightTask = nil
            throw error
        }
    }

    /// A caller cancelling must not cancel the shared task — other callers
    /// may still be awaiting its result.
    private func awaitWithoutCancelling(_ task: Task<Content, any Error>) async throws -> Content {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            // Intentionally empty: the shared task keeps running for other callers.
        }
    }
}

/// An immutable ScreenCaptureKit snapshot passed across the cache actor.
///
/// `SCShareableContent` is an Objective-C reference type without a Sendable
/// annotation. It is returned as a completed framework snapshot and this
/// wrapper never mutates or exposes any mutable state, so sharing that
/// reference among the capture readers is safe.
nonisolated struct ShareableContentSnapshot: @unchecked Sendable {
    let content: SCShareableContent
}
