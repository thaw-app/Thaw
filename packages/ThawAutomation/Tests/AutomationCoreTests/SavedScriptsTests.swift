//
//  SavedScriptsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AutomationCore
import Foundation
import Testing
import ThawModuleKit
import ThawModuleTestSupport

/// What Thaw reads back from the Scripts module's defaults when it exports or copies a profile.
@MainActor
@Suite("Saved scripts")
struct SavedScriptsTests {
    private let work = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let suites = ScratchSuites(prefix: "SavedScriptsTests")
    private let inFile = ProfileAutomation(preHook: HookScript(path: "/tmp/old.sh"))

    /// A module store that has taken over the work profile, the way importFromThaw marks it.
    private func takenOver(_ automation: ProfileAutomation?) throws -> UserDefaults {
        let defaults = try #require(suites.make())
        let store = HookStore(defaults: defaults)
        store.update { $0.profileHooks[work] = automation }
        defaults.set([work.uuidString], forKey: SavedScripts.knownProfilesKey)
        return defaults
    }

    @Test("An edited script is the one Thaw reads, not the file's")
    func editedScript() throws {
        let edited = ProfileAutomation(postHook: HookScript(path: "/tmp/new.sh", timeoutSeconds: 30))
        let defaults = try takenOver(edited)
        #expect(SavedScripts.automation(forProfileID: work, inFile: inFile, moduleDefaults: defaults) == edited)
    }

    @Test("A script removed in the module stays removed")
    func removedScript() throws {
        let defaults = try takenOver(nil)
        #expect(SavedScripts.automation(forProfileID: work, inFile: inFile, moduleDefaults: defaults) == nil)
    }

    @Test("A profile the module hasn't taken over keeps the file's scripts")
    func notTakenOver() throws {
        let defaults = try #require(suites.make())
        #expect(SavedScripts.automation(forProfileID: work, inFile: inFile, moduleDefaults: defaults) == inFile)
        #expect(SavedScripts.automation(forProfileID: work, inFile: inFile, moduleDefaults: nil) == inFile)
    }

    @Test("The domain is the Scripts module's bundle ID")
    func domain() {
        #expect(SavedScripts.domain(hostBundleIdentifier: "com.example.Thaw") == "com.example.Thaw.module.automation")
    }
}
