//
//  Bridging.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ScreenCaptureKit

// MARK: - Bridging

/// The window server surface Thaw talks to, gathered behind one name.
///
/// Wraps the calls declared in Shims.swift, turning C conventions into Swift
/// values and logging failures. Never throws: callers poll, and reporting
/// nothing to retry next tick beats propagating a failed round trip.
public enum Bridging {
    private static let diagLog = DiagLog(category: "Bridging")
}

// MARK: - Core Foundation Type Guards

public extension Bridging {
    /// The elements of value, or nil unless it really is a CFArray.
    ///
    /// A value statically typed as CFArray bridges unconditionally and that bridge
    /// aborts on any other CF type, so the type id is checked before any cast.
    static func arrayValue(of value: CFTypeRef?) -> [Any]? {
        guard let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }
        return value as? [Any]
    }

    /// The entries of value, or nil unless it really is a CFDictionary whose
    /// keys bridge to Key.
    static func dictionaryValue<Key: Hashable>(of value: CFTypeRef?) -> [Key: Any]? {
        guard let value, CFGetTypeID(value) == CFDictionaryGetTypeID() else {
            return nil
        }
        return value as? [Key: Any]
    }
}

// MARK: - Connections

extension Bridging {
    // MARK: Connection Handles

    /// The connection handle that means "not scoped to one client".
    ///
    /// The window list calls take a second connection naming the client whose
    /// windows are wanted. Zero is not a real connection; passing it asks for
    /// every client's windows instead of one client's.
    private static let unscopedConnection: CGSConnectionID = 0

    /// This process's window server connection.
    private static var processConnection: CGSConnectionID {
        cgsMainConnectionID()
    }

    /// The window server connection bound to the calling thread.
    ///
    /// Distinct from processConnection: geometry calls are issued on the
    /// caller's own connection so a window this process is actively moving is
    /// read back through the same channel that moved it.
    private static var callerConnection: CGSConnectionID {
        cgsDefaultConnectionForThread()
    }

    // MARK: Connection Properties

    /// Writes a property onto this process's window server connection.
    ///
    /// - Parameters:
    ///   - value: The value to store. nil bridges to kCFNull, which is how
    ///     the window server records an explicitly empty property.
    ///   - key: The property name.
    public static func setConnectionProperty(_ value: Any?, forKey key: String) {
        let connection = processConnection
        let status = cgsSetConnectionProperty(connection, connection, key as CFString, value as CFTypeRef)
        if status != .success {
            diagLog.error("cgsSetConnectionProperty failed with error \(status.logString)")
        }
    }
}

// MARK: - Displays

public extension Bridging {
    // MARK: Display Enumeration

    /// Every display currently attached and awake.
    ///
    /// CGGetActiveDisplayList is a count-then-fetch pair. Displays can attach
    /// or detach between the two calls, so the fetch reports how many entries
    /// it wrote and the buffer is trimmed to that count, clamped to the
    /// allocation: the tail holds zeroes that are not display identifiers.
    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var capacity: UInt32 = 0
        let sizing = CGGetActiveDisplayList(0, nil, &capacity)
        guard sizing == .success else {
            diagLog.error("CGGetActiveDisplayList failed with error \(sizing.logString)")
            return []
        }
        guard capacity > 0 else {
            return []
        }
        var buffer = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        var written: UInt32 = 0
        let fetch = CGGetActiveDisplayList(capacity, &buffer, &written)
        guard fetch == .success else {
            diagLog.error("CGGetActiveDisplayList failed with error \(fetch.logString)")
            return []
        }
        return Array(buffer.prefix(Int(min(written, capacity))))
    }

    /// The display's UUID, which survives the display identifier being
    /// recycled across sleep, hot-plug and resolution changes.
    ///
    /// The Create call returns the reference at +1, so it is consumed
    /// retained; taking it unretained would leak a CFUUID on every call.
    private static func displayUUID(of displayID: CGDirectDisplayID) -> CFUUID? {
        guard let created = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            diagLog.error("CGDisplayCreateUUIDFromDisplayID returned nil for display \(displayID)")
            return nil
        }
        return created.takeRetainedValue()
    }

    /// The attached display whose UUID matches uuid, if any.
    private static func activeDisplayID(matching uuid: CFUUID) -> CGDirectDisplayID? {
        activeDisplayIDs().first { displayID in
            guard let candidate = displayUUID(of: displayID) else {
                return false
            }
            return CFEqual(candidate, uuid)
        }
    }

    // MARK: Display Lookups

    /// Returns the UUID string for a given display ID.
    /// - Parameter displayID: The display identifier.
    /// - Returns: The UUID string for display, or nil if unavailable.
    static func getDisplayUUIDString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = displayUUID(of: displayID) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Returns the UUID string for the display with active menu bar.
    /// - Returns: The UUID string of the active menu bar display, or nil if unavailable.
    static func getActiveMenuBarDisplayUUID() -> String? {
        guard let displayID = getActiveMenuBarDisplayID() else {
            return nil
        }
        return getDisplayUUIDString(for: displayID)
    }

    /// The display the menu bar is currently attached to.
    ///
    /// Falls back to the main display whenever the window server cannot name
    /// one, or names a display that is no longer attached: callers use this to
    /// pick a screen to work on, and there is always a main display.
    static func getActiveMenuBarDisplayID() -> CGDirectDisplayID? {
        // The UUID string comes back at +1, so it is taken retained before
        // anything else can bail out.
        guard let identifier = cgsCopyActiveMenuBarDisplayIdentifier(processConnection) else {
            return CGMainDisplayID()
        }
        guard
            let uuid = CFUUIDCreateFromString(nil, identifier.takeRetainedValue()),
            let displayID = activeDisplayID(matching: uuid)
        else {
            return CGMainDisplayID()
        }
        return displayID
    }
}

