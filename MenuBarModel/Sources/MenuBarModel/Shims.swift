//
//  Shims.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics

// MARK: - Bridged Types

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

    public static let currentSpaceMask: CGSSpaceMask = [.includesUser, .includesCurrent]
    public static let otherSpacesMask: CGSSpaceMask = [.includesOthers, .includesCurrent]
    public static let allSpacesMask: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    public static let allVisibleSpacesMask: CGSSpaceMask = [.visible, .allSpacesMask]
}

// MARK: - CGSConnection

@_silgen_name("CGSMainConnectionID")
public func cgsMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSDefaultConnectionForThread")
public func cgsDefaultConnectionForThread() -> CGSConnectionID

@_silgen_name("CGSCopyConnectionProperty")
public func cgsCopyConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ outValue: inout Unmanaged<CFTypeRef>?
) -> CGError

@_silgen_name("CGSSetConnectionProperty")
public func cgsSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

// MARK: - CGSDisplay

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
public func cgsCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> Unmanaged<CFString>?

// MARK: - CGSEvent

@_silgen_name("CGSEventIsAppUnresponsive")
public func cgsEventIsAppUnresponsive(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber
) -> Bool

@_silgen_name("CGSEventSetAppIsUnresponsiveNotificationTimeout")
public func cgsEventSetAppIsUnresponsiveNotificationTimeout(
    _ cid: CGSConnectionID,
    _ timeout: Double
) -> CGError

// MARK: - CGSSpace

@_silgen_name("CGSGetActiveSpace")
public func cgsGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopySpacesForWindows")
public func cgsCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: CGSSpaceMask,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
public func cgsManagedDisplayGetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString
) -> CGSSpaceID

@_silgen_name("CGSSpaceGetType")
public func cgsSpaceGetType(
    _ cid: CGSConnectionID,
    _ sid: CGSSpaceID
) -> CGSSpaceType

// MARK: - CGSWindow

@_silgen_name("CGSGetWindowCount")
public func cgsGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
public func cgsGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowList")
public func cgsGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
public func cgsGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
public func cgsGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
public func cgsGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

@_silgen_name("CGSGetWindowLevel")
public func cgsGetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outLevel: inout CGWindowLevel
) -> CGError

/// Moves a window's top-left origin in global display coordinates. Used by the
/// CGS off-screen hider to push a status-item window outside every display's
/// bounds (and to restore it). Works cross-process via the default connection,
/// without requiring an assessment-mode reflow.
@_silgen_name("CGSMoveWindow")
public func cgsMoveWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ origin: inout CGPoint
) -> CGError

// MARK: - ProcessSerialNumber

@_silgen_name("GetProcessForPID")
public func getProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus

/// Resolves the CGS connection ID owning a process (identified by its PSN) so
/// its menu-bar item windows can be enumerated via
/// ``cgsGetProcessMenuBarWindowList``.
@_silgen_name("CGSGetConnectionIDForPSN")
public func cgsGetConnectionIDForPSN(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber,
    _ outTargetCID: inout CGSConnectionID
) -> CGError

// MARK: - SkyLight (Private)

/// Returns a safe error message from dlerror(), handling NULL returns.
private func dlerrorMessage() -> String {
    guard let errorPtr = dlerror() else {
        return "unknown dynamic loader error"
    }
    return String(cString: errorPtr)
}

/// Dynamic loader for SkyLight private APIs.
/// Uses dlsym to avoid link-time dependencies on private symbols.
public enum SkyLightAPI {
    private static let diagLog = DiagLog(category: "SkyLightAPI")

    // `UnsafeMutableRawPointer` isn't `Sendable`, so this `static let` can't be
    // plain `Sendable`-checked despite being effectively immutable. Swift
    // guarantees thread-safe, run-once initialization of `static let`
    // properties, and this handle is never reassigned or `dlclose`d after
    // that, so there's nothing to race on.
    private static nonisolated(unsafe) let handle: UnsafeMutableRawPointer? = {
        let handle = dlopen(SharedConstants.skyLightFrameworkPath, RTLD_NOW)
        if handle == nil {
            diagLog.error("Failed to open SkyLight framework: \(dlerrorMessage())")
        } else {
            diagLog.debug("Successfully opened SkyLight framework")
        }
        return handle
    }()

    /// Type alias for SLWindowListCreateImageFromArray function
    public typealias SLWindowListCreateImageFromArrayFn = @convention(c) (
        CGRect,
        CFArray,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    /// Cached function pointer
    public static let createImageFromArray: SLWindowListCreateImageFromArrayFn? = {
        guard let handle else {
            diagLog.error("Cannot load SLWindowListCreateImageFromArray: SkyLight framework handle is nil")
            return nil
        }
        guard let sym = dlsym(handle, "SLWindowListCreateImageFromArray") else {
            diagLog.error("Failed to load SLWindowListCreateImageFromArray symbol: \(dlerrorMessage())")
            return nil
        }
        diagLog.debug("Successfully loaded SLWindowListCreateImageFromArray symbol")
        return unsafeBitCast(sym, to: SLWindowListCreateImageFromArrayFn.self)
    }()
}
