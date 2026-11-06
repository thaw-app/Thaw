//
//  SpaceMenuBarChoicesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Spaces page storage", .serialized, .scratchDefaults)
struct SpaceMenuBarStorageTests {
    @Test("Choices round-trip through Defaults, and unreadable data loads as nothing")
    func defaultsRoundTrip() {
        var choices = SpaceMenuBarChoices(isHiddenEverywhere: true)
        choices.update(key: "A") { $0.revealStripHeight = 9 }
        SpaceMenuBarKeeper.saveToDefaults(choices)
        #expect(SpaceMenuBarKeeper.loadFromDefaults() == choices)
        Defaults.set(Data("not json".utf8), forKey: .spaceMenuBarChoices)
        #expect(SpaceMenuBarKeeper.loadFromDefaults() == nil)
        Defaults.removeObject(forKey: .spaceMenuBarChoices)
        #expect(SpaceMenuBarKeeper.loadFromDefaults() == nil)
    }

    @Test("Watching for agent restarts reports nothing for the agent already running")
    func liveRestartsStartQuiet() async {
        let restarts = SpaceMenuBarKeeper.liveAgentRestarts()
        let watcher = Task {
            for await _ in restarts {
                return true
            }
            return false
        }
        try? await Task.sleep(for: .milliseconds(50))
        watcher.cancel()
        #expect(await watcher.value == false)
    }
}

private func space(_ id: CGSSpaceID, _ key: String) -> Bridging.ManagedSpace {
    Bridging.ManagedSpace(spaceID: id, persistentKey: key, displayIdentifier: "D", ordinal: 1)
}

@Suite("Spaces page choices")
struct SpaceMenuBarChoicesTests {
    @Test("A choice back at the defaults is dropped")
    func dropsDefaults() {
        var choices = SpaceMenuBarChoices()
        choices.update(key: "A") { $0.isHidden = true }
        #expect(choices.choice(forKey: "A").isHidden)
        choices.update(key: "A") { $0.isHidden = false }
        #expect(choices.spaces.isEmpty)
    }

    @Test("Stored choices survive encoding with their keys")
    func roundTrips() throws {
        var choices = SpaceMenuBarChoices(isHiddenEverywhere: true)
        choices.update(key: "display:X#default") { $0.revealStripHeight = 12 }
        let decoded = try JSONDecoder().decode(SpaceMenuBarChoices.self, from: JSONEncoder().encode(choices))
        #expect(decoded == choices)
    }

    @Test("Everything sends the global choices and each listed Space under today's identifier")
    func everything() {
        var choices = SpaceMenuBarChoices(isHiddenEverywhere: true, usesFullScreenAppearanceEverywhere: true)
        choices.update(key: "A") { $0.isHidden = true
            $0.isAutoShowDisabled = true
        }
        choices.update(key: "B") { $0.revealStripHeight = 6 }
        choices.update(key: "GONE") { $0.isHidden = true }
        let requests = SpaceMenuBarReapply.requests(for: choices, spaces: [space(41, "A"), space(42, "B"), space(43, "C")], scope: .everything)
        #expect(requests == [
            .hiddenEverywhere,
            .fullScreenAppearanceEverywhere,
            .hidden(spaceID: 41),
            .autoShowDisabled(spaceID: 41),
            .revealStripHeight(6, spaceID: 42),
        ])
        #expect(choices.spaces["GONE"] != nil, "a Space that is gone stays stored")
    }

    @Test("A new Space gets only its own choices")
    func newSpaces() {
        var choices = SpaceMenuBarChoices(isHiddenEverywhere: true)
        choices.update(key: "A") { $0.isHidden = true }
        choices.update(key: "B") { $0.isHidden = true }
        let old = [space(1, "A")]
        let new = [space(1, "A"), space(2, "B")]
        let keys = SpaceMenuBarReapply.newKeys(from: old, to: new)
        #expect(keys == ["B"])
        #expect(SpaceMenuBarReapply.requests(for: choices, spaces: new, scope: .spaces(keys)) == [.hidden(spaceID: 2)])
    }

    @Test("Keys translate from identifiers, never for the unknown Space")
    func keyTranslation() {
        let spaces = [space(7, "A"), space(0, "Z")]
        #expect(SpaceMenuBarReapply.key(forSpaceID: 7, in: spaces) == "A")
        #expect(SpaceMenuBarReapply.key(forSpaceID: 0, in: spaces) == nil)
        #expect(SpaceMenuBarReapply.key(forSpaceID: 8, in: spaces) == nil)
    }

    @Test("A new agent process is a restart; the first sighting and the gap are not")
    func restarts() {
        var detector = MenuBarAgentRestartDetector()
        let answers = [[100], [100], [], [200], [200]].map { detector.observe(Set($0)) }
        #expect(answers == [false, false, false, true, false])
    }
}

/// Records every request and answers with accepts.
@MainActor
private final class RecordingPresentation: MenuBarPresentationControlling {
    var accepts = true
    var calls: [String] = []
    var isSupported: Bool {
        true
    }

    private func record(_ call: String) -> Bool {
        calls.append(call)
        return accepts
    }

    func revealSystemMenuBar() async -> Bool {
        record("reveal")
    }

    func setSystemMenuBarHidden(_ hidden: Bool) async -> Bool {
        record("hidden \(hidden)")
    }