// MARK: - Process Responsiveness

public extension Bridging {
    /// Whether the window server has given up waiting on a process.
    ///
    /// A process that never answers is one whose menu bar item cannot be
    /// interrogated or moved, so callers use this to skip work rather than
    /// stall behind it.
    ///
    /// - Parameter pid: The process to ask about.
    /// - Returns: false when the process is responsive, and also when it
    ///   cannot be addressed at all: a process that has exited is not
    ///   "unresponsive", it is simply gone.
    static func isProcessUnresponsive(_ pid: pid_t) -> Bool {
        // The window server addresses processes by Process Manager serial
        // number, not by BSD pid, so the lookup comes first.
        var psn = ProcessSerialNumber()
        let result = getProcessForPID(pid, &psn)
        guard result == noErr else {
            // -600 (procNotFound) means the owner has already quit, not that it
            // is unresponsive. It is frequent (an owner terminating while a view
            // still polls it), so it stays quiet instead of logging every tick.
            if result != -600 {
                diagLog.error("getProcessForPID failed with error \(result)")
            }
            return false
        }
        return cgsEventIsAppUnresponsive(processConnection, &psn)
    }
}

// MARK: - Spaces

public extension Bridging {
    /// The space the user is currently looking at.
    static func getActiveSpaceID() -> CGSSpaceID {
        cgsGetActiveSpace(processConnection)
    }

    /// The space currently shown on one display.
    ///
    /// The window server keys its per-display space state by display UUID
    /// rather than by display identifier, so the identifier is resolved first.
    ///
    /// - Parameter displayID: The display to ask about.
    /// - Returns: nil when the display has no resolvable UUID, which is the
    ///   case for a display that has just been detached.
    static func getCurrentSpaceID(for displayID: CGDirectDisplayID) -> CGSSpaceID? {
        guard let uuid = displayUUID(of: displayID) else {
            return nil
        }
        guard let uuidText = CFUUIDCreateString(nil, uuid) else {
            diagLog.error("CFUUIDCreateString returned nil for display \(displayID)")
            return nil
        }
        return cgsManagedDisplayGetCurrentSpace(processConnection, uuidText)
    }

    /// The spaces a window appears on.
    ///
    /// - Parameters:
    ///   - windowID: The window to look up.
    ///   - visibleSpacesOnly: Restricts the answer to spaces that are on
    ///     screen right now, rather than every space the window is assigned to.
    /// - Returns: The matching space identifiers, or an empty array if the
    ///   window server declined to answer.
    static func getSpaceList(for windowID: CGWindowID, visibleSpacesOnly: Bool = false) -> [CGSSpaceID] {
        let scope: CGSSpaceMask = visibleSpacesOnly ? .allVisibleSpacesMask : .allSpacesMask
        // Another Copy call: the array arrives at +1 and is consumed retained
        // on both the success and the wrong-type path, so a description the
        // bridge cannot read is still released rather than leaked.
        guard let copied = cgsCopySpacesForWindows(processConnection, scope.rawValue, [windowID] as CFArray) else {
            diagLog.error("cgsCopySpacesForWindows returned nil")
            return []
        }
        guard let elements = arrayValue(of: copied.takeRetainedValue()) else {
            diagLog.error("cgsCopySpacesForWindows returned a value that is not an array")
            return []
        }
        guard let spaceIDs = elements as? [CGSSpaceID] else {
            diagLog.error("cgsCopySpacesForWindows returned array of unexpected type")
            return []
        }
        return spaceIDs
    }

