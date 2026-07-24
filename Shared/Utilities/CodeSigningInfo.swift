//
//  CodeSigningInfo.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Security

enum CodeSigningInfo {
    /// The team identifier of the current process, or `nil` when signed
    /// without one (ad-hoc). Used by both the XPC service's `Listener` and
    /// the main app's `MenuBarItemServiceConnection` to decide whether a
    /// same-team peer requirement can ever be satisfied.
    static let processTeamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else {
            return nil
        }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }()
}
