//
//  ModuleLaunchRulesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawModuleKit

@MainActor
@Suite("Module manifest")
struct ModuleManifestTests {
    private let validInfo: [String: Any] = [
        "CFBundleIdentifier": "com.thaw.module.automation",
        "CFBundleShortVersionString": "1.2.0",
        "CFBundleName": "Scripts",
        ModuleManifest.identifierKey: "automation",
        ModuleManifest.minimumAPIVersionKey: 1,
    ]

    @Test("A complete Info.plist gives a manifest")
    func readsACompleteManifest() throws {
        let manifest = try #require(ModuleManifest(infoDictionary: validInfo))
        #expect(manifest.identifier == "automation")
        #expect(manifest.bundleIdentifier == "com.thaw.module.automation")
        #expect(manifest.version == "1.2.0")
        #expect(manifest.name == "Scripts")
        #expect(manifest.minimumAPIVersion == 1)
    }

    @Test(
        "An Info.plist without a module identity is not a module",
        arguments: [
            ModuleManifest.identifierKey,
            ModuleManifest.minimumAPIVersionKey,
            "CFBundleIdentifier",
        ]
    )
    func rejectsAMissingKey(_ key: String) {
        var info = validInfo
        info.removeValue(forKey: key)
        #expect(ModuleManifest(infoDictionary: info) == nil)
    }

    @Test("An empty identifier or an API version below 1 is not a module")
    func rejectsInvalidValues() {
        var emptyIdentifier = validInfo
        emptyIdentifier[ModuleManifest.identifierKey] = ""
        var zeroVersion = validInfo
        zeroVersion[ModuleManifest.minimumAPIVersionKey] = 0
        #expect(ModuleManifest(infoDictionary: emptyIdentifier) == nil)
        #expect(ModuleManifest(infoDictionary: zeroVersion) == nil)
    }

    @Test("A missing short version reads as 0")
    func defaultsTheVersion() throws {
        var info = validInfo
        info.removeValue(forKey: "CFBundleShortVersionString")
        let manifest = try #require(ModuleManifest(infoDictionary: info))
        #expect(manifest.version == "0")
    }

    @Test("A missing bundle name falls back to the identifier")
    func defaultsTheName() throws {
        var info = validInfo
        info.removeValue(forKey: "CFBundleName")
        let manifest = try #require(ModuleManifest(infoDictionary: info))
        #expect(manifest.name == "automation")
    }
}

@MainActor
@Suite("Module launch rules")
struct ModuleLaunchRulesTests {
    private let manifest = ModuleManifest(
        identifier: "automation",
        bundleIdentifier: "com.thaw.module.automation",
        version: "1.0.0",
        minimumAPIVersion: 1
    )

    @Test("A module signed by Thaw's team that fits this API version launches")
    func launchesATrustedCompatibleModule() {
        let verdict = ModuleLaunchRules.verdict(manifest: manifest, moduleTeamID: "TEAM", ownTeamID: "TEAM", apiVersion: 1)
        #expect(verdict == .launch)
    }

    @Test("A bundle without a manifest is not launched")
    func refusesABundleWithoutAManifest() {
        let verdict = ModuleLaunchRules.verdict(manifest: nil, moduleTeamID: "TEAM", ownTeamID: "TEAM", apiVersion: 1)
        #expect(verdict == .notAModule)
    }

    @Test(
        "A module is untrusted unless both team IDs are known and equal",
        arguments: [("OTHER", "TEAM"), (nil, "TEAM"), ("TEAM", nil), (nil, nil)] as [(String?, String?)]
    )
    func refusesAnotherTeam(moduleTeamID: String?, ownTeamID: String?) {
        let verdict = ModuleLaunchRules.verdict(manifest: manifest, moduleTeamID: moduleTeamID, ownTeamID: ownTeamID, apiVersion: 1)
        #expect(verdict == .untrusted)
    }

    @Test("A module that needs a newer API waits for a Thaw update")
    func refusesAModuleThatNeedsANewerThaw() {
        let newer = ModuleManifest(
            identifier: "automation",
            bundleIdentifier: "com.thaw.module.automation",
            version: "2.0.0",
            minimumAPIVersion: 3
        )
        let verdict = ModuleLaunchRules.verdict(manifest: newer, moduleTeamID: "TEAM", ownTeamID: "TEAM", apiVersion: 2)
        #expect(verdict == .needsNewerThaw(requiredAPIVersion: 3))
    }

    @Test("Trust is checked before the API version")
    func checksTrustFirst() {
        let newer = ModuleManifest(
            identifier: "automation",
            bundleIdentifier: "com.thaw.module.automation",
            version: "2.0.0",
            minimumAPIVersion: 3
        )
        let verdict = ModuleLaunchRules.verdict(manifest: newer, moduleTeamID: "OTHER", ownTeamID: "TEAM", apiVersion: 2)
        #expect(verdict == .untrusted)
    }
}

