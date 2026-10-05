//
//  SettingsURIBuiltInTrustTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The built-in trust path: a partner app passes the gate without a prompt only
/// when its signature carries this app's team.
@MainActor
@Suite("Settings URI built-in trust", .serialized)
struct SettingsURIBuiltInTrustTests {
    private let floe = "com.thaw.floe"

    private func withScratchDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
        let suiteName = "SettingsURIBuiltInTrustTests.\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suiteName))
        let previous = Defaults.store
        let previousCenter = SettingsURIHandler.settingsChangeNotificationCenter
        Defaults.store = scratch
        SettingsURIHandler.settingsChangeNotificationCenter = NotificationCenter()
        defer {
            SettingsURIHandler.settingsChangeNotificationCenter = previousCenter
            Defaults.store = previous
            scratch.removePersistentDomain(forName: suiteName)
        }
        return try body(scratch)
    }

    @Test("A built-in sender is trusted when both signatures carry the same team", arguments: [
        ("TEAM", "TEAM", true),
        ("OTHER", "TEAM", false),
        (nil, "TEAM", false),
        ("TEAM", nil, false),
    ] as [(String?, String?, Bool)])
    func builtInSenderNeedsTheSameTeam(sender: String?, own: String?, trusted: Bool) {
        var lookedUp = [String]()
        let result = SettingsURIHandler.isBuiltInTrustedSender(
            bundleIdentifier: floe,
            senderTeamID: { bundleID in
                lookedUp.append(bundleID)
                return sender
            },
            ownTeamID: { own }
        )

        #expect(result == trusted)
        #expect(lookedUp == [floe], "The team is read from the sender's own installed app")
    }

    @Test("A sender outside the built-in list is refused without reading any signature", arguments: [
        nil, "", "com.example.other", "com.thaw.floe.helper",
    ] as [String?])
    func otherSendersAreNeverBuiltIn(bundleIdentifier: String?) {
        var lookups = 0
        let result = SettingsURIHandler.isBuiltInTrustedSender(
            bundleIdentifier: bundleIdentifier,
            senderTeamID: { _ in
                lookups += 1
                return "TEAM"
            },
            ownTeamID: {
                lookups += 1
                return "TEAM"
            }
        )

        #expect(!result)
        #expect(lookups == 0)
    }

    @Test("A build with no team of its own never grants built-in trust")
    func unsignedBuildTrustsNobody() {
        let ownTeam = SettingsURIHandler.teamIdentifier(ofAppAt: Bundle.main.bundleURL, logName: "this app")
        let trusted = SettingsURIHandler.isBuiltInTrustedSender(bundleIdentifier: floe)

        #expect(!trusted || ownTeam != nil)
        #expect(!SettingsURIHandler.isBuiltInTrustedSender(bundleIdentifier: floe, ownTeamID: { nil }))
    }

    @Test("A built-in sender passes the gate without being in the approved list")
    func builtInSenderSkipsTheWhitelist() throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.getWhitelist().isEmpty)
            #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: floe) { $0 == floe })
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: floe) { _ in false })
            #expect(SettingsURIHandler.getWhitelist().isEmpty, "Built-in trust is not remembered as an approval")
        }
    }

    @Test("A sender with no identity is refused before built-in trust is consulted", arguments: [nil, ""] as [String?])
    func unidentifiedSenderNeverReachesBuiltInTrust(bundleIdentifier: String?) throws {
        try withScratchDefaults { _ in
            var consulted = false
            let allowed = SettingsURIHandler.isWhitelisted(bundleIdentifier: bundleIdentifier) { _ in
                consulted = true
                return true
            }
            #expect(!allowed)
            #expect(!consulted)
        }
    }

    @Test("Something that is not a signed app has no team")
    func unsignedBundleHasNoTeam() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsURIBuiltInTrustTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(SettingsURIHandler.teamIdentifier(ofAppAt: folder, logName: "empty folder") == nil)
        let missing = folder.appendingPathComponent("Missing.app")
        #expect(SettingsURIHandler.teamIdentifier(ofAppAt: missing, logName: "missing app") == nil)
    }

    @Test("Setting the rehide strategy stores its raw value and announces it")
    func enumSettingIsStoredAndAnnounced() throws {
        try withScratchDefaults { _ in
            nonisolated(unsafe) var announced = [[AnyHashable: Any]]()
            let observer = SettingsURIHandler.settingsChangeNotificationCenter.addObserver(
                forName: .settingsDidChangeViaURI,
                object: nil,
                queue: nil
            ) { note in
                announced.append(note.userInfo ?? [:])
            }
            defer { SettingsURIHandler.settingsChangeNotificationCenter.removeObserver(observer) }

            #expect(SettingsURIHandler.handleSet(key: "rehideStrategy", value: "timed", sender: "com.example.sender"))
            #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.timed.rawValue)
            #expect(announced.count == 1)
            #expect(announced.first?["key"] as? String == "rehideStrategy")
            #expect(announced.first?["rawEnumValue"] as? Int == RehideStrategy.timed.rawValue)

            #expect(!SettingsURIHandler.handleSet(key: "rehideStrategy", value: "sometimes", sender: "com.example.sender"))
            #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.timed.rawValue)
            #expect(announced.count == 1)
        }
    }
}
