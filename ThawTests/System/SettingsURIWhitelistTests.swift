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
    private func unclaimedBundleID(_ label: String) -> String {
        "com.example.thawtests.\(label).\(UUID().uuidString)"
    }

    /// A sender as the Apple Event's validated signature would name it.
    private func sender(_ bundleID: String, team: String? = nil, hash: String? = "c0ffee") -> SettingsURISender {
        SettingsURISender(bundleIdentifier: bundleID, teamIdentifier: team, codeHash: hash)
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

    @Test("An app that was never approved does not pass the gate", .scratchDefaults)
    func unapprovedSenderIsRefused() {
        #expect(SettingsURIHandler.getWhitelist().isEmpty, "A fresh install approves nobody")
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(unclaimedBundleID("stranger"))))
    }

    @Test("A request whose sender cannot be identified does not pass the gate", .scratchDefaults)
    func unidentifiedSenderIsRefused() {
        // The Apple Event carries no validated signature, or the process it
        // named is gone. Anonymous has to mean refused, not "unknown app".
        #expect(!SettingsURIHandler.isWhitelisted(sender: nil))
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender("")))
    }

    @Test("Approving an app grants access, and the approval is written where a relaunch will find it", .scratchDefaults)
    func approvalGrantsAccessAndPersists() {
        let scratch = Defaults.store
        let bundleID = unclaimedBundleID("approved")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")

        #expect(SettingsURIHandler.isWhitelisted(sender: sender(bundleID, team: "TEAMID1234")))
        #expect(SettingsURIHandler.getWhitelist() == [bundleID])

        // Read the suite directly rather than through the handler: the
        // pane promises the approval survives a quit, so it has to be in
        // the defaults domain and not cached for the life of the process.
        let persisted = scratch.stringArray(forKey: Defaults.Key.settingsURIWhitelist.rawValue)
        #expect(persisted == [bundleID], "The approval must be on disk, not only in memory")
    }

    @Test("Approving the same app twice leaves one entry", .scratchDefaults)
    func approvalIsNotDuplicated() {
        let bundleID = unclaimedBundleID("twice")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID)
        SettingsURIHandler.addToWhitelist(bundleId: bundleID)

        // A duplicate would survive a single removal and silently keep the
        // access the user believes they just revoked.
        #expect(SettingsURIHandler.getWhitelist() == [bundleID])
    }

    @Test("Removing an app revokes its access and forgets the signature it was pinned to", .scratchDefaults)
    func removalRevokesAccessAndForgetsTheSignature() {
        let scratch = Defaults.store
        let bundleID = unclaimedBundleID("revoked")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")
        SettingsURIHandler.removeFromWhitelist(bundleId: bundleID)

        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID, team: "TEAMID1234")))
        #expect(SettingsURIHandler.getWhitelist().isEmpty)

        // The stored team identifier has to go with the entry. Left
        // behind, an app re-approved under the same bundle id would
        // inherit a pin the user never granted it.
        let identities = scratch.data(forKey: Defaults.Key.settingsURISigningIdentities.rawValue)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        #expect(identities[bundleID] == nil, "Revoking must not leave the old signature behind")
    }

    @Test("Being on the list is not enough: an approval pinned to a team identifier dies with it", .scratchDefaults)
    func signatureDriftRevokesAccess() {
        // Another app claiming the approved bundle id, unsigned or signed by
        // another team, is refused even though the id is on the list.
        let bundleID = unclaimedBundleID("pinned")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")

        #expect(SettingsURIHandler.getWhitelist() == [bundleID], "Still listed…")
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID)), "…and still refused")
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID, team: "OTHERTEAM1")))
    }

    @Test("An approval without a team is pinned to the approved code hash", .scratchDefaults)
    func noTeamApprovalNeedsTheSameCode() {
        let scratch = Defaults.store
        let bundleID = unclaimedBundleID("adhoc")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, codeHash: "aaaa")

        #expect(SettingsURIHandler.isWhitelisted(sender: sender(bundleID, hash: "aaaa")))
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID, hash: "bbbb")), "Other unsigned code is refused")
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID, hash: nil)))

        let hashes = scratch.data(forKey: Defaults.Key.settingsURICodeHashes.rawValue)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        #expect(hashes[bundleID] == "aaaa")

        SettingsURIHandler.removeFromWhitelist(bundleId: bundleID)
        let remaining = scratch.data(forKey: Defaults.Key.settingsURICodeHashes.rawValue)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        #expect(remaining[bundleID] == nil, "Revoking forgets the code hash too")
    }

    @Test("An older approval with neither team nor code hash asks again, then is upgraded", .scratchDefaults)
    func legacyNoTeamApprovalIsUpgraded() {
        let bundleID = unclaimedBundleID("legacy")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID)
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID, hash: "aaaa")), "No pin yet, so the user is asked")

        // Approving the prompt records the sender's code hash on the existing entry.
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, codeHash: "aaaa")
        #expect(SettingsURIHandler.getWhitelist() == [bundleID])
        #expect(SettingsURIHandler.isWhitelisted(sender: sender(bundleID, hash: "aaaa")))
    }

    @Test("Approving an app again replaces the identity it was pinned to", .scratchDefaults)
    func reapprovalReplacesThePin() {
        let bundleID = unclaimedBundleID("repinned")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, codeHash: "aaaa")
        SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")

        #expect(SettingsURIHandler.isWhitelisted(sender: sender(bundleID, team: "TEAMID1234")))
        #expect(!SettingsURIHandler.isWhitelisted(sender: sender(bundleID, hash: "aaaa")), "The old code hash no longer counts")

        // A plain add from the settings pane keeps the pin it already has.
        SettingsURIHandler.addToWhitelist(bundleId: bundleID)
        #expect(SettingsURIHandler.isWhitelisted(sender: sender(bundleID, team: "TEAMID1234")))
    }

    @Test("The whole surface is off until the user turns it on", .scratchDefaults)
    func featureGateDefaultsOff() {
        #expect(!SettingsURIHandler.isEnabled(), "thaw:// settings writes are opt-in")
        Defaults.set(true, forKey: .settingsURIEnabled)
        #expect(SettingsURIHandler.isEnabled())
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

        for key in ["settingsURIEnabled", "settingsURIWhitelist", "settingsURISigningIdentities", "settingsURICodeHashes"] {
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

    @Test("An unrecognised key is refused and writes nothing", .scratchDefaults)
    func unknownKeyWritesNothing() {
        let scratch = Defaults.store
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

    @Test("Toggle refuses a key that is not a Boolean", .scratchDefaults, arguments: ["rehideInterval", "rehideStrategy"])
    func toggleRefusesNonBooleanKeys(key: String) {
        let scratch = Defaults.store
        // toggle flips a Bool. Pointed at a duration or an enum it would
        // write true over a number, so it has to refuse rather than
        // coerce, the caller is told to use set instead.
        #expect(!SettingsURIHandler.handleToggle(key: key, sender: unclaimedBundleID("sender")))
        #expect(scratch.object(forKey: key) == nil)
    }

    @Test("Toggle refuses a malformed display UUID, matching set", .scratchDefaults)
    func toggleRefusesMalformedDisplayUUID() {
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

    @Test("A published double is clamped to its range, and non-finite values are refused")
    func doubleWritesAreClampedAndFinite() async throws {
        // tooltipDelay is published with a 0...5 range. The live settings
        // models subscribe to the change notification this posts, so the
        // original value is read before the scratch suite is installed and
        // written back through the same path at the end; the sleep lets the
        // main-queue delivery land while the scratch suite is still current,
        // so nothing a model persists in response reaches the real domain.
        let originalValue = Defaults.double(forKey: .tooltipDelay)
        let suiteName = ScratchDefaults.name("SettingsURIWhitelistTests")
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
        ScratchDefaults.remove(suiteName)
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
