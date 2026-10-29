//
//  SettingsURISender.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import AppKit
import Security

/// The app that sent a thaw:// Apple Event, identified by its own validated code signature
/// so another app can't borrow a grant by claiming the same bundle ID.
nonisolated struct SettingsURISender: Equatable, Sendable {
    let bundleIdentifier: String

    /// The signing team, or nil for code signed without one.
    let teamIdentifier: String?

    /// The code directory hash in hex, which pins a sender that has no team.
    let codeHash: String?

    /// The name from the sender's own signed Info.plist, or its bundle identifier when that has none.
    let displayName: String

    init(bundleIdentifier: String, teamIdentifier: String?, codeHash: String?, displayName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.codeHash = codeHash
        self.displayName = displayName ?? bundleIdentifier
    }

    /// The sender of event, or nil when its code can't be found or validated.
    static func identify(from event: NSAppleEventDescriptor) -> SettingsURISender? {
        if let token = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data, token.count == MemoryLayout<audit_token_t>.size {
            return identify(guestAttributes: [kSecGuestAttributeAudit: token])
        }
        guard let pid = senderPID(from: event) else { return nil }
        return identify(guestAttributes: [kSecGuestAttributePid: NSNumber(value: pid)])
    }

    /// The bundle identifier from the signed Info.plist, or the signing identifier for code
    /// without one, along with the team, code hash and the name the signed Info.plist gives.
    /// The team is kept only when teamIsAnchored: any signer can write a team into the code directory.
    static func identity(fromSigningInfo info: [String: Any], teamIsAnchored: Bool = false) -> SettingsURISender? {
        let plist = info[kSecCodeInfoPList as String] as? [String: Any]
        let plistIdentifier = (plist?["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let signingIdentifier = (info[kSecCodeInfoIdentifier as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let bundleIdentifier = plistIdentifier ?? signingIdentifier else {
            return nil
        }
        let team = teamIsAnchored ? teamIdentifier(inSigningInfo: info) : nil
        let hash = (info[kSecCodeInfoUnique as String] as? Data).flatMap { $0.isEmpty ? nil : hexString($0) }
        let name = ["CFBundleDisplayName", "CFBundleName"].firstNonNil { key in
            (plist?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return SettingsURISender(bundleIdentifier: bundleIdentifier, teamIdentifier: team, codeHash: hash, displayName: name)
    }

    /// Whether this sender is the one a stored grant was made for. A grant with a team needs that
    /// team; a grant without one needs a sender without a team and the same code hash.
    func matchesGrant(storedTeamIdentifier: String?, storedCodeHash: String?) -> Bool {
        if let storedTeamIdentifier {
            return teamIdentifier == storedTeamIdentifier
        }
        guard teamIdentifier == nil, let storedCodeHash, let codeHash else {
            return false
        }
        return codeHash.caseInsensitiveCompare(storedCodeHash) == .orderedSame
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
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
        return identity(of: staticCode)
    }

    /// The identity in the validated signature of the app at url, for an app the user picks by hand.
    static func identify(appAt url: URL) -> SettingsURISender? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
        else {
            return nil
        }
        return identity(of: staticCode)
    }

    private static func identity(of staticCode: SecStaticCode) -> SettingsURISender? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess, let info = info as? [String: Any]
        else {
            return nil
        }
        let anchored = teamIdentifier(inSigningInfo: info).map { isAnchored(staticCode, toTeam: $0) } ?? false
        return identity(fromSigningInfo: info, teamIsAnchored: anchored)
    }

    private static func teamIdentifier(inSigningInfo info: [String: Any]) -> String? {
        (info[kSecCodeInfoTeamIdentifier as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A requirement that only an Apple-issued developer certificate for team satisfies, or nil
    /// when team isn't a team ID, so nothing a signer wrote can change the requirement's meaning.
    static func anchoredTeamRequirement(_ team: String) -> String? {
        guard team.wholeMatch(of: /[A-Z0-9]{10}/) != nil else { return nil }
        return #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
    }

    private static func isAnchored(_ staticCode: SecStaticCode, toTeam team: String) -> Bool {
        var requirement: SecRequirement?
        guard let text = anchoredTeamRequirement(team),
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else {
            return false
        }
        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }

    /// macOS 26 stores the sender PID as a UInt32 on arm64, so any integer type is read raw.
    private static func senderPID(from event: NSAppleEventDescriptor) -> pid_t? {
        guard let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            return nil
        }
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