    /// Whether a space is a full-screen space rather than a desktop.
    ///
    /// - Parameter spaceID: The space to classify.
    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        // The shim hands back the raw tag rather than a Swift enum so that a
        // value outside the three known cases is an ordinary number this can
        // reject, instead of an invalid enum case.
        let rawType = cgsSpaceGetType(processConnection, spaceID)
        return CGSSpaceType(rawValue: rawType) == .fullscreen
    }

    /// A space as the window server currently reports it.
    struct ManagedSpace: Hashable, Sendable {
        /// The space's identifier. Renumbered across logout.
        public let spaceID: CGSSpaceID
        /// A key that survives logout. Safe to persist.
        public let persistentKey: String
        /// The display the space belongs to.
        public let displayIdentifier: String
        /// The space's 1-based position within its display's list, which is
        /// how Mission Control numbers desktops.
        public let ordinal: Int

        public init(spaceID: CGSSpaceID, persistentKey: String, displayIdentifier: String, ordinal: Int) {
            self.spaceID = spaceID
            self.persistentKey = persistentKey
            self.displayIdentifier = displayIdentifier
            self.ordinal = ordinal
        }
    }

    /// Returns every space the window server currently knows about.
    ///
    /// A CGSSpaceID is renumbered across logout, so the persistent key is the
    /// per-space uuid stored in com.apple.spaces, which survives reboot. The
    /// default space on each display reports an empty uuid and falls back to a
    /// key derived from its display; there is only ever one such space per
    /// display, which keeps the fallback unambiguous.
    static func getManagedSpaces() -> [ManagedSpace] {
        guard let raw = cgsCopyManagedDisplaySpaces(processConnection) else {
            diagLog.error("cgsCopyManagedDisplaySpaces returned nil")
            return []
        }
        guard let elements = arrayValue(of: raw.takeRetainedValue()) else {
            diagLog.error("cgsCopyManagedDisplaySpaces returned a value that is not an array")
            return []
        }
        let displays = elements.compactMap { element -> [String: Any]? in
            dictionaryValue(of: element as CFTypeRef)
        }
        if displays.count != elements.count {
            diagLog.error("cgsCopyManagedDisplaySpaces returned an array of unexpected type")
        }

        var result: [ManagedSpace] = []
        for display in displays {
            let displayIdentifier = display["Display Identifier"] as? String ?? "unknown"
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                // Entries without a Spaces array are collapsed records
                // for displays that are not currently attached.
                continue
            }
            for (index, space) in spaces.enumerated() {
                guard let spaceID = space["id64"] as? CGSSpaceID else { continue }
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
}

// MARK: - SLSMenuBar

public extension Bridging {
    /// The window server's own account of menu bar reveal state.
    ///
    /// Thaw otherwise infers this from item geometry, which cannot distinguish
    /// "settled" from "one frame into a reveal". Acting mid-reflow is what
    /// produces mis-timed captures and synthetic moves against a layout that is
    /// still moving.
    struct MenuBarRevealState: Equatable, Sendable {
        /// Progress through an autohide reveal, 0...1.
        public let revealFraction: Float
        /// Menu bar bounds while revealed; .zero when nothing is revealed.
        public let revealedBounds: CGRect
        public let isAutohideEnabled: Bool
        public let isVisible: Bool
        /// Whether the window server actually answered. False when SkyLight no
        /// longer vends these symbols, in which case every other field is a
        /// placeholder and callers must fall back to inferring from geometry.
        public let isAvailable: Bool
    }

    /// Reads menu bar reveal state for spaceID, defaulting to the active space.
    ///
    /// Every call here is a plain window-server round trip on the main
    /// connection, with no entitlement or private mach service. Failures degrade
    /// to a settled-looking state rather than throwing, since callers use this to
    /// defer work and "settled" on error means acting immediately.
    static func menuBarRevealState(forSpace spaceID: CGSSpaceID? = nil) -> MenuBarRevealState {
        guard
            SLSMenuBar.isAvailable,
            let getReveal = SLSMenuBar.getSpaceMenuBarReveal,
            let getBounds = SLSMenuBar.getRevealedMenuBarBounds,
            let getAutohide = SLSMenuBar.getMenuBarAutohideEnabled,
            let isVisible = SLSMenuBar.isMenuBarVisibleOnSpace
        else {
            return MenuBarRevealState(
                revealFraction: 0,
                revealedBounds: .zero,
                isAutohideEnabled: false,
                isVisible: true,
                isAvailable: false
            )
        }

        let cid = cgsMainConnectionID()
        let sid = spaceID ?? getActiveSpaceID()

        var bounds = CGRect.zero
        if getBounds(cid, &bounds) != .success {
            bounds = .zero
        }

        var autohide: Int32 = 0
        let autohideEnabled = getAutohide(cid, &autohide) == .success && autohide != 0

        return MenuBarRevealState(
            revealFraction: getReveal(sid),
            revealedBounds: bounds,
            isAutohideEnabled: autohideEnabled,
            isVisible: isVisible(cid, sid) != 0,
            isAvailable: true
        )
    }
}

// MARK: - Windows

public extension Bridging {
    /// The window's frame in global display coordinates.
    ///
    /// Issued on the calling thread's own connection rather than the process
    /// connection, so a window this process is in the middle of moving reads
    /// back through the same channel that moved it.
    ///
    /// - Parameter windowID: The window to measure.
    /// - Returns: nil rather than a zero rectangle when the window server
    ///   refuses, so callers can tell "no answer" from "empty window".
    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        var frame = CGRect.zero
        let status = cgsGetScreenRectForWindow(callerConnection, windowID, &frame)
        guard status == .success else {
            // Debug, not error: a window refusing to report its frame is routine
            // on a live bar (items vanish while menus open, sections conceal, and
            // collapsed macOS 27 dividers have no window at all). Every caller
            // falls back to the last known frame, so error level only buries
            // real failures.
            diagLog.debug("cgsGetScreenRectForWindow failed with error \(status.logString)")
            return nil
        }
        return frame
    }

    /// Diagnostic: logs the menu-bar windows owned by SystemUIServer and
    /// MenuBarAgent. On macOS 27 any individual item windows are owned by the
    /// system process, not by the third-party app. Call once during startup.
    static func logSystemMenuBarWindows() {
        let bundleIDs = ["com.apple.systemuiserver", SharedConstants.menuBarHostingBundleID]
        for bid in bundleIDs {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.processIdentifier else {
                diagLog.debug("logSystemMenuBarWindows: \(bid) not running")
                continue
            }
            diagLog.debug("logSystemMenuBarWindows: \(bid) pid=\(pid)")
            let wids = getMenuBarWindowIDs(forProcess: pid, skipWidthFilter: true)
            diagLog.debug("logSystemMenuBarWindows: \(bid) → \(wids.count) menu-bar windows")
            for wid in wids {
                let bounds = getWindowBounds(for: wid)
                let level = getWindowLevel(for: wid)
                diagLog.debug("logSystemMenuBarWindows: \(bid) window \(wid) bounds=\(bounds?.debugDescription ?? "nil") level=\(level.map(String.init(describing:)) ?? "nil")")
            }
        }
    }

    /// Returns the real CGWindowIDs of a process's menu-bar item windows.
    ///
    /// On macOS 27 the per-item identifiers Thaw carries are synthetic (a hash
    /// of the item's identity), not real window IDs, so the CGS off-screen hider
    /// cannot move them directly. This resolves a running process to its actual
    /// menu-bar window IDs via its CGS connection. Returns an empty array if the
    /// process has no menu-bar windows or the connection cannot be resolved.
    ///
    /// - Parameter pid: The owning process identifier.
    static func getMenuBarWindowIDs(forProcess pid: pid_t, skipWidthFilter: Bool = false) -> [CGWindowID] {
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else {
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → no PSN")
            return []
        }
        let cid = callerConnection
        var targetCID: CGSConnectionID = 0
        guard cgsGetConnectionIDForPSN(cid, &psn, &targetCID) == .success, targetCID != 0 else {
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → cgsGetConnectionIDForPSN failed, targetCID=\(targetCID)")
            return []
        }
        var count: Int32 = 0
        guard cgsGetWindowCount(cid, targetCID, &count) == .success, count > 0 else {
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → cgsGetWindowCount=\(count)")
            return []
        }
        diagLog.debug("getMenuBarWindowIDs: pid \(pid) total windows=\(count)")
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var outCount: Int32 = 0
        let result = list.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return CGError.failure
            }
            return cgsGetProcessMenuBarWindowList(cid, targetCID, count, base, &outCount)
        }
        guard result == .success else {
            diagLog.error("cgsGetProcessMenuBarWindowList failed for pid \(pid): \(result.logString)")
            return []
        }

        // On macOS 27 the menu bar is rendered into shared hosting windows
        // (one per display), not per-item windows. cgsGetProcessMenuBarWindowList
        // returns those hosting windows for every process. They must be filtered
        // out: moving a hosting window off-screen collapses the entire bar.
        // Hosting windows are full display width; real per-item windows are at
        // most a few hundred points wide. On pre-27 macOS where items have
        // individual windows this filter is a no-op (items are narrow).
        let allReturned = Array(list.prefix(Int(outCount)))
        let windowIDs: [CGWindowID] = if skipWidthFilter {
            allReturned
        } else {
            allReturned.filter { wid in
                guard let bounds = getWindowBounds(for: wid) else { return false }
                return bounds.width <= 1000
            }
        }

        for wid in windowIDs {
            let bounds = getWindowBounds(for: wid)
            let level = getWindowLevel(for: wid)
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → window \(wid) bounds=\(bounds?.debugDescription ?? "nil") level=\(level.map(String.init(describing:)) ?? "nil")")
        }
        if !skipWidthFilter, windowIDs.isEmpty, outCount > 0 {
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → all \(outCount) returned windows were hosting windows, filtered out")
        }
        return windowIDs
    }

    /// Moves a window's top-left origin in global display coordinates. Returns
    /// whether the move succeeded. Used by the CGS off-screen hider to push a
    /// status-item window outside all displays and to restore it.
    ///
    /// - Parameters:
    ///   - windowID: The window to move.
    ///   - origin: The new top-left origin, in global (Y-down) coordinates.
    @discardableResult
    static func moveWindow(_ windowID: CGWindowID, to origin: CGPoint) -> Bool {
        var point = origin
        let result = cgsMoveWindow(callerConnection, windowID, &point)
        guard result == .success else {
            diagLog.error("cgsMoveWindow failed for window \(windowID): \(result.logString)")
            return false
        }
        return true
    }

    /// The window's stacking level.
    ///
    /// - Parameter windowID: The window to inspect.
    /// - Returns: nil when the window server refuses. Level zero is a real
    ///   level, so it cannot double as a failure marker.
    static func getWindowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
        var stackingLevel: CGWindowLevel = 0
        let status = cgsGetWindowLevel(processConnection, windowID, &stackingLevel)
        guard status == .success else {
            diagLog.error("cgsGetWindowLevel failed with error \(status.logString)")
            return nil
        }
        return stackingLevel
    }

    /// Whether a window is assigned to a particular space.
    ///
    /// Asks about every space the window belongs to, not only the visible
    /// ones, so a window on a space that is currently scrolled away still
    /// counts as being on it.
    ///
    /// - Parameters:
    ///   - windowID: The window to look up.
    ///   - spaceID: The space to test against.
    static func isWindowOnSpace(_ windowID: CGWindowID, _ spaceID: CGSSpaceID) -> Bool {
        getSpaceList(for: windowID, visibleSpacesOnly: false).contains(spaceID)
    }

    /// Whether a window is genuinely visible somewhere on the desktop.
    ///
    /// The window server's on-screen list alone is not enough: menu bar items
    /// parked off the edge of every display (which is how items get hidden)
    /// keep appearing in it. So the list is only a cheap rejection, and a
    /// window that passes it must still land on an attached display. The list
    /// is one round trip; the geometry check is one per display.
    ///
    /// - Parameter windowID: The window to test.
    static func isWindowOnScreen(_ windowID: CGWindowID) -> Bool {
        guard onScreenWindowIDs().contains(windowID) else {
            return false
        }
        guard let frame = getWindowBounds(for: windowID) else {
            return false
        }
        return activeDisplayIDs().contains { displayID in
            CGDisplayBounds(displayID).intersects(frame)
        }
    }

    // MARK: Window List Plumbing

    // Every window list is read the same way: one call reports the count, a
    // second fills a buffer sized from it. The count can change between the
    // two round trips, so the fetch reports how many identifiers it wrote; the
    // rest of the buffer is zeroes, which is not a valid window identifier.
    //
    // Split in two so each list logs the symbol that failed and sizes itself
    // from the right counting call. The menu bar list has no counting call and
    // borrows the total window count.

    /// Runs the counting half of a list read.
    ///
    /// - Parameters:
    ///   - symbol: The window server call being made, used only for logging.
    ///   - measure: Invokes that call, writing the count through the pointer.
    /// - Returns: The number of identifiers to allocate for, or nil if the
    ///   window server refused. A refusal is distinct from a count of zero:
    ///   callers that log around this need to tell them apart.
    private static func windowIDCount(
        _ symbol: String,
        _ measure: (UnsafeMutablePointer<Int32>) -> CGError
    ) -> Int32? {
        var available: Int32 = 0
        let status = measure(&available)
        guard status == .success else {
            diagLog.error("\(symbol) failed with error \(status.logString)")
            return nil
        }
        // Nothing documents a negative count, but it would trap the allocation
        // below, so it is folded into "no windows" here rather than trusted.
        return max(available, 0)
    }

    /// Runs the fetching half of a list read.
    ///
    /// - Parameters:
    ///   - symbol: The window server call being made, used only for logging.
    ///   - capacity: The buffer size, as reported by windowIDCount(_:_:).
    ///   - fetch: Invokes the call with the capacity, the buffer, and the
    ///     out-parameter for how many identifiers were written.
    /// - Returns: Only the identifiers the window server reports writing.
    private static func windowIDs(
        _ symbol: String,
        capacity: Int32,
        _ fetch: (Int32, UnsafeMutablePointer<CGWindowID>, UnsafeMutablePointer<Int32>) -> CGError
    ) -> [CGWindowID] {
        guard capacity > 0 else {
            // No allocation, and no round trip either: an empty buffer has no
            // base address to hand across, and the answer is already known.
            return []
        }
        var buffer = [CGWindowID](repeating: 0, count: Int(capacity))
        var written: Int32 = 0
        let status = buffer.withUnsafeMutableBufferPointer { region -> CGError in
            guard let base = region.baseAddress else {
                return .failure
            }
            return fetch(capacity, base, &written)
        }
        guard status == .success else {
            diagLog.error("\(symbol) failed with error \(status.logString)")
            return []
        }
        // Trim to what was written, clamped to what was allocated. The clamp is
        // the load-bearing half: the count came from an earlier round trip, and
        // a server that reports writing more than it was given room for would
        // otherwise send this reading past the end of the buffer.
        return Array(buffer.prefix(Int(min(max(written, 0), capacity))))
    }

    /// Every window the window server knows about, across all clients.
    private static func allWindowIDs() -> [CGWindowID] {
        guard let capacity = windowIDCount("cgsGetWindowCount", {
            cgsGetWindowCount(processConnection, unscopedConnection, $0)
        }) else {
            return []
        }
        return windowIDs("cgsGetWindowList", capacity: capacity) { capacity, buffer, written in
            cgsGetWindowList(processConnection, unscopedConnection, capacity, buffer, written)
        }
    }

    /// The windows the window server currently considers on screen.
    private static func onScreenWindowIDs() -> [CGWindowID] {
        guard let capacity = windowIDCount("cgsGetOnScreenWindowCount", {
            cgsGetOnScreenWindowCount(processConnection, unscopedConnection, $0)
        }) else {
            return []
        }
        return windowIDs("cgsGetOnScreenWindowList", capacity: capacity) { capacity, buffer, written in
            cgsGetOnScreenWindowList(processConnection, unscopedConnection, capacity, buffer, written)
        }
    }

    /// The windows every client contributes to the menu bar.
    ///
    /// Sized from the total window count: there is no counting call for this
    /// list, and the menu bar windows are a subset of all windows, so the total
    /// is a safe over-allocation.
    private static func processMenuBarWindowIDs() -> [CGWindowID] {
        guard let capacity = windowIDCount("cgsGetWindowCount", {
            cgsGetWindowCount(processConnection, unscopedConnection, $0)
        }) else {
            diagLog.warning("getProcessMenuBarWindowList: getWindowCount() returned nil, cannot enumerate windows")
            return []
        }
        diagLog.debug("getProcessMenuBarWindowList: total window count = \(capacity)")
        let menuBarWindowIDs = windowIDs("cgsGetProcessMenuBarWindowList", capacity: capacity) { capacity, buffer, written in
            cgsGetProcessMenuBarWindowList(processConnection, unscopedConnection, capacity, buffer, written)
        }
        diagLog.debug("getProcessMenuBarWindowList: returned \(menuBarWindowIDs.count) menu bar windows")
        return menuBarWindowIDs
    }

    // MARK: Window Lists

    /// Filters applied to a window list.
    struct WindowListOption: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Keep only windows the window server reports as on screen.
        public static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Keep only windows assigned to the space in front right now.
        public static let activeSpace = WindowListOption(rawValue: 1 << 1)
    }

    /// Filters applied to a menu bar window list.
    struct MenuBarWindowListOption: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Keep only windows the window server reports as on screen.
        public static let onScreen = MenuBarWindowListOption(rawValue: 1 << 0)

        /// Keep only windows assigned to the space in front right now.
        public static let activeSpace = MenuBarWindowListOption(rawValue: 1 << 1)

        /// Drop the menu bar itself, keeping only the items sitting in it.
        public static let itemsOnly = MenuBarWindowListOption(rawValue: 1 << 2)
    }

    /// Window identifiers for every window, narrowed by option.
    ///
    /// The on-screen filter is applied by asking the window server for a
    /// different list rather than by filtering the full one, since it has a
    /// dedicated call for it. The active-space filter has no such call and is
    /// applied here, one lookup per window.
    ///
    /// - Parameter option: The filters to apply. An empty set returns
    ///   everything the window server will name.
    static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        let windowIDs = option.contains(.onScreen) ? onScreenWindowIDs() : allWindowIDs()
        guard option.contains(.activeSpace) else {
            return windowIDs
        }
        // Read once, outside the loop: the active space cannot change mid-pass
        // in any way this could react to, and asking per window would be a
        // round trip per window.
        let spaceInFront = getActiveSpaceID()
        return windowIDs.filter { windowID in
            isWindowOnSpace(windowID, spaceInFront)
        }
    }

    /// Window identifiers for what is drawn in the menu bar, narrowed by
    /// option.
    ///
    /// Unlike getWindowList(option:) there is only one source list here, so
    /// every filter is applied on this side. They are collected first and run
    /// together per window, which keeps their shared setup (the on-screen set,
    /// the active space) to a single lookup rather than one per window, and
    /// lets allSatisfy stop at the first filter that rejects.
    ///
    /// - Parameter option: The filters to apply. An empty set returns
    ///   everything the window server will name.
    static func getMenuBarWindowList(option: MenuBarWindowListOption = []) -> [CGWindowID] {
        // Whatever a filter needs in common across every window is resolved
        // here, before the pass: the on-screen set and the active space each
        // cost a window server round trip, and resolving them inside the pass
        // would turn that into a round trip per window. Each stays nil while
        // its filter is switched off, so the pass can tell "filter disabled"
        // from "filter matched nothing".
        var onScreenIDs: Set<CGWindowID>?
        if option.contains(.onScreen) {
            let resolved = Set(onScreenWindowIDs())
            diagLog.debug("getMenuBarWindowList: onScreen filter active, \(resolved.count) on-screen windows")
            onScreenIDs = resolved
        }

        var requiredSpaceID: CGSSpaceID?
        if option.contains(.activeSpace) {
            let resolved = getActiveSpaceID()
            diagLog.debug("getMenuBarWindowList: activeSpace filter active, spaceID = \(resolved)")
            requiredSpaceID = resolved
        }

        let excludesTheBarItself = option.contains(.itemsOnly)

        let rawList = processMenuBarWindowIDs()
        let filtered = rawList.filter { windowID in
            if let onScreenIDs, !onScreenIDs.contains(windowID) {
                return false
            }
            if let requiredSpaceID, !isWindowOnSpace(windowID, requiredSpaceID) {
                return false
            }
            // The bar itself sits at the main menu level and the items in it do
            // not. Checked last because it is the only filter that costs a
            // round trip per window, so the cheap set and space tests get to
            // reject first. A window whose level cannot be read is kept: an
            // unreadable level is not evidence of being the bar.
            if excludesTheBarItself, getWindowLevel(for: windowID) == kCGMainMenuWindowLevel {
                return false
            }
            return true
        }
        diagLog.debug("getMenuBarWindowList: \(rawList.count) raw -> \(filtered.count) after filtering (options: onScreen=\(option.contains(.onScreen)), activeSpace=\(option.contains(.activeSpace)), itemsOnly=\(option.contains(.itemsOnly)))")
        return filtered
    }

    // MARK: - Window Array Packing

    /// The largest capture dimension the window server accepts, in pixels.
    static let maximumCaptureDimension = 16384

    /// Whether bounds is safe to hand the window server as a capture rect.
    ///
    /// A null rect means "the minimum rect enclosing the windows", which is
    /// always safe; anything else has to be finite, positively sized, and
    /// inside the dimension limit at the scale the capture will allocate.
    /// CGRect.isFinite is not public, so the components are checked.
    static func isValidCaptureBounds(_ bounds: CGRect, scale: CGFloat = 1) -> Bool {
        if bounds.isNull {
            return true
        }
        guard
            bounds.origin.x.isFinite,
            bounds.origin.y.isFinite,
            bounds.size.width.isFinite,
            bounds.size.height.isFinite,
            scale.isFinite,
            scale > 0
        else { return false }
        // width/height return absolute extents, so a negatively sized rect
        // would pass a > 0 test against them; the raw size components keep
        // the sign.
        guard bounds.size.width > 0, bounds.size.height > 0 else { return false }
        let limit = CGFloat(maximumCaptureDimension) / scale
        return bounds.size.width <= limit && bounds.size.height <= limit
    }

    /// The largest point-to-pixel scale among the active displays, or 1.
    ///
    /// SLWindowListCreateImageFromArray allocates the pixel size of the
    /// rect it is handed, and the SkyLight path cannot resolve the scale by
    /// intersecting the capture rect with a display: it exists precisely to
    /// capture windows parked where no display is. Over-estimating fails safe.
    static func maximumActiveDisplayScale() -> CGFloat {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, nil) == .success else { return 1 }
        var maximum: CGFloat = 1
        for displayID in displays {
            guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { continue }
            maximum = max(maximum, CGFloat(mode.pixelWidth) / CGFloat(mode.width))
        }
        return maximum
    }

    /// Captures the given windows through SkyLight, or nil when the symbol is
    /// unavailable or the capture fails.
    ///
    /// Unlike captureWindowsImageSCK this does not consult shareable
    /// content: it hands the window IDs straight to the window server, which is
    /// what makes it work for menu-bar items the SCK filter cannot address.
    static func captureWindowsImage(
        windowIDs: [CGWindowID],
        screenBounds: CGRect? = nil,
        options: CGWindowImageOption = []
    ) -> CGImage? {
        guard let createImage = SkyLightAPI.createImageFromArray else {
            diagLog.debug("captureWindowsImage: SLWindowListCreateImageFromArray unavailable; use ScreenCaptureKit")
            return nil
        }
        guard let windowArray = createCGWindowArray(with: windowIDs) else {
            diagLog.warning("captureWindowsImage: createCGWindowArray returned nil for \(windowIDs.count) window IDs")
            return nil
        }
        let bounds = screenBounds ?? .null
        let scale = maximumActiveDisplayScale()
        guard isValidCaptureBounds(bounds, scale: scale) else {
            diagLog.error("captureWindowsImage: refusing capture with invalid bounds \(bounds) at scale \(scale)")
            return nil
        }
        guard let image = createImage(bounds, windowArray as CFArray, options)?.takeRetainedValue() else {
            diagLog.debug("captureWindowsImage: SkyLight returned nil for \(windowIDs.count) window(s)")
            return nil
        }
        diagLog.debug("captureWindowsImage: captured \(windowIDs.count) window(s) → \(image.width)×\(image.height)px")
        return image
    }

    /// Packs window identifiers into the array shape the CGWindowList and
    /// SkyLight capture calls expect.
    ///
    /// Those calls take a CFArray whose elements are the identifiers
    /// themselves reinterpreted as pointers, not boxed numbers, so the array is
    /// built with no-op callbacks: nothing in it is a real object, and asking
    /// Core Foundation to retain or release the entries would be a crash.
    ///
    /// - Parameter windowIDs: The identifiers to pack. Identifier zero has no
    ///   pointer representation and is dropped.
    /// - Returns: The packed array, or nil when nothing survived the pack,
    ///   since an empty array is not something the capture calls accept.
    static func createCGWindowArray(with windowIDs: [CGWindowID]) -> NSArray? {
        var pointers = windowIDs.compactMap { windowID in
            UnsafeRawPointer(bitPattern: UInt(windowID))
        } as [UnsafeRawPointer?]
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

// MARK: - ScreenCaptureKit Window Capture

public extension Bridging {
    /// Whether a capture of this many pixels is big enough to carry a menu bar
    /// glyph.
    ///
    /// A collapsed window frame slivers the union bounds; the resulting
    /// one-pixel strip samples as a colour and crops as a glyph.
    static func isPlausibleCaptureSize(width: Int, height: Int) -> Bool {
        width >= 2 && height >= 2
    }

    /// Captures a composite image of an array of windows using ScreenCaptureKit.
    ///
    /// The only window-capture path. SCK's content filter is bounded by the
    /// display, so every window has to lie within display bounds: the
    /// display+including filter returns -3812 for sourceRects outside them, and
    /// the desktopIndependentWindow filter returns -3811 for those windows too.
    /// That bound holds for everything Thaw captures, because macOS 27
    /// composites the menu bar in MenuBarAgent and status items have no
    /// individual windows to sit off-display.
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
        options: CGWindowImageOption = [],
        shouldCapture: @Sendable () -> Bool = { true }
    ) async -> CGImage? {
        guard shouldCapture() else { return nil }
        guard !windowIDs.isEmpty else {
            diagLog.warning("captureWindowsImageSCK: empty windowIDs")
            return nil
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            diagLog.error("captureWindowsImageSCK: SCShareableContent failed: \(error)")
            return nil
        }

        // Preserve caller's z-order so the composite renders correctly.
        let scWindows = windowIDs.compactMap { id in
            content.windows.first { $0.windowID == id }
        }

        // Require an exact match. Partial captures are unsafe: cache composites
        // rely on the result covering every requested window's bounds for the
        // post-capture crop math, and color samplers rely on every requested
        // window being included for the averaged color to mean anything.
        // Fail fast so callers fall back cleanly to SkyLight or skip the tick.
        guard scWindows.count == windowIDs.count else {
            let matched = Set(scWindows.map(\.windowID))
            let missing = windowIDs.filter { !matched.contains($0) }
            diagLog.warning("captureWindowsImageSCK: SCK resolved \(scWindows.count)/\(windowIDs.count) requested windows; missing IDs: \(missing)")
            return nil
        }

        // Union of selected window frames; used both as default bounds and
        // to find the host display.
        let unionBounds = scWindows.reduce(CGRect.null) { $0.union($1.frame) }
        let usesExplicitBounds = screenBounds.map { !$0.isNull } ?? false
        let effectiveBounds: CGRect = {
            if let screenBounds, !screenBounds.isNull {
                return screenBounds
            }
            return unionBounds
        }()

        // Pick the display that holds the largest share of unionBounds. A
        // strict frame.contains check rejects status-item windows whose bounds
        // overshoot NSScreen.frame.maxX by a few pixels (the Clock and Thaw
        // items do), and their icons would vanish from Settings and Search.
        // Largest intersection also picks the majority display for a
        // cross-display span, and returns nil when no display overlaps at all.
        let displayCandidates = content.displays.compactMap { display -> (SCDisplay, CGFloat)? in
            let intersection = display.frame.intersection(unionBounds)
            guard !intersection.isNull else { return nil }
            return (display, intersection.width * intersection.height)
        }
        guard let display = displayCandidates.max(by: { $0.1 < $1.1 })?.0 else {
            diagLog.warning("captureWindowsImageSCK: no display intersects unionBounds=\(unionBounds) (effectiveBounds=\(effectiveBounds))")
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

        configuration.sourceRect = CGRect(
            x: effectiveBounds.origin.x - display.frame.origin.x,
            y: effectiveBounds.origin.y - display.frame.origin.y,
            width: effectiveBounds.width,
            height: effectiveBounds.height
        )
        configuration.width = Int((effectiveBounds.width * scale).rounded())
        configuration.height = Int((effectiveBounds.height * scale).rounded())

        // A degenerate union means the window server has not laid the bar out,
        // so fail and let callers fall back. An explicit screenBounds is exempt:
        // the colour sampler asks for a one-pixel-tall strip on purpose.
        guard usesExplicitBounds
            || Self.isPlausibleCaptureSize(width: configuration.width, height: configuration.height)
        else {
            diagLog.warning(
                "captureWindowsImageSCK: degenerate \(configuration.width)×\(configuration.height)px " +
                    "from unionBounds=\(unionBounds) effectiveBounds=\(effectiveBounds); skipping"
            )
            return nil
        }

        do {
            guard shouldCapture() else { return nil }
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
}
