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

// MARK: - Process Responsiveness

/// Whether the window server considers the addressed process wedged.
///
/// Returns C bool, so the one-byte Swift Bool is the matching width.
@_silgen_name("CGSEventIsAppUnresponsive")
public func cgsEventIsAppUnresponsive(
    _ connection: CGSConnectionID,
    _ process: UnsafeMutablePointer<ProcessSerialNumber>
) -> Bool

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

// MARK: - Connection Notifications

/// SLSRegisterConnectionNotifyProc, loaded at runtime so that a missing symbol
/// leaves Space changes to the NSWorkspace notification instead of failing launch.
public enum SLSConnectionNotifications {
    /// Event id, payload, payload length, context, connection. Called on
    /// whichever thread receives the window server's message.
    public typealias Proc = @convention(c) (
        UInt32,
        UnsafeMutableRawPointer?,
        Int,
        UnsafeMutableRawPointer?,
        CGSConnectionID
    ) -> Void

    /// Connection, callback, event id, context.
    public typealias Register = @convention(c) (
        CGSConnectionID,
        Proc,
        UInt32,
        UnsafeMutableRawPointer?
    ) -> CGError

    public static let register: Register? = {
        guard let handle = dlopen(SharedConstants.skyLightFrameworkPath, RTLD_LAZY), let symbol = dlsym(handle, "SLSRegisterConnectionNotifyProc") else {
            return nil
        }
        return unsafeBitCast(symbol, to: Register.self)
    }()
}