@MainActor
@Suite("Module restart policy")
struct ModuleRestartPolicyTests {
    private let policy = ModuleRestartPolicy(window: 600, maxCrashes: 5, baseDelay: 1, maxDelay: 30)
    private let now = Date(timeIntervalSinceReferenceDate: 10000)

    @Test("The first crash restarts after the base delay")
    func restartsAfterTheFirstCrash() {
        #expect(policy.decision(crashes: [now], now: now) == .restart(after: 1))
    }

    @Test("Each further crash in the window doubles the delay")
    func doublesTheDelay() {
        let crashes = (0 ..< 4).map { now.addingTimeInterval(TimeInterval(-$0 * 10)) }
        #expect(policy.decision(crashes: crashes, now: now) == .restart(after: 8))
    }

    @Test("The delay never passes the cap")
    func capsTheDelay() {
        let capped = ModuleRestartPolicy(window: 600, maxCrashes: 10, baseDelay: 1, maxDelay: 30)
        let crashes = (0 ..< 9).map { now.addingTimeInterval(TimeInterval(-$0)) }
        #expect(capped.decision(crashes: crashes, now: now) == .restart(after: 30))
    }

    @Test("Too many crashes in the window stop the module")
    func stopsAfterTooManyCrashes() {
        let crashes = (0 ..< 5).map { now.addingTimeInterval(TimeInterval(-$0 * 10)) }
        #expect(policy.decision(crashes: crashes, now: now) == .stop)
    }

    @Test("Crashes older than the window don't count")
    func ignoresOldCrashes() {
        let old = (1 ... 6).map { now.addingTimeInterval(TimeInterval(-600 - $0)) }
        #expect(policy.decision(crashes: old + [now], now: now) == .restart(after: 1))
    }
}

@MainActor
@Suite("Module defaults")
struct ModuleDefaultsTests {
    private func profile(_ automation: ProfileAutomation?) throws -> Data {
        var object: [String: Any] = ["id": UUID().uuidString, "name": "Work"]
        if let automation {
            object["automation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(automation))
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("A global script left in Thaw's settings turns Automation on")
    func globalScriptCounts() {
        #expect(ModuleDefaults.automationHadScripts(globalHookData: [nil, Data("{}".utf8)], profileFiles: []))
    }

    @Test("A script saved in a profile turns Automation on")
    func profileScriptCounts() throws {
        let files = try [profile(nil), profile(ProfileAutomation(postHook: HookScript(path: "/tmp/post.sh")))]
        #expect(ModuleDefaults.automationHadScripts(globalHookData: [nil, nil], profileFiles: files))
    }

    @Test("No scripts anywhere leaves Automation off")
    func nothingLeavesItOff() throws {
        let files = try [profile(nil), profile(ProfileAutomation()), Data("not json".utf8)]
        #expect(!ModuleDefaults.automationHadScripts(globalHookData: [nil, nil], profileFiles: files))
    }
}

@MainActor
@Suite("Module start defaults", .serialized)
struct ModuleStartDefaultsTests {
    @Test("Thaw's own settings say which modules had work before")
    func readsPriorWorkFromThawSettings() throws {
        try ScratchDefaults.withStore(named: "ModuleStartDefaultsTests") { store in
            var profilesRead = 0
            let checks = ModuleDefaults.priorWorkInThawSettings { profilesRead += 1; return [] }
            #expect(checks["automation"]?() == false)
            #expect(checks["triggers"]?() == false)
            #expect(checks["widgets"]?() == false)

            store.set(Data("{}".utf8), forKey: "GlobalPostProfileHook")
            store.set(Data("[]".utf8), forKey: "AppRunningTriggersV1")
            store.set(true, forKey: "StatusIconPrototype.published")
            #expect(checks["automation"]?() == true)
            #expect(checks["triggers"]?() == true)
            #expect(checks["widgets"]?() == true)
            #expect(profilesRead == 2, "Profile files are read only by the Scripts check")
        }
    }

    @Test("Each module starts on only when Thaw had its own kind of work before")
    func startsOnForPriorWork() {
        var asked: [String] = []
        let priorWork: [String: () -> Bool] = [
            "automation": { asked.append("automation"); return true },
            "triggers": { asked.append("triggers"); return false },
        ]
        #expect(ModuleDefaults.startsEnabled("automation", priorWork: priorWork))
        #expect(!ModuleDefaults.startsEnabled("triggers", priorWork: priorWork))
        #expect(!ModuleDefaults.startsEnabled("spaces", priorWork: priorWork))
        #expect(asked == ["automation", "triggers"], "Only the asked-for module's check runs")
    }
}
