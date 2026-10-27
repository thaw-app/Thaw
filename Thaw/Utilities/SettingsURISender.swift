//
//  SettingsURISender.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Security

/// The app that sent a thaw:// Apple Event, identified through its audit token by its
/// own code signature, so another app can't borrow a grant by claiming its bundle ID.
nonisolated struct SettingsURISender: Equatable {
    let bundleIdentifier: String
    let team: SettingsURIHandler.TeamIdentifierLookup
    /// The name from the sender's own signed Info.plist, shown when asking for approval.
    let displayName: String

    /// The sender of event, or nil when its code can't be found or validated.
    static func identify(from event: NSAppleEventDescriptor) -> SettingsURISender? {
        if let token = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data, !token.isEmpty {
            return identify(auditToken: token)
        }
        guard let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)), let pid = pid(from: descriptor)
        else {
            return nil
        }
        return identify(pid: pid)
    }

    /// The process with this audit token, identified the same way as an event's sender.
    static func identify(auditToken: Data) -> SettingsURISender? {
        identify(guestAttributes: [kSecGuestAttributeAudit: auditToken])
    }

    /// The running process with pid, identified the same way as an event's sender.
    static func identify(pid: pid_t) -> SettingsURISender? {
        identify(guestAttributes: [kSecGuestAttributePid: NSNumber(value: pid)])
    }

    /// The bundle identifier from the signed Info.plist, or the signing identifier for
    /// code without one, the team, and the display name, falling back to the bundle identifier.
    static func identity(fromSigningInfo info: [String: Any]) -> SettingsURISender? {
        let plist = info[kSecCodeInfoPList as String] as? [String: Any]
        guard let bundleIdentifier = (plist?["CFBundleIdentifier"] as? String)
            ?? (info[kSecCodeInfoIdentifier as String] as? String), !bundleIdentifier.isEmpty
        else {
            return nil
        }
        let team: SettingsURIHandler.TeamIdentifierLookup = if let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String {
            .team(teamID)
        } else {
            .noTeamIdentifier
        }
        let displayName = [plist?["CFBundleDisplayName"], plist?["CFBundleName"]]
            .lazy
            .compactMap { $0 as? String }
            .first { !$0.isEmpty } ?? bundleIdentifier
        return SettingsURISender(bundleIdentifier: bundleIdentifier, team: team, displayName: displayName)
    }

    private static func identify(guestAttributes: [CFString: Any]) -> SettingsURISender? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, guestAttributes as CFDictionary, [], &code) == errSecSuccess, let code, SecCodeCheckValidity(code, [], nil) == errSecSuccess
        else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess, let info = info as? [String: Any]
        else {
            return nil
        }
        return identity(fromSigningInfo: info)
    }

    /// macOS 26 stores the sender PID as a UInt32 on arm64, so any integer type is read raw.
    static func pid(from descriptor: NSAppleEventDescriptor) -> pid_t? {
        let integerTypes: Set<OSType> = [typeSInt16, typeSInt32, typeSInt64, typeUInt16, typeUInt32, typeUInt64]
        var pid: pid_t = 0
        if integerTypes.contains(descriptor.descriptorType) {
            let data = descriptor.data
            let copyCount = min(data.count, MemoryLayout<pid_t>.size)
            data.withUnsafeBytes { source in
                withUnsafeMutableBytes(of: &pid) { destination in
                    guard let sourceAddress = source.baseAddress, let destinationAddress = destination.baseAddress else {
                        return
                    }
                    memcpy(destinationAddress, sourceAddress, copyCount)
                }
            }
        } else {
            pid = descriptor.int32Value
        }
        return pid > 0 ? pid : nil
    }
}
