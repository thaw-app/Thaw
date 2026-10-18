//
//  HookStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AutomationCore
import Foundation
import Testing
import ThawModuleKit
import ThawModuleTestSupport

@MainActor
@Suite("Hook store")
struct HookStoreTests {
    private let work = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let home = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private let suites = ScratchSuites(prefix: "HookStoreTests")

    private func freshDefaults() -> UserDefaults {
        suites.make()!
    }

    /// A Thaw profiles folder with a manifest and one file per profile.
    private func profilesFolder(_ profiles: [(UUID, String, ProfileAutomation?)]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = profiles.map { ["id": $0.0.uuidString, "name": $0.1, "createdAt": "2026-01-01T00:00:00Z"] }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("profiles.json"))
        for (id, name, automation) in profiles {
            var object: [String: Any] = ["id": id.uuidString, "name": name, "menuBarLayout": [String: Any]()]
            if let automation {
                object["automation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(automation))
            }
            try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("\(id.uuidString).json"))
        }
        return folder
    }

    @Test("The catalog lists Thaw's profiles by name and reads each one's hooks")
    func catalogReadsThawProfiles() throws {
        let hooks = ProfileAutomation(preHook: HookScript(path: "/tmp/pre.sh"))
        let catalog = try ProfileCatalog(directory: profilesFolder([(work, "Work", hooks), (home, "Home", nil)]))

        #expect(catalog.profiles() == [ProfileSummary(id: work, name: "Work"), ProfileSummary(id: home, name: "Home")])
        #expect(catalog.automation(forProfileID: work) == hooks)
        #expect(catalog.automation(forProfileID: home) == nil)
    }

    @Test("A missing profiles folder is an empty catalog")
    func missingFolderIsEmpty() {
        let catalog = ProfileCatalog(directory: URL(filePath: "/nonexistent/thaw-profiles"))
        #expect(catalog.profiles().isEmpty)
    }

    @Test("Saved hooks come back in a new store")
    func persists() {
        let defaults = freshDefaults()
        let store = HookStore(defaults: defaults)
        store.update { $0.globalPreHook = HookScript(path: "/tmp/pre.sh", timeoutSeconds: 30) }
        store.update { $0.profileHooks[work] = ProfileAutomation(postHook: HookScript(path: "/tmp/post.sh")) }

        let reloaded = HookStore(defaults: defaults)
        #expect(reloaded.configuration == store.configuration)
        #expect(reloaded.configuration.globalPreHook?.timeoutSeconds == 30)
    }

    @Test("The first run takes Thaw's global hooks and every profile's hooks")
    func importsFromThaw() throws {
        let host = freshDefaults()
        try host.set(JSONEncoder().encode(HookScript(path: "/tmp/global-pre.sh")), forKey: HookStore.thawGlobalPreKey)
        try host.set(JSONEncoder().encode(HookScript(path: "/tmp/global-post.sh", isEnabled: false)), forKey: HookStore.thawGlobalPostKey)
        let workHooks = ProfileAutomation(preHook: HookScript(path: "/tmp/work-pre.sh"))
        let catalog = try ProfileCatalog(directory: profilesFolder([(work, "Work", workHooks), (home, "Home", nil)]))
        let store = HookStore(defaults: freshDefaults())

        store.importFromThaw(hostDefaults: host, catalog: catalog)

        #expect(store.configuration.globalPreHook == HookScript(path: "/tmp/global-pre.sh"))
        #expect(store.configuration.globalPostHook == HookScript(path: "/tmp/global-post.sh", isEnabled: false))
        #expect(store.configuration.profileHooks == [work: workHooks])
    }

    @Test("Thaw's global hooks are taken once and never overwrite later edits")
    func importsGlobalsOnce() throws {
        let host = freshDefaults()
        try host.set(JSONEncoder().encode(HookScript(path: "/tmp/global-pre.sh")), forKey: HookStore.thawGlobalPreKey)
        let catalog = ProfileCatalog(directory: URL(filePath: "/nonexistent"))
        let store = HookStore(defaults: freshDefaults())
        store.importFromThaw(hostDefaults: host, catalog: catalog)
        store.update { $0.globalPreHook = nil }

        store.importFromThaw(hostDefaults: host, catalog: catalog)

        #expect(store.configuration.globalPreHook == nil)
    }

    @Test("A profile's hooks are taken when the module first sees it, and not again")
    func importsEachProfileOnce() throws {
        let folder = try profilesFolder([(work, "Work", nil)])
        let catalog = ProfileCatalog(directory: folder)
        let store = HookStore(defaults: freshDefaults())
        store.importFromThaw(hostDefaults: nil, catalog: catalog)

        // A profile imported from a file later arrives with its hooks switched off.
        let imported = ProfileAutomation(preHook: HookScript(path: "/tmp/shared.sh", isEnabled: false))
        let later = try profilesFolder([(work, "Work", ProfileAutomation(preHook: HookScript(path: "/tmp/ignored.sh"))), (home, "Home", imported)])
        store.importFromThaw(hostDefaults: nil, catalog: ProfileCatalog(directory: later))

        #expect(store.configuration.profileHooks[home] == imported)
        #expect(store.configuration.profileHooks[work] == nil)
    }
}
