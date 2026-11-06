//
//  ProcessDisplayName.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Renames this process in the Dock, the app switcher and Force Quit, so the settings process
/// doesn't share the app's name. There is no public call; Chromium names its helpers this way.
enum ProcessDisplayName {
    private typealias GetASN = @convention(c) () -> CFTypeRef?
    private typealias SetItem = @convention(c) (Int32, CFTypeRef, CFString, CFTypeRef, UnsafeMutableRawPointer?) -> OSStatus

    @discardableResult
    static func set(_ name: String) -> Bool {
        guard
            let handle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY),
            let getASNSymbol = dlsym(handle, "_LSGetCurrentApplicationASN"),
            let setItemSymbol = dlsym(handle, "_LSSetApplicationInformationItem"),
            let keySymbol = dlsym(handle, "_kLSDisplayNameKey")
        else {
            return false
        }
        let getASN = unsafeBitCast(getASNSymbol, to: GetASN.self)
        let setItem = unsafeBitCast(setItemSymbol, to: SetItem.self)
        let key = keySymbol.assumingMemoryBound(to: CFString.self).pointee
        guard let asn = getASN() else { return false }
        // -2 is the current login session.
        return setItem(-2, asn, key, name as CFString, nil) == noErr
    }
}
