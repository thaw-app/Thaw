//
//  Shims.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics

// MARK: - Window Server Vocabulary

// The window server's own vocabulary. Connections and spaces are plain integer
// handles in C, so they are spelled as type aliases rather than wrappers: they
// travel straight into and out of the calls below and gain nothing from being
// boxed.

public typealias CGSConnectionID = Int32
public typealias CGSSpaceID = Int

public enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

public struct CGSSpaceMask: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    public static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    public static let includesUser = CGSSpaceMask(rawValue: 1 << 2)

    public static let visible = CGSSpaceMask(rawValue: 1 << 16)

    public static let allSpacesMask: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    public static let allVisibleSpacesMask: CGSSpaceMask = [.visible, .allSpacesMask]
}

// MARK: - Declaration Conventions

//
// Everything below names a C entry point that CoreGraphics exports but does not
// declare in a public header. The @_silgen_name string is the linker symbol
// and is therefore fixed; the Swift declaration next to it exists only to give
// that symbol a type, so it has to describe the C prototype exactly.
// Out-parameters are UnsafeMutablePointer, not inout: both lower to the same
// pointer, but the pointer shows which arguments the window server writes.
// Return types stay at their C width: a uint32_t result is declared UInt32 and
// mapped to an enum by the caller, because declaring the enum here lets Swift
// lower the return to one byte and turns an unknown value into undefined
// behaviour.
//
// Ownership follows the Core Foundation naming rule. A call with Copy or
// Create in its name hands back a +1 reference that this process owns, so its
// result is declared Unmanaged and consumed with takeRetainedValue().
// Anything else returns a borrowed reference.

// MARK: - Connections

/// The window server connection shared by this process.
@_silgen_name("CGSMainConnectionID")
public func cgsMainConnectionID() -> CGSConnectionID

/// The window server connection bound to the calling thread.
@_silgen_name("CGSDefaultConnectionForThread")
public func cgsDefaultConnectionForThread() -> CGSConnectionID

/// Reads a property stored on a connection. Returns the value at +1.
@_silgen_name("CGSCopyConnectionProperty")
public func cgsCopyConnectionProperty(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ key: CFString,
    _ value: UnsafeMutablePointer<Unmanaged<CFTypeRef>?>
) -> CGError

/// Stores a property on a connection.
@_silgen_name("CGSSetConnectionProperty")
public func cgsSetConnectionProperty(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

/// The UUID string, at +1, of the display currently hosting the menu bar.
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
public func cgsCopyActiveMenuBarDisplayIdentifier(_ connection: CGSConnectionID) -> Unmanaged<CFString>?

// MARK: - SLSMenuBar

// Signatures recovered by disassembling SkyLight on macOS 27 and confirmed by
// an unentitled probe: every one returns err=0 from an ordinary main
// window-server connection. Unlike MenuBarAgent's menu-bar services, which all
// require an unobtainable com.apple.private.* entitlement, this surface is
// WindowServer IPC and is genuinely reachable.
//
// Note the asymmetry: SLSGetSpaceMenuBarReveal takes a space ID and no
// connection (it calls CGSGetMainConnectionMachPort() internally), and returns
// the reveal fraction directly rather than through an out-parameter.

/// These are resolved with dlsym rather than @_silgen_name because they live
/// in SkyLight, which the app does not link. Linking a private framework to reach
/// them would turn a symbol that disappears in some future macOS into a launch
/// failure; an unresolved dlsym is just a nil pointer the callers already treat
/// as "no information".
public enum SLSMenuBar {
    /// How far through an autohide reveal the menu bar is on sid, 0...1.
    /// Takes a space ID and no connection: it resolves the connection itself.
    public typealias GetSpaceMenuBarReveal = @convention(c) (CGSSpaceID) -> Float
    /// Bounds of the menu bar while revealed. Zero when nothing is revealed.
    public typealias GetRevealedMenuBarBounds =
        @convention(c) (CGSConnectionID, UnsafeMutablePointer<CGRect>) -> CGError
    /// Whether the menu bar is set to autohide.
    public typealias GetMenuBarAutohideEnabled =
        @convention(c) (CGSConnectionID, UnsafeMutablePointer<Int32>) -> CGError
    /// Whether the menu bar is currently visible on sid.
    public typealias IsMenuBarVisibleOnSpace = @convention(c) (CGSConnectionID, CGSSpaceID) -> Int32

    /// Resolved once at first use and never mutated, so unchecked is accurate.
    private static nonisolated(unsafe) let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }

    public static let getSpaceMenuBarReveal =
        symbol("SLSGetSpaceMenuBarReveal", as: GetSpaceMenuBarReveal.self)
    public static let getRevealedMenuBarBounds =
        symbol("SLSGetRevealedMenuBarBounds", as: GetRevealedMenuBarBounds.self)
    public static let getMenuBarAutohideEnabled =
        symbol("SLSGetMenuBarAutohideEnabled", as: GetMenuBarAutohideEnabled.self)
    public static let isMenuBarVisibleOnSpace =
        symbol("SLSIsMenuBarVisibleOnSpace", as: IsMenuBarVisibleOnSpace.self)

    /// Whether every symbol resolved. False on an OS that has moved or renamed
    /// them, in which case reveal state is simply unavailable.
    public static var isAvailable: Bool {
        getSpaceMenuBarReveal != nil
            && getRevealedMenuBarBounds != nil
            && getMenuBarAutohideEnabled != nil
            && isMenuBarVisibleOnSpace != nil
    }
}

