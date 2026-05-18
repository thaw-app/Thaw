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

typealias CGSConnectionID = Int32
typealias CGSSpaceID = Int

enum CGSSpaceType: UInt32 {
    case user = 0
    case system = 2
    case fullscreen = 4
}

struct CGSSpaceMask: OptionSet {
    let rawValue: UInt32

    static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    static let includesUser = CGSSpaceMask(rawValue: 1 << 2)

    static let visible = CGSSpaceMask(rawValue: 1 << 16)

    static let currentSpaceMask: CGSSpaceMask = [.includesUser, .includesCurrent]
    static let otherSpacesMask: CGSSpaceMask = [.includesOthers, .includesCurrent]
    static let allSpacesMask: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    static let allVisibleSpacesMask: CGSSpaceMask = [.visible, .allSpacesMask]
}

// MARK: - CGSConnection

@_silgen_name("CGSMainConnectionID")
func cgsMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSDefaultConnectionForThread")
func cgsDefaultConnectionForThread() -> CGSConnectionID

@_silgen_name("CGSCopyConnectionProperty")
func cgsCopyConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ outValue: inout Unmanaged<CFTypeRef>?
) -> CGError

@_silgen_name("CGSSetConnectionProperty")
func cgsSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

// MARK: - CGSDisplay

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
func cgsCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> Unmanaged<CFString>?

// MARK: - CGSEvent

@_silgen_name("CGSEventIsAppUnresponsive")
func cgsEventIsAppUnresponsive(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber
) -> Bool

@_silgen_name("CGSEventSetAppIsUnresponsiveNotificationTimeout")
func cgsEventSetAppIsUnresponsiveNotificationTimeout(
    _ cid: CGSConnectionID,
    _ timeout: Double
) -> CGError

// MARK: - CGSSpace

@_silgen_name("CGSGetActiveSpace")
func cgsGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopySpacesForWindows")
func cgsCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: CGSSpaceMask,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func cgsManagedDisplayGetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString
) -> CGSSpaceID

@_silgen_name("CGSSpaceGetType")
func cgsSpaceGetType(
    _ cid: CGSConnectionID,
    _ sid: CGSSpaceID
) -> CGSSpaceType

// MARK: - CGSWindow

@_silgen_name("CGSGetWindowCount")
func cgsGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
func cgsGetOnScreenWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowList")
func cgsGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
func cgsGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func cgsGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func cgsGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

@_silgen_name("CGSGetWindowLevel")
func cgsGetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outLevel: inout CGWindowLevel
) -> CGError

// MARK: - ProcessSerialNumber

@_silgen_name("GetProcessForPID")
func getProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus

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
enum SkyLightAPI {
    private static let diagLog = DiagLog(category: "SkyLightAPI")

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
    typealias SLWindowListCreateImageFromArrayFn = @convention(c) (
        CGRect,
        CFArray,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    /// Cached function pointer
    static let createImageFromArray: SLWindowListCreateImageFromArrayFn? = {
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
