//
//  SettingsURISenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Security
import Testing
@testable import Thaw

/// How a thaw:// sender is named from its own signature, and which stored approvals it matches.
@Suite("Settings URI sender identity")
struct SettingsURISenderTests {
    private let hashBytes = Data([0x0A, 0xFF, 0x10, 0x00])

    @Test("The signed Info.plist bundle ID wins over the signing identifier")
    func plistBundleIdentifierWins() throws {
        let info: [String: Any] = [
            kSecCodeInfoPList as String: ["CFBundleIdentifier": "com.example.app"],
            kSecCodeInfoIdentifier as String: "com.example.signing",
            kSecCodeInfoTeamIdentifier as String: "TEAM123456",
            kSecCodeInfoUnique as String: hashBytes,
        ]
        let sender = try #require(SettingsURISender.identity(fromSigningInfo: info))
        #expect(sender.bundleIdentifier == "com.example.app")
        #expect(sender.teamIdentifier == "TEAM123456")
        #expect(sender.codeHash == "0aff1000")
    }

    @Test("Code without an Info.plist is named by its signing identifier and may have no team")
    func signingIdentifierIsTheFallback() throws {
        let info: [String: Any] = [
            kSecCodeInfoPList as String: ["CFBundleIdentifier": ""],
            kSecCodeInfoIdentifier as String: "thawctl",
            kSecCodeInfoUnique as String: hashBytes,
        ]
        let sender = try #require(SettingsURISender.identity(fromSigningInfo: info))
        #expect(sender.bundleIdentifier == "thawctl")
        #expect(sender.teamIdentifier == nil)
        #expect(sender.codeHash == "0aff1000")
    }

    @Test("Signing information that names nothing gives no sender", arguments: [
        [:],
        [kSecCodeInfoIdentifier as String: ""],
        [kSecCodeInfoTeamIdentifier as String: "TEAM123456"],
    ] as [[String: String]])
    func unnamedCodeIsNoSender(info: [String: String]) {
        #expect(SettingsURISender.identity(fromSigningInfo: info) == nil)
    }

    @Test("The display name comes from the signed Info.plist, preferring the display name")
    func displayNameComesFromSignedPlist() throws {
        let info: [String: Any] = [
            kSecCodeInfoPList as String: [
                "CFBundleIdentifier": "com.example.app",
                "CFBundleDisplayName": "Example Display",
                "CFBundleName": "Example",
            ],
        ]
        let sender = try #require(SettingsURISender.identity(fromSigningInfo: info))
        #expect(sender.displayName == "Example Display")
    }

    @Test("The bundle name stands in for an absent or empty display name")
    func bundleNameIsTheFirstFallback() throws {
        let info: [String: Any] = [
            kSecCodeInfoPList as String: [
                "CFBundleIdentifier": "com.example.app",
                "CFBundleDisplayName": "",
                "CFBundleName": "Example",
            ],
        ]
        let sender = try #require(SettingsURISender.identity(fromSigningInfo: info))
        #expect(sender.displayName == "Example")
    }

    @Test("A sender whose signed Info.plist names nothing is shown by its bundle identifier")
    func bundleIdentifierIsTheLastFallback() throws {
        let info: [String: Any] = [
            kSecCodeInfoPList as String: ["CFBundleIdentifier": "com.example.app", "CFBundleName": ""],
        ]
        let sender = try #require(SettingsURISender.identity(fromSigningInfo: info))
        #expect(sender.displayName == "com.example.app")
        let bare = try #require(SettingsURISender.identity(fromSigningInfo: [kSecCodeInfoIdentifier as String: "thawctl"]))
        #expect(bare.displayName == "thawctl")
    }

    @Test("An empty team or code hash counts as none")
    func emptyValuesAreAbsent() throws {
        let info: [String: Any] = [
            kSecCodeInfoIdentifier as String: "com.example.app",
            kSecCodeInfoTeamIdentifier as String: "",
            kSecCodeInfoUnique as String: Data(),
        ]
        let sender = try #require(SettingsURISender.identity(fromSigningInfo: info))
        #expect(sender.teamIdentifier == nil)
        #expect(sender.codeHash == nil)
    }

    @Test("An event without a sender attribute identifies nobody")
    func eventWithoutSenderIsAnonymous() {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(SettingsURISender.identify(from: event) == nil)
    }

    @Test("An event whose sender PID is this process is identified from this process's own signature")
    func eventFromThisProcessIsIdentified() {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setAttribute(NSAppleEventDescriptor(int32: getpid()), forKeyword: AEKeyword(keySenderPIDAttr))

        // An unsigned test host may fail validation; when it passes, the name comes from the signature.
        if let sender = SettingsURISender.identify(from: event) {
            #expect(!sender.bundleIdentifier.isEmpty)
            #expect(sender.codeHash != nil)
        }

        event.setAttribute(NSAppleEventDescriptor(int32: -1), forKeyword: AEKeyword(keySenderPIDAttr))
        #expect(SettingsURISender.identify(from: event) == nil)
    }

    @Test("A grant with a team matches only a sender with that team", arguments: [
        ("TEAM", nil, true),
        ("TEAM", "abc", true),
        ("OTHER", nil, false),
        (nil, "abc", false),
    ] as [(String?, String?, Bool)])
    func teamGrantNeedsTheTeam(senderTeam: String?, senderHash: String?, matches: Bool) {
        let sender = SettingsURISender(bundleIdentifier: "com.example.app", teamIdentifier: senderTeam, codeHash: senderHash)
        #expect(sender.matchesGrant(storedTeamIdentifier: "TEAM", storedCodeHash: nil) == matches)
    }

    @Test("A grant without a team matches only the same code without a team", arguments: [
        (nil, "abc", "abc", true),
        (nil, "ABC", "abc", true),
        (nil, "def", "abc", false),
        (nil, nil, "abc", false),
        ("TEAM", "abc", "abc", false),
        (nil, "abc", nil, false),
        (nil, nil, nil, false),
    ] as [(String?, String?, String?, Bool)])
    func noTeamGrantNeedsTheCodeHash(senderTeam: String?, senderHash: String?, storedHash: String?, matches: Bool) {
        let sender = SettingsURISender(bundleIdentifier: "com.example.app", teamIdentifier: senderTeam, codeHash: senderHash)
        #expect(sender.matchesGrant(storedTeamIdentifier: nil, storedCodeHash: storedHash) == matches)
    }
}
