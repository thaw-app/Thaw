//
//  SettingsURISenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Security
import Testing
@testable import Thaw

@MainActor
@Suite("Settings URI sender", .serialized)
struct SettingsURISenderTests {
    @Test("The bundle identifier comes from the signed Info.plist")
    func bundleIdentifierFromPlist() {
        let sender = SettingsURISender.identity(fromSigningInfo: [
            kSecCodeInfoPList as String: ["CFBundleIdentifier": "com.example.Real"],
            kSecCodeInfoIdentifier as String: "com.example.signing",
            kSecCodeInfoTeamIdentifier as String: "AB12CD34EF",
        ])

        #expect(sender == SettingsURISender(bundleIdentifier: "com.example.Real", team: .team("AB12CD34EF"), displayName: "com.example.Real"))
    }

    @Test("The display name comes from the sender's own Info.plist", arguments: [
        (["CFBundleIdentifier": "com.example.Real", "CFBundleDisplayName": "Shown", "CFBundleName": "Named"], "Shown"),
        (["CFBundleIdentifier": "com.example.Real", "CFBundleDisplayName": "", "CFBundleName": "Named"], "Named"),
        (["CFBundleIdentifier": "com.example.Real"], "com.example.Real"),
    ])
    func displayNameFromPlist(plist: [String: String], expected: String) {
        let sender = SettingsURISender.identity(fromSigningInfo: [kSecCodeInfoPList as String: plist])

        #expect(sender?.displayName == expected)
    }

    @Test("Code without an Info.plist falls back to its signing identifier and no team")
    func signingIdentifierFallback() {
        let sender = SettingsURISender.identity(fromSigningInfo: [
            kSecCodeInfoIdentifier as String: "com.example.tool",
        ])

        #expect(sender == SettingsURISender(bundleIdentifier: "com.example.tool", team: .noTeamIdentifier, displayName: "com.example.tool"))
    }

    @Test("Code with no identifier at all is not a sender")
    func noIdentifier() {
        #expect(SettingsURISender.identity(fromSigningInfo: [:]) == nil)
        #expect(SettingsURISender.identity(fromSigningInfo: [kSecCodeInfoIdentifier as String: ""]) == nil)
    }

    @Test("A running process is identified from its own code")
    func identifiesRunningProcess() {
        let sender = SettingsURISender.identify(pid: ProcessInfo.processInfo.processIdentifier)

        #expect(sender?.bundleIdentifier.isEmpty == false)
    }

    @Test("A process that doesn't exist is not identified")
    func missingProcess() {
        #expect(SettingsURISender.identify(pid: 999_999) == nil)
    }

    @Test("Only toggling the Thaw Bar saves a setting")
    func persistingActions() {
        #expect(SettingsURIAction.allCases.filter(\.persistsSettings) == [.toggleThawbar])
    }

    @Test("A sender claiming an approved bundle ID is checked against its own team")
    func impostorIsRefused() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Approved", teamIdentifier: "AB12CD34EF")

            #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Approved", senderIdentity: .team("AB12CD34EF")))
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Approved", senderIdentity: .team("ZZ99ZZ99ZZ")))
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Approved", senderIdentity: .noTeamIdentifier))
        }
    }

    @Test("A signed sender doesn't match a grant made without a team")
    func signedSenderAgainstUnsignedGrant() throws {
        try withScratchDefaults { _ in
            SettingsURIHandler.addToWhitelist(bundleId: "com.example.Script")

            #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Script", senderIdentity: .noTeamIdentifier))
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: "com.example.Script", senderIdentity: .team("AB12CD34EF")))
        }
    }
}
