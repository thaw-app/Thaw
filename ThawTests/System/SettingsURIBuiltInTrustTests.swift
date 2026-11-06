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

    private func sender(_ bundleID: String, team: String?) -> SettingsURISender {
        SettingsURISender(bundleIdentifier: bundleID, teamIdentifier: team, codeHash: "c0ffee")
    }

    @Test("A built-in sender is trusted when both signatures carry the same team", arguments: [
        ("TEAM", "TEAM", true),
        ("OTHER", "TEAM", false),
        (nil, "TEAM", false),
        ("TEAM", nil, false),
    ] as [(String?, String?, Bool)])
    func builtInSenderNeedsTheSameTeam(senderTeam: String?, own: String?, trusted: Bool) {
        // The team comes from the sending process's own signature, not from an installed app.
        let result = SettingsURIHandler.isBuiltInTrustedSender(sender(floe, team: senderTeam), ownTeamID: { own })
        #expect(result == trusted)
    }

    @Test("A sender outside the built-in list is refused without reading this app's signature", arguments: [
        "", "com.example.other", "com.thaw.floe.helper",
    ])
    func otherSendersAreNeverBuiltIn(bundleIdentifier: String) {
        var lookups = 0
        let result = SettingsURIHandler.isBuiltInTrustedSender(sender(bundleIdentifier, team: "TEAM")) {
            lookups += 1
            return "TEAM"
        }

        #expect(!result)
        #expect(lookups == 0)
        #expect(!SettingsURIHandler.isBuiltInTrustedSender(nil) { "TEAM" })
    }

    @Test("A build with no team of its own never grants built-in trust")
    func unsignedBuildTrustsNobody() {
        let ownTeam = SettingsURIHandler.teamIdentifier(ofAppAt: Bundle.main.bundleURL, logName: "this app")
        let trusted = SettingsURIHandler.isBuiltInTrustedSender(sender(floe, team: "TEAM"))

        #expect(!trusted || ownTeam == "TEAM")
        #expect(!SettingsURIHandler.isBuiltInTrustedSender(sender(floe, team: nil), ownTeamID: { nil }))
    }

    @Test("A built-in sender passes the gate without being in the approved list", .scratchDefaults)
    func builtInSenderSkipsTheWhitelist() throws {
        try withPrivateSettingsChangeCenter {
            let floeSender = sender(floe, team: "TEAM")
            #expect(SettingsURIHandler.getWhitelist().isEmpty)
            #expect(SettingsURIHandler.isWhitelisted(sender: floeSender) { $0.bundleIdentifier == floe })
            #expect(!SettingsURIHandler.isWhitelisted(sender: floeSender) { _ in false })
            #expect(SettingsURIHandler.getWhitelist().isEmpty, "Built-in trust is not remembered as an approval")
        }
    }

    @Test("A sender with no identity is refused before built-in trust is consulted", .scratchDefaults)
    func unidentifiedSenderNeverReachesBuiltInTrust() throws {
        try withPrivateSettingsChangeCenter {
            var consulted = false
            for candidate in [nil, sender("", team: "TEAM")] {
                let allowed = SettingsURIHandler.isWhitelisted(sender: candidate) { _ in
                    consulted = true
                    return true
                }
                #expect(!allowed)
            }
            #expect(!consulted)
        }
    }

    @Test("Something that is not a signed app has no team")
    func unsignedBundleHasNoTeam() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(ScratchDefaults.name("SettingsURIBuiltInTrustTests"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(SettingsURIHandler.teamIdentifier(ofAppAt: folder, logName: "empty folder") == nil)
        let missing = folder.appendingPathComponent("Missing.app")
        #expect(SettingsURIHandler.teamIdentifier(ofAppAt: missing, logName: "missing app") == nil)
    }

    @Test("Setting the rehide strategy stores its raw value and announces it", .scratchDefaults)
    func enumSettingIsStoredAndAnnounced() throws {
        try withPrivateSettingsChangeCenter {
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

@MainActor
@Suite("Module senders")
struct ModuleSenderTrustTests {
    @Test("Thaw's own modules are built-in senders when signed by the same team")
    func modulesAreBuiltIn() {
        #expect(SettingsURIHandler.isBuiltInTrusted(
            bundleId: "com.stonerl.Thaw.module.triggers",
            senderTeamID: "TEAM",
            ownTeamID: "TEAM",
            ownBundleID: "com.stonerl.Thaw"
        ))
        #expect(!SettingsURIHandler.isBuiltInTrusted(
            bundleId: "com.stonerl.Thaw.module.triggers",
            senderTeamID: "OTHER",
            ownTeamID: "TEAM",
            ownBundleID: "com.stonerl.Thaw"
        ))
    }

    @Test(
        "Only an app named after this Thaw's bundle ID counts as its module",
        arguments: ["com.stonerl.Thaw.debug.module.triggers", "com.stonerl.Thaw.module.", "com.stonerl.Thawmodule.x", "com.other.module.triggers"]
    )
    func otherBundlesAreNotModules(bundleId: String) {
        #expect(!SettingsURIHandler.isBuiltInTrusted(
            bundleId: bundleId,
            senderTeamID: "TEAM",
            ownTeamID: "TEAM",
            ownBundleID: "com.stonerl.Thaw"
        ))
    }
}
