//
//  SettingsURIWhitelistTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Keeps the Automation pane's thaw:// promises honest.
///
/// The pane tells the user four things: an app Thaw does not recognise cannot
/// change a setting, approval is asked for once and then remembered, an
/// approved app stays pinned to the signature it was approved with, and
/// removing it takes the access away. These tests make SettingsURIHandler,
/// the gate every external write passes through, enforce those claims.
///
/// Each test points Defaults.store at a throwaway suite first, so none of
/// this touches the tester's real com.stonerl.Thaw domain or approved apps.
@MainActor
@Suite("Settings URI whitelist gate", .serialized)
struct SettingsURIWhitelistTests {
    /// A bundle identifier no installed app can claim.
    ///
    /// The gate resolves a sender through LaunchServices, so a fabricated id
    /// is what makes these tests deterministic: the lookup finds nothing and
    /// the "current team identifier" is reliably nil.
    private func unclaimedBundleID(_ label: String) -> String {
        "com.example.thawtests.\(label).\(UUID().uuidString)"
    }

    /// Runs body with Defaults pointed at an empty, throwaway suite.
    private func withScratchDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
        let suiteName = "SettingsURIWhitelistTests.\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suiteName))
        let previous = Defaults.store
        Defaults.store = scratch
        defer {
            Defaults.store = previous
            scratch.removePersistentDomain(forName: suiteName)
        }
        return try body(scratch)
    }

    // MARK: - Who may write

    @Test("A built-in app is trusted only when signed by this app's team")
    func builtInTrustNeedsTheSameTeam() {
        let floe = "com.thaw.floe"
        #expect(SettingsURIHandler.isBuiltInTrusted(bundleId: floe, senderTeamID: "TEAM", ownTeamID: "TEAM"))
        #expect(!SettingsURIHandler.isBuiltInTrusted(bundleId: floe, senderTeamID: "OTHER", ownTeamID: "TEAM"))
        #expect(!SettingsURIHandler.isBuiltInTrusted(bundleId: floe, senderTeamID: nil, ownTeamID: "TEAM"))
        #expect(!SettingsURIHandler.isBuiltInTrusted(bundleId: floe, senderTeamID: "TEAM", ownTeamID: nil))
        #expect(!SettingsURIHandler.isBuiltInTrusted(bundleId: floe, senderTeamID: nil, ownTeamID: nil))
        #expect(!SettingsURIHandler.isBuiltInTrusted(bundleId: "com.example.other", senderTeamID: "TEAM", ownTeamID: "TEAM"))
    }

    @Test("An app that was never approved does not pass the gate")
    func unapprovedSenderIsRefused() throws {
        try withScratchDefaults { _ in
            #expect(SettingsURIHandler.getWhitelist().isEmpty, "A fresh install approves nobody")
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: unclaimedBundleID("stranger")))
        }
    }

    @Test("A request whose sender cannot be identified does not pass the gate", arguments: [nil, ""] as [String?])
    func unidentifiedSenderIsRefused(bundleIdentifier: String?) throws {
        try withScratchDefaults { _ in
            // The Apple Event carries no usable sender PID, or the process it
            // named is gone. Anonymous has to mean refused, not "unknown app".
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: bundleIdentifier))
        }
    }

    @Test("Approving an app grants access, and the approval is written where a relaunch will find it")
    func approvalGrantsAccessAndPersists() throws {
        try withScratchDefaults { scratch in
            let bundleID = unclaimedBundleID("approved")
            SettingsURIHandler.addToWhitelist(bundleId: bundleID)

            #expect(SettingsURIHandler.isWhitelisted(bundleIdentifier: bundleID))
            #expect(SettingsURIHandler.getWhitelist() == [bundleID])

            // Read the suite directly rather than through the handler: the
            // pane promises the approval survives a quit, so it has to be in
            // the defaults domain and not cached for the life of the process.
            let persisted = scratch.stringArray(forKey: Defaults.Key.settingsURIWhitelist.rawValue)
            #expect(persisted == [bundleID], "The approval must be on disk, not only in memory")
        }
    }

    @Test("Approving the same app twice leaves one entry")
    func approvalIsNotDuplicated() throws {
        try withScratchDefaults { _ in
            let bundleID = unclaimedBundleID("twice")
            SettingsURIHandler.addToWhitelist(bundleId: bundleID)
            SettingsURIHandler.addToWhitelist(bundleId: bundleID)

            // A duplicate would survive a single removal and silently keep the
            // access the user believes they just revoked.
            #expect(SettingsURIHandler.getWhitelist() == [bundleID])
        }
    }

    @Test("Removing an app revokes its access and forgets the signature it was pinned to")
    func removalRevokesAccessAndForgetsTheSignature() throws {
        try withScratchDefaults { scratch in
            let bundleID = unclaimedBundleID("revoked")
            SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")
            SettingsURIHandler.removeFromWhitelist(bundleId: bundleID)

            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: bundleID))
            #expect(SettingsURIHandler.getWhitelist().isEmpty)

            // The stored team identifier has to go with the entry. Left
            // behind, an app re-approved under the same bundle id would
            // inherit a pin the user never granted it.
            let identities = scratch.data(forKey: Defaults.Key.settingsURISigningIdentities.rawValue)
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            #expect(identities[bundleID] == nil, "Revoking must not leave the old signature behind")
        }
    }

    @Test("Being on the list is not enough: an approval pinned to a team identifier dies with it")
    func signatureDriftRevokesAccess() throws {
        try withScratchDefaults { _ in
            // Nothing installed claims this bundle id, so its current team
            // identifier resolves to nil while the stored one says otherwise.
            // That is the same shape as an approved app being replaced by an
            // unsigned or differently signed binary at the same bundle id.
            let bundleID = unclaimedBundleID("pinned")
            SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")

            #expect(SettingsURIHandler.getWhitelist() == [bundleID], "Still listed…")
            #expect(!SettingsURIHandler.isWhitelisted(bundleIdentifier: bundleID), "…and still refused")
        }
    }

    @Test("The whole surface is off until the user turns it on")
    func featureGateDefaultsOff() throws {
        try withScratchDefaults { _ in
            #expect(!SettingsURIHandler.isEnabled(), "thaw:// settings writes are opt-in")
            Defaults.set(true, forKey: .settingsURIEnabled)
            #expect(SettingsURIHandler.isEnabled())
        }
    }

    // MARK: - What may be written

    @Test("The keys that guard the gate are not reachable through the gate")
    func theGateIsNotReachableThroughItself() {
        // An app that could write these would approve itself, un-pin its own
        // signature, or switch the surface on behind the user's back. They
        // have to stay off the published key list for good.
        let published = SettingsURIHandler.supportedBooleanKeys
            + SettingsURIHandler.doubleKeys
            + SettingsURIHandler.enumKeys
            + SettingsURIHandler.perDisplayKeys
        // An empty list is not a pass: it would satisfy every check below.
        #expect(!published.isEmpty, "No keys were published; the allow-list check proves nothing")

        for key in ["settingsURIEnabled", "settingsURIWhitelist", "settingsURISigningIdentities"] {
            #expect(!published.contains(key))
            #expect(!SettingsURIHandler.isValidSettingsKey(key), "\(key) must not be settable over thaw://")
        }

        for key in published {
            let lowered = key.lowercased()
            #expect(
                !lowered.contains("settingsuri") && !lowered.contains("whitelist"),
                "\(key) looks like part of the authorization machinery and must not be published"
            )
        }
    }

    @Test("An unrecognised key is refused and writes nothing")
    func unknownKeyWritesNothing() throws {
        try withScratchDefaults { scratch in
            let sender = unclaimedBundleID("sender")

            #expect(!SettingsURIHandler.handleSet(key: "notASetting", value: "true", sender: sender))
            #expect(!SettingsURIHandler.handleToggle(key: "notASetting", sender: sender))
            #expect(!SettingsURIHandler.handleSet(key: "settingsURIWhitelist", value: "true", sender: sender))

            #expect(scratch.object(forKey: "notASetting") == nil, "A refused write must not fall through")
            #expect(
                scratch.stringArray(forKey: Defaults.Key.settingsURIWhitelist.rawValue) == nil,
                "A refused write must not reach the approval list"
            )
        }
    }

    @Test("Toggle refuses a key that is not a Boolean", arguments: ["rehideInterval", "rehideStrategy"])
    func toggleRefusesNonBooleanKeys(key: String) throws {
        try withScratchDefaults { scratch in
            // toggle flips a Bool. Pointed at a duration or an enum it would
            // write true over a number, so it has to refuse rather than
            // coerce, the caller is told to use set instead.
            #expect(!SettingsURIHandler.handleToggle(key: key, sender: unclaimedBundleID("sender")))
            #expect(scratch.object(forKey: key) == nil)
        }
    }

    @Test("Toggle refuses a malformed display UUID, matching set")
    func toggleRefusesMalformedDisplayUUID() throws {
        try withScratchDefaults { _ in
            let sender = unclaimedBundleID("sender")
            // Both contain a hyphen, which the old shape check accepted, but
            // neither is a UUID. set has always refused them; toggle must
            // reach the same verdict.
            for malformed in ["not-a-uuid", "abc-def"] {
                #expect(
                    !SettingsURIHandler.handleToggle(key: "useThawBar", sender: sender, displayUUID: malformed),
                    "\(malformed) is not a display UUID"
                )
            }
        }
    }

    @Test("A published double is clamped to its range, and non-finite values are refused")
    func doubleWritesAreClampedAndFinite() async throws {
        // tooltipDelay is published with a 0...5 range. The live settings
        // models subscribe to the change notification this posts, so the
        // original value is read before the scratch suite is installed and
        // written back through the same path at the end; the sleep lets the
        // main-queue delivery land while the scratch suite is still current,
        // so nothing a model persists in response reaches the real domain.
        let originalValue = Defaults.double(forKey: .tooltipDelay)
        let suiteName = "SettingsURIWhitelistTests.\(UUID().uuidString)"
        let scratch = try #require(UserDefaults(suiteName: suiteName))
        let previousStore = Defaults.store
        Defaults.store = scratch
        let sender = unclaimedBundleID("sender")

        #expect(SettingsURIHandler.handleSet(key: "tooltipDelay", value: "99", sender: sender))
        #expect(Defaults.double(forKey: .tooltipDelay) == 5, "Out of range is clamped, not rejected")

        #expect(SettingsURIHandler.handleSet(key: "tooltipDelay", value: "-4", sender: sender))
        #expect(Defaults.double(forKey: .tooltipDelay) == 0)

        #expect(SettingsURIHandler.handleSet(key: "tooltipDelay", value: "2", sender: sender))
        #expect(Defaults.double(forKey: .tooltipDelay) == 2, "An approved in-range write lands unchanged")

        // Neither of these may overwrite the value the previous write left.
        #expect(!SettingsURIHandler.handleSet(key: "tooltipDelay", value: "nan", sender: sender))
        #expect(!SettingsURIHandler.handleSet(key: "tooltipDelay", value: "inf", sender: sender))
        #expect(!SettingsURIHandler.handleSet(key: "tooltipDelay", value: "later", sender: sender))
        #expect(Defaults.double(forKey: .tooltipDelay) == 2)

        _ = SettingsURIHandler.handleSet(key: "tooltipDelay", value: String(originalValue), sender: sender)
        try await Task.sleep(for: .milliseconds(100))
        Defaults.store = previousStore
        scratch.removePersistentDomain(forName: suiteName)
    }

    @Test("Ice-era key names still resolve to their current spelling")
    func legacyKeyNamesStillResolve() {
        // Scripts written before the rename keep working; a dropped alias is a
        // silent breakage in somebody's automation, not a visible error.
        #expect(SettingsURIHandler.canonicalKey("showIceIcon") == "showThawIcon")
        #expect(SettingsURIHandler.canonicalKey("useIceBar") == "useThawBar")
        #expect(SettingsURIHandler.isValidSettingsKey("showIceIcon"))
        #expect(SettingsURIHandler.canonicalKey("showThawIcon") == "showThawIcon", "Current names pass through")
    }
}