    func setSystemMenuBarAutoShowEnabled(_ enabled: Bool) async -> Bool {
        record("autoShow \(enabled)")
    }

    func setSystemMenuBarHidden(_ hidden: Bool, spaceID: UInt64) async -> Bool {
        record("hidden \(hidden) \(spaceID)")
    }

    func setSystemMenuBarAutoShowDisabled(_ disabled: Bool, spaceID: UInt64) async -> Bool {
        record("autoShowDisabled \(disabled) \(spaceID)")
    }

    func setSystemMenuBarAutohideHeight(_ height: Double, spaceID: UInt64) async -> Bool {
        record("height \(height) \(spaceID)")
    }

    func clearSystemMenuBarOverrides(forSpace spaceID: UInt64) async -> Bool {
        record("clear \(spaceID)")
    }

    func setFullScreenAppearanceOnUserSpace(_ enabled: Bool) async -> Bool {
        record("fullScreen \(enabled)")
    }
}

@MainActor
@Suite("Spaces page keeper")
struct SpaceMenuBarKeeperTests {
    @Test("Recorded choices are saved by key and reset clears them")
    func recordsAndForgets() {
        var saved: [SpaceMenuBarChoices] = []
        let keeper = SpaceMenuBarKeeper(load: { saved.last }, save: { saved.append($0) }, presentation: { RecordingPresentation() })
        let spaces = [space(5, "A")]
        keeper.record(spaceID: 5, in: spaces) { $0.isAutoShowDisabled = true }
        keeper.record(spaceID: 6, in: spaces) { $0.isHidden = true }
        keeper.recordHiddenEverywhere(true)
        keeper.recordFullScreenAppearanceEverywhere(true)
        #expect(keeper.choice(forSpaceID: 5, in: spaces).isAutoShowDisabled)
        #expect(keeper.choice(forSpaceID: 6, in: spaces) == SpaceMenuBarChoice())
        keeper.forget(spaceID: 5, in: spaces)
        #expect(keeper.choices.spaces.isEmpty)
        keeper.removeAll()
        #expect(keeper.choices == SpaceMenuBarChoices())
        #expect(saved.count == 5)
    }

    @Test("A choice saved by another process wins over the one in memory")
    func readsTheStore() async {
        let presentation = RecordingPresentation()
        var stored: SpaceMenuBarChoices?
        let keeper = SpaceMenuBarKeeper(load: { stored }, save: { stored = $0 }, presentation: { presentation })
        stored = SpaceMenuBarChoices(isHiddenEverywhere: true)
        await keeper.reapply(.everything, spaces: [])
        #expect(presentation.calls == ["hidden true"])
        #expect(keeper.choices.isHiddenEverywhere)
    }

    @Test("Resetting undoes each stored choice in the agent and forgets it, keeping Spaces that are gone out of the requests")
    func resetAll() async {
        let presentation = RecordingPresentation()
        var stored = SpaceMenuBarChoices(isHiddenEverywhere: true, usesFullScreenAppearanceEverywhere: true)
        stored.update(key: "A") { $0.isHidden = true }
        stored.update(key: "GONE") { $0.isHidden = true }
        var current: SpaceMenuBarChoices? = stored
        let keeper = SpaceMenuBarKeeper(load: { current }, save: { current = $0 }, presentation: { presentation })
        await keeper.resetAll(spaces: [space(3, "A"), space(4, "B")])
        #expect(presentation.calls == ["hidden false", "fullScreen false", "clear 3"])
        #expect(current == SpaceMenuBarChoices())
    }

    @Test("Starting re-applies everything, then new Spaces and agent restarts")
    func reappliesOnStart() async {
        let presentation = RecordingPresentation()
        var stored = SpaceMenuBarChoices(isHiddenEverywhere: true)
        stored.update(key: "A") { $0.isHidden = true }
        stored.update(key: "B") { $0.isAutoShowDisabled = true }
        let keeper = SpaceMenuBarKeeper(load: { stored }, save: { _ in }, presentation: { presentation })
        var listed = [space(1, "A")]
        let directory = SpaceDirectory(read: { listed })
        let (restarts, restart) = AsyncStream<Void>.makeStream()
        keeper.start(directory: directory, agentRestarts: restarts)

        await waitUntil { presentation.calls.count == 2 }
        #expect(presentation.calls == ["hidden true", "hidden true 1"])

        listed = [space(1, "A"), space(2, "B")]
        directory.refresh()
        await waitUntil { presentation.calls.count == 3 }
        #expect(presentation.calls.last == "autoShowDisabled true 2")

        restart.yield()
        await waitUntil { presentation.calls.count == 6 }
        #expect(Array(presentation.calls.suffix(3)) == ["hidden true", "hidden true 1", "autoShowDisabled true 2"])
        keeper.stop()
    }

    @Test("A declined request is reported as not accepted")
    func declined() async {
        let presentation = RecordingPresentation()
        presentation.accepts = false
        let keeper = SpaceMenuBarKeeper(load: { SpaceMenuBarChoices(usesFullScreenAppearanceEverywhere: true) }, save: { _ in }, presentation: { presentation })
        let accepted = await keeper.reapply(.everything, spaces: [])
        #expect(accepted.isEmpty)
        #expect(presentation.calls == ["fullScreen true"])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
