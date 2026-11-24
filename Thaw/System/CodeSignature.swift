//
//  CodeSignature.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Security

/// The code signature of an app on disk or a running process. Nothing is
/// validated until a caller asks, so each caller chooses its own checks.
nonisolated struct CodeSignature {
    /// A Security call that failed, with the status it returned.
    struct Failure: Error {
        let status: OSStatus
    }

    let staticCode: SecStaticCode

    init(staticCode: SecStaticCode) {
        self.staticCode = staticCode
    }

    /// The signature of the app at url. Creating it doesn't check the signature.
    init(appAt url: URL) throws(Failure) {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw Failure(status: status)
        }
        self.staticCode = staticCode
    }

    /// Whether the whole signature checks out under flags.
    func isValid(flags: SecCSFlags = []) -> Bool {
        SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess
    }

    /// The signing information, read without validating the signature.
    func signingInformation() throws(Failure) -> [String: Any] {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let info = info as? [String: Any] else {
            throw Failure(status: status)
        }
        return info
    }

    /// The team in signing information, or nil when it names none. Any signer can
    /// write a team into its code directory; isAnchored(toTeam:) proves the team.
    static func teamIdentifier(in info: [String: Any]) -> String? {
        (info[kSecCodeInfoTeamIdentifier as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A requirement that only an Apple-issued developer certificate for team satisfies, or nil
    /// when team isn't a team ID, so nothing a signer wrote can change the requirement's meaning.
    static func anchoredTeamRequirement(_ team: String) -> String? {
        guard team.wholeMatch(of: /[A-Z0-9]{10}/) != nil else { return nil }
        return #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
    }

    /// Whether an Apple-issued developer certificate for team signed this code.
    func isAnchored(toTeam team: String) -> Bool {
        var requirement: SecRequirement?
        guard let text = Self.anchoredTeamRequirement(team),
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else {
            return false
        }
        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}