// MARK: - Process Responsiveness

/// Whether the window server considers the addressed process wedged.
///
/// Returns C bool, so the one-byte Swift Bool is the matching width.
@_silgen_name("CGSEventIsAppUnresponsive")
public func cgsEventIsAppUnresponsive(
    _ connection: CGSConnectionID,
    _ process: UnsafeMutablePointer<ProcessSerialNumber>
) -> Bool

/// How long a process may stall before the call above starts saying yes.
@_silgen_name("CGSEventSetAppIsUnresponsiveNotificationTimeout")
public func cgsEventSetAppIsUnresponsiveNotificationTimeout(
    _ connection: CGSConnectionID,
    _ seconds: Double
) -> CGError

// MARK: - Spaces

/// The space the user is currently looking at.
@_silgen_name("CGSGetActiveSpace")
public func cgsGetActiveSpace(_ connection: CGSConnectionID) -> CGSSpaceID

/// The spaces each of windowIDs appears on, as a CFArray at +1.
///
/// mask is the raw value of a CGSSpaceMask; the C parameter is a plain
/// integer, so the option set is unwrapped by the caller rather than passed as
/// a struct whose layout Swift is free to choose.
@_silgen_name("CGSCopySpacesForWindows")
public func cgsCopySpacesForWindows(
    _ connection: CGSConnectionID,
    _ mask: UInt32,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

/// The space currently shown on the display named by displayUUID.
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
public func cgsManagedDisplayGetCurrentSpace(
    _ connection: CGSConnectionID,
    _ displayUUID: CFString
) -> CGSSpaceID

/// The raw space-type tag for spaceID; map it through CGSSpaceType.
@_silgen_name("CGSSpaceGetType")
public func cgsSpaceGetType(
    _ connection: CGSConnectionID,
    _ spaceID: CGSSpaceID
) -> UInt32

/// Every display the window server manages, each with its Spaces array,
/// as a CFArray of dictionaries at +1.
@_silgen_name("CGSCopyManagedDisplaySpaces")
public func cgsCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> Unmanaged<CFArray>?

// MARK: - Window Lists

// The four list calls come in measure/fetch pairs. The measure call reports how
// many identifiers are available; the fetch call takes a buffer sized from that
// answer, plus a second out-parameter telling the caller how many identifiers it
// actually wrote. The two numbers are read in separate round trips and are not
// required to agree, which is why the fetch call reports its own.

/// Counts every window belonging to owner (zero means all clients).
@_silgen_name("CGSGetWindowCount")
public func cgsGetWindowCount(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ count: UnsafeMutablePointer<Int32>
) -> CGError

/// Counts the on-screen windows belonging to owner.
@_silgen_name("CGSGetOnScreenWindowCount")
public func cgsGetOnScreenWindowCount(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ count: UnsafeMutablePointer<Int32>
) -> CGError

/// Fills buffer with up to capacity window identifiers, reporting how many
/// it wrote through written.
@_silgen_name("CGSGetWindowList")
public func cgsGetWindowList(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ capacity: Int32,
    _ buffer: UnsafeMutablePointer<CGWindowID>,
    _ written: UnsafeMutablePointer<Int32>
) -> CGError

/// As above, restricted to windows the window server considers on screen.
@_silgen_name("CGSGetOnScreenWindowList")
public func cgsGetOnScreenWindowList(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ capacity: Int32,
    _ buffer: UnsafeMutablePointer<CGWindowID>,
    _ written: UnsafeMutablePointer<Int32>
) -> CGError

/// As above, restricted to the windows a process contributes to the menu bar.
///
/// Sized from cgsGetWindowCount: there is no dedicated counting call for
/// this list, and the menu-bar windows are a subset of the process's windows.
@_silgen_name("CGSGetProcessMenuBarWindowList")
public func cgsGetProcessMenuBarWindowList(
    _ connection: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ capacity: Int32,
    _ buffer: UnsafeMutablePointer<CGWindowID>,
    _ written: UnsafeMutablePointer<Int32>
) -> CGError

// MARK: - Window Geometry

/// The window's frame in global display coordinates.
@_silgen_name("CGSGetScreenRectForWindow")
public func cgsGetScreenRectForWindow(
    _ connection: CGSConnectionID,
    _ windowID: CGWindowID,
    _ rect: UnsafeMutablePointer<CGRect>
) -> CGError

/// The window's stacking level.
@_silgen_name("CGSGetWindowLevel")
public func cgsGetWindowLevel(
    _ connection: CGSConnectionID,
    _ windowID: CGWindowID,
    _ level: UnsafeMutablePointer<CGWindowLevel>
) -> CGError

/// Moves a window's top-left origin in global display coordinates. Used by the
/// CGS off-screen hider to push a status-item window outside every display's
/// bounds (and to restore it). Works cross-process via the default connection,
/// without requiring a restriction reflow.
@_silgen_name("CGSMoveWindow")
public func cgsMoveWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ origin: inout CGPoint
) -> CGError

// MARK: - Processes

/// Resolves a BSD process identifier to the Process Manager serial number that
/// the window server's per-process calls address.
@_silgen_name("GetProcessForPID")
public func getProcessForPID(
    _ pid: pid_t,
    _ process: UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

/// Resolves the CGS connection ID owning a process (identified by its PSN) so
/// its menu-bar item windows can be enumerated via
/// cgsGetProcessMenuBarWindowList.
@_silgen_name("CGSGetConnectionIDForPSN")
public func cgsGetConnectionIDForPSN(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber,
    _ outTargetCID: inout CGSConnectionID
) -> CGError

// MARK: - SkyLight window capture

/// SLWindowListCreateImageFromArray, loaded at runtime.
///
/// This is the only API that can capture a status-item window parked off the
/// bar. ScreenCaptureKit resolves none of them (on macOS 26/27 it refuses
/// these windows with -3811/-3812), and falling back to the composited
/// display strip makes every crop carry the desktop behind the bar.
public enum SkyLightAPI {
    /// CGRect, CFArray, CGWindowImageOption -> Unmanaged<CGImage>?
    public typealias CreateImageFromArrayFn = @convention(c) (
        CGRect,
        CFArray,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    /// The loaded symbol, or nil when the framework or symbol is missing, in
    /// which case callers fall back to the ScreenCaptureKit path.
    public static let createImageFromArray: CreateImageFromArrayFn? = {
        guard let handle = dlopen(SharedConstants.skyLightFrameworkPath, RTLD_NOW) else {
            return nil
        }
        guard let symbol = dlsym(handle, "SLWindowListCreateImageFromArray") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CreateImageFromArrayFn.self)
    }()
}
