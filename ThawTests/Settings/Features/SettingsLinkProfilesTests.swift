//
//  SettingsLinkProfilesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation
import os
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The app and its settings process joined in one process: a command runs in the app's share of the link at once,
/// and a request is answered as the host answers it, with the handler's answer or the words of what it threw.
@MainActor
@Observable
private final class Wire {
    @ObservationIgnored private var app = [SettingsAppFeature]()
    @ObservationIgnored private var child = [SettingsChildFeature]()
    /// The names of the requests and commands the settings process sent.
    private(set) var asked = [String]()
    @ObservationIgnored private(set) lazy var remote = SettingsRemote { [weak self] in self?.deliver($0) }

    /// Joins the Profiles page's share with the Shortcuts page's, which carries each profile's shortcut.
    init(app appState: AppState, child childState: AppState) {
        let profiles = ProfilesAppLink(profileManager: appState.profileManager) {
            ProfilePagePerformer(profileManager: appState.profileManager, appState: appState)
        }
        app = [profiles.feature, .hotkeys(appState)]
        let hotkeys = SettingsHotkeysMirror(models: .live(childState)) { [weak self] in self?.remote }
        child = [ProfilesLink.child(profiles: childState.profileManager), .hotkeys(mirror: hotkeys)]
    }

    private func deliver(_ message: SettingsLinkMessage) {
        switch message {
        case let .command(name, payload):
            asked.append(name)
            app.forEach { $0.commands[name]?(payload) }
        case let .request(id, name, payload):
            asked.append(name)
            guard let handler = app.lazy.compactMap({ $0.requests[name] }).first else { return }
            Task {
                do {
                    try await remote.answered(id: id, payload: handler(payload), failure: nil)
                } catch {
                    remote.answered(id: id, payload: nil, failure: error.localizedDescription)
                }
            }
        default:
            break
        }
    }

    /// What the app would send under a topic now.
    func status(_ topic: String) -> Data? {
        app.lazy.compactMap { $0.statuses[topic]?() }.first
    }

    func show(_ topic: String, _ payload: Data) {
        child.forEach { $0.statuses[topic]?(payload) }
    }

    /// Sends the app's state under a topic as the host does when what it reads has changed.
    func send(_ topic: String = ProfilesLink.list) throws {
        try show(topic, #require(status(topic)))
    }

    func endProcess() {
        app.forEach { $0.processEnded() }
    }
}

/// What a page would show in its error alert.
@MainActor
@Observable
private final class Errors {
    var message: String?
    var binding: Binding<String?> {
        Binding { self.message } set: { self.message = $0 }
    }
}

/// The Profiles page across the app and its settings process. Each end has its own AppState, never
/// started, and its own profile folder: the settings process's must stay empty.
@Suite("Settings process link, Profiles page", .serialized, .scratchDefaults)
@MainActor
struct SettingsLinkProfilesTests {
    private typealias Link = ProfilesLink

    /// Not one another suite registers, so neither takes the other's.
    private static let combination = KeyCombination(key: KeyCode(rawValue: 0x6B), modifiers: [.command, .option, .control, .shift])

    @MainActor
    private struct World {
        let appState: AppState
        /// The app's profiles, the only ones on disk.
        let profiles: ProfileManager
        let childState: AppState
        let childProfiles: ProfileManager
        let directory: URL
        let wire: Wire
        let errors = Errors()
        let undo = UndoManager()

        /// The page's runner in the settings process.
        var runner: ProfilePageRunner {
            ProfilePageRunner(
                performer: ProfilePagePerformer(profileManager: childProfiles, appState: childState),
                remote: wire.remote,
                undoManager: undo,
                errorMessage: errors.binding
            )
        }

        /// Runs one of the page's actions from the settings process and waits for what it left.
        func run(_ action: ProfilePageAction) async -> ProfilePageOutcome? {
            // One undo step for each action, as each click is in a window: the test never returns to the run loop between two.
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            defer { undo.endUndoGrouping() }
            return await withCheckedContinuation { continuation in
                runner.run(action) { continuation.resume(returning: $0) }
            }
        }

        var namesInApp: [String] {
            profiles.profiles.map(\.name)
        }

        func waitForNames(_ names: [String]) async {
            await waitUntil {
                namesInApp == names
            } tracking: {
                _ = profiles.profiles
            }
        }
    }

    private func withWorld(profiles names: [String] = [], _ body: (World) async throws -> Void) async throws {
        let directory = try ProfileTestDirectory.make(seeding: names)
        let childDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: childDirectory)
        }
        let appState = ProfileManager.$directoryOverride.withValue(directory) { AppState() }
        // Spacing is only ever written, so nothing a test does can restart an app.
        appState.spacingManager.spacingApplyMode = .writeOnly
        appState.settings.displaySettings.spacingApplyMode = .writeOnly
        let childState = ProfileManager.$directoryOverride.withValue(childDirectory) { AppState() }
        let world = World(
            appState: appState,
            profiles: appState.profileManager,
            childState: childState,
            childProfiles: childState.profileManager,
            directory: directory,
            wire: Wire(app: appState, child: childState)
        )
        try await body(world)
        #expect(childState.profileManager.appState == nil, "the settings process's profiles never get the app state, which would register hotkeys")
        let written = try FileManager.default.contentsOfDirectory(atPath: childDirectory.path)
        #expect(written.isEmpty, "the settings process wrote no profile file")
    }

    private func survives<Value: Codable & Equatable>(_ value: Value) -> Bool {
        SettingsLinkPayload.encode(value).flatMap { SettingsLinkPayload.decode(Value.self, from: $0) } == value
    }

    /// Whether anything that reads the list would be told to read it again while body runs.
    private func listChanges(in profiles: ProfileManager, during body: () throws -> Void) rethrows -> Bool {
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = profiles.profiles
        } onChange: {
            changed.withLock { $0 = true }
        }
        try body()
        return changed.withLock { $0 }
    }

    // MARK: Payloads

    @Test("Each payload survives the link")
    func payloads() throws {
        let id = UUID()
        var metadata = ProfileMetadata(id: id, name: "Work", createdAt: .now, modifiedAt: .now)
        metadata.associatedDisplayUUID = "DISPLAY"
        metadata.keepsLayoutChangesSetting = false
        #expect(survives([metadata]))
        #expect(survives(ProfileListEdit.display(uuid: nil, name: nil, profile: id)))
        #expect(survives(ProfileListEdit.space(key: "SPACE", name: "Desktop 2", profile: id)))
        #expect(survives(ProfileListEdit.layoutBehavior(keepsChanges: nil, reappliesAtLaunch: true, profile: id)))

        let actions: [ProfilePageAction] = [
            .create(name: "Desk"), .preview(id: id), .apply(id: id, spacingRelaunchApproved: true),
            .update(id: id, scope: .layoutOnly), .updateSettingsInEveryProfile, .rename(id: id, name: "Office"),
            .duplicate(id: id, name: "Work Copy"), .delete(id: id), .export(id: nil), .export(id: id),
            .importFile(Data("{}".utf8)), .edit(.display(uuid: "DISPLAY", name: "Studio", profile: id)),
        ]
        for action in actions {
            let sent = try #require(SettingsLinkPayload.encode(action))
            let received = try #require(SettingsLinkPayload.decode(ProfilePageAction.self, from: sent))
            #expect(SettingsLinkPayload.encode(received) == sent, "\(action)")
        }

        let profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"name": "Work"}"#.utf8))
        var diff = ProfileLayoutDiff()
        diff.moves = [.init(item: .init(id: "a:b", bundleID: "a", title: "b"), from: "visible", to: "hidden")]
        diff.settingChanges = [.init(key: "area.names", label: "Item names")]
        diff.relaunchingSpacingOffset = 4
        let outcome = ProfilePageOutcome(undoName: "Save Profile", preview: ProfilePreview(profile: profile, diff: diff), exported: Data([1, 2]), notice: "Note")
        let sent = try #require(SettingsLinkPayload.encode(Link.Performed(outcome: outcome, undo: id)))
        let answer = try #require(SettingsLinkPayload.decode(Link.Performed.self, from: sent))
        #expect(answer.undo == id)
        #expect(answer.outcome.undoName == "Save Profile")
        #expect(answer.outcome.preview?.profile.id == profile.id)
        #expect(answer.outcome.preview?.diff == diff)
        #expect(answer.outcome.exported == Data([1, 2]))
        #expect(answer.outcome.notice == "Note")
    }

    // MARK: The list

    @Test("The app sends the profile list as it is now")
    func appSendsList() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            @MainActor func list() throws -> [ProfileMetadata] {
                try #require(world.wire.status(Link.list).flatMap { SettingsLinkPayload.decode([ProfileMetadata].self, from: $0) })
            }
            #expect(try list() == world.profiles.profiles)
            try world.profiles.renameProfile(id: world.profiles.profiles[0].id, to: "Office")
            #expect(try list().map(\.name) == ["Office", "Home"])
        }
    }

    @Test("The settings process shows the app's list, and only tells its page of a list that differs")
    func childShowsList() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            #expect(world.childProfiles.profiles.isEmpty)
            let shown = try listChanges(in: world.childProfiles) { try world.wire.send() }
            #expect(shown)
            #expect(world.childProfiles.profiles == world.profiles.profiles)
            let shownAgain = try listChanges(in: world.childProfiles) { try world.wire.send() }
            #expect(!shownAgain, "the same list again changes nothing")

            world.wire.show(Link.list, Data("not a list".utf8))
            #expect(world.childProfiles.profiles == world.profiles.profiles, "a payload that isn't a list changes nothing")
        }
    }

    // MARK: Actions

    @Test("Save Current runs in the app, and the settings process's Undo and Redo take the profile away and bring it back")
    func createsAndUndoes() async throws {
        try await withWorld { world in
            let outcome = await world.run(.create(name: "Desk"))
            #expect(outcome?.undoName == "Create Profile")
            #expect(world.namesInApp == ["Desk"])
            let id = try #require(world.profiles.profiles.first?.id)
            #expect(world.profiles.activeProfileID == id)
            #expect(world.undo.undoActionName == "Create Profile")

            world.undo.undo()
            await world.waitForNames([])
            #expect(world.profiles.activeProfileID == nil)
            #expect(world.undo.redoActionName == "Create Profile")

            world.undo.redo()
            await world.waitForNames(["Desk"])
            #expect(world.profiles.profiles.first?.id == id, "redo brings back the same profile")
            #expect(world.wire.asked == [Link.perform, Link.undo, Link.undo])
            #expect(world.errors.message == nil)
        }
    }

    @Test("Rename, Duplicate and Delete run in the app, and Delete undoes")
    func renamesDuplicatesAndDeletes() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let work = world.profiles.profiles[0].id
            #expect(await world.run(.rename(id: work, name: "Office"))?.undoName == "Rename Profile")
            #expect(world.namesInApp == ["Office", "Home"])
            #expect(await world.run(.rename(id: work, name: "Office"))?.undoName == nil, "the same name leaves nothing to undo")

            #expect(await world.run(.duplicate(id: work, name: "Office Copy"))?.undoName == "Duplicate Profile")
            #expect(world.namesInApp == ["Office", "Home", "Office Copy"])

            world.profiles.activeProfileID = work
            #expect(await world.run(.delete(id: work))?.undoName == "Delete Profile")
            #expect(world.namesInApp == ["Home", "Office Copy"])
            #expect(world.profiles.activeProfileID == nil, "deleting the active profile leaves none active")

            world.undo.undo()
            await world.waitForNames(["Office", "Home", "Office Copy"])
            #expect(world.profiles.activeProfileID == work, "undo puts it back first in the list, and active")
        }
    }

    @Test("Update saves the app's setup into a profile or into all, and undoes")
    func updates() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let ids = world.profiles.profiles.map(\.id)
            let original = Defaults.DefaultValue.showOnHover
            @MainActor func saved() throws -> [Bool] {
                try ids.map { try world.profiles.loadProfile(id: $0).generalSettings.showOnHover }
            }
            world.appState.settings.visibility.showOnHover = !original

            #expect(await world.run(.update(id: ids[1], scope: .configurationOnly))?.undoName == "Save Configuration")
            let afterOne = try saved()
            #expect(afterOne == [original, !original])
            world.undo.undo()
            await waitUntil {
                (try? saved()) == [original, original]
            } tracking: {
                _ = world.profiles.profiles
            }

            #expect(await world.run(.update(id: ids[0], scope: .all))?.undoName == "Save Profile")
            #expect(await world.run(.update(id: ids[0], scope: .layoutOnly))?.undoName == "Save Layout")
            #expect(await world.run(.updateSettingsInEveryProfile)?.undoName == "Save Configuration on All Profiles")
            let afterAll = try saved()
            #expect(afterAll == [!original, !original])

            let missing = UUID()
            #expect(await world.run(.update(id: missing, scope: .all)) == nil)
            let here = Errors()
            let performer = ProfilePagePerformer(profileManager: world.profiles, appState: world.appState)
            ProfilePageRunner(performer: performer, remote: nil, undoManager: nil, errorMessage: here.binding).run(.update(id: missing, scope: .all))
            #expect(here.message != nil)
            #expect(world.errors.message == here.message, "the app's failure shows on the page in the words its own window shows")
        }
    }

    @Test("The preview comes from the app, and an apply answers once the layout has had its turn")
    func previewsAndApplies() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let offset = (DisplaySettingsManager.currentSystemSpacing() ?? 16) - 16
            try #require(world.appState.spacingManager.isOnDisk(offset: offset), "spacing and padding on disk differ, so an apply would rewrite them")
            world.appState.spacingManager.offset = offset
            let home = world.profiles.profiles[1].id
            let original = Defaults.DefaultValue.showOnHover
            world.appState.settings.visibility.showOnHover = !original

            let preview = try #require(await world.run(.preview(id: home))?.preview)
            #expect(preview.profile.id == home)
            #expect(preview.diff.settingChanges.contains { $0.key == "showOnHover" }, "the change is against the app's settings")
            #expect(preview.diff.relaunchingSpacingOffset == nil)

            let outcome = await world.run(.apply(id: home, spacingRelaunchApproved: false))
            #expect(world.profiles.activeProfileID == home)
            #expect(world.profiles.layoutTask == nil, "the answer waited for the layout")
            #expect(world.appState.settings.visibility.showOnHover == original, "the profile's setting is back")
            #expect(outcome?.notice?.contains("not managing the menu bar yet") == true, "an app that was never started has no layout engine")
            #expect(outcome?.undoName == nil)
        }
    }

    @Test("An export's contents come to the settings process, and it hands an import's contents to the app")
    func exportsAndImports() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let work = world.profiles.profiles[0].id
            let one = try #require(await world.run(.export(id: work))?.exported)
            let bundle = try #require(try JSONSerialization.jsonObject(with: one) as? [String: Any])
            let names = (bundle["entries"] as? [[String: Any]])?.compactMap { ($0["profile"] as? [String: Any])?["name"] as? String }
            #expect(names == ["Work"])

            let all = try #require(await world.run(.export(id: nil)))
            let text = try #require(all.exported.flatMap { String(data: $0, encoding: .utf8) })
            #expect(text.contains("Work") && text.contains("Home"))
            #expect(all.notice == nil)

            #expect(await world.run(.importFile(one)) != nil)
            #expect(world.namesInApp == ["Work", "Home", "Work"])

            #expect(await world.run(.importFile(Data("not profiles".utf8))) == nil)
            #expect(world.errors.message != nil)
            #expect(world.namesInApp.count == 3)
        }
    }

    @Test("An export says which profiles it had to leave out")
    func exportNamesUnreadableProfiles() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let home = world.profiles.profiles[1].id
            try FileManager.default.removeItem(at: world.directory.appendingPathComponent("\(home.uuidString).json"))
            let all = try #require(await world.run(.export(id: nil)))
            #expect(all.notice?.contains("Home") == true)
            #expect(all.exported != nil)
        }
    }

    // MARK: What switches to a profile

    @Test("A display, a Space and the layout switches are saved by the app")
    func editsList() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let work = world.profiles.profiles[0]
            try world.wire.send()
            let layout = ProfileLayoutBehaviorSection(
                profileManager: world.childProfiles,
                profile: work,
                errorMessage: world.errors.binding,
                remote: world.wire.remote
            )
            let switches = ProfileSwitchesSection(
                profileManager: world.childProfiles,
                displaySettings: world.childState.settings.displaySettings,
                profile: work,
                errorMessage: world.errors.binding,
                remote: world.wire.remote
            )

            layout.keepsChanges.wrappedValue = false
            layout.reappliesAtLaunch.wrappedValue = true
            switches.displayBinding.wrappedValue = "DISPLAY"
            switches.spaceBinding(groups: []).wrappedValue = "SPACE"
            await waitUntil {
                world.profiles.profiles[0].associatedSpaceKey == "SPACE"
            } tracking: {
                _ = world.profiles.profiles
            }

            let saved = world.profiles.profiles[0]
            #expect(!saved.keepsLayoutChanges)
            #expect(saved.reappliesAtLaunch)
            #expect(saved.associatedDisplayUUID == "DISPLAY")
            #expect(world.childProfiles.profiles[0] == work, "the settings process waits for the app's list")

            try world.wire.send()
            #expect(!layout.keepsChanges.wrappedValue)
            #expect(switches.displayBinding.wrappedValue == "DISPLAY")
            #expect(switches.spaceBinding(groups: []).wrappedValue == "SPACE")
        }
    }

    @Test("Without a remote the same edits are made at once on the page's own profiles")
    func editsHere() throws {
        try ProfileTestDirectory.withManager(seeding: ["Work"]) { manager, _ in
            let errors = Errors()
            let work = manager.profiles[0].id
            ProfilePageRunner.make(.display(uuid: "DISPLAY", name: "Studio", profile: work), on: manager, remote: nil, errorMessage: errors.binding)
            #expect(manager.profiles[0].associatedDisplayUUID == "DISPLAY")
            #expect(errors.message == nil)
        }
    }

    @Test("The recorder in the settings process records into the hotkey the Shortcuts page's share mirrors, also for a profile made meanwhile")
    func recordsShortcut() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let work = world.profiles.profiles[0]
            world.profiles.appState = world.appState
            world.profiles.rebuildProfileHotkeys()
            let hotkey = try #require(world.profiles.profileHotkeys[work.id])
            defer { hotkey.keyCombination = nil }
            try world.wire.send()
            #expect(world.childProfiles.profileHotkeys.isEmpty, "this process builds no hotkey of its own")
            try world.wire.send(HotkeysSettingsLink.bindings)
            let mirrored = try #require(world.childProfiles.profileHotkeys[work.id])
            #expect(mirrored.keyCombination == nil)

            let section = ProfileSwitchesSection(
                profileManager: world.childProfiles,
                displaySettings: world.childState.settings.displaySettings,
                profile: work,
                errorMessage: world.errors.binding,
                remote: world.wire.remote
            )
            let size = CGSize(width: 760, height: 600)
            let drawn = OffscreenRender(AnyView(ThawForm { section }.environment(world.childState).frame(width: size.width, height: size.height)), size: size)
            await drawn.settle { !drawn.elements(role: .button, label: "Record Shortcut").isEmpty }
            #expect(drawn.texts().contains("Keyboard shortcut"))

            mirrored.keyCombination = Self.combination
            #expect(hotkey.keyCombination == Self.combination)
            #expect(hotkey.isEnabled)
            try world.wire.send(HotkeysSettingsLink.bindings)
            #expect(mirrored.keyCombination == Self.combination && mirrored.isEnabled)

            mirrored.setRecording(true)
            #expect(!hotkey.isEnabled, "the old combination can't fire while a new one is recorded")
            world.wire.endProcess()
            #expect(hotkey.isEnabled, "a recording the settings process never ended doesn't leave the shortcut off")
            mirrored.setRecording(true)
            mirrored.setRecording(false)
            #expect(hotkey.isEnabled)

            mirrored.keyCombination = nil
            #expect(hotkey.keyCombination == nil)

            #expect(await world.run(.create(name: "Desk")) != nil)
            let desk = try #require(world.profiles.profiles.last)
            try world.wire.send(HotkeysSettingsLink.bindings)
            #expect(world.childProfiles.profileHotkeys[desk.id] != nil, "a profile made while the page is open gets a hotkey to record into")
            #expect(world.childProfiles.profileHotkeys[work.id] === mirrored, "and the recorder already shown keeps its own")
        }
    }

    // MARK: The process ending

    @Test("Once the settings process has ended, the app has forgotten its undo steps")
    func endForgetsUndoSteps() async throws {
        try await withWorld { world in
            let remote = world.wire.remote
            /// Whether the app still had the step.
            @MainActor func undo(_ step: UUID) async throws -> Bool {
                try await remote.request(Link.undo, step)
            }
            let kept = try #require(try await Link.run(.create(name: "Desk"), via: remote).undo)
            #expect(try await undo(kept))
            #expect(world.namesInApp.isEmpty)
            #expect(try await undo(kept))
            #expect(world.namesInApp == ["Desk"], "the same name asks for the undo and then the redo")

            let forgotten = try #require(try await Link.run(.create(name: "Travel"), via: remote).undo)
            world.wire.endProcess()
            #expect(try await !undo(forgotten))
            #expect(world.namesInApp == ["Desk", "Travel"], "an edit the app no longer remembers stays")

            await #expect(throws: SettingsRequestError.failed(SettingsRequestError.unreadable.localizedDescription)) {
                _ = try await remote.request(Link.perform, "not an action") as Link.Performed
            }
        }
    }

    @Test("An undo the app can't make shows on the page, and asking again changes nothing")
    func failedUndo() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let work = world.profiles.profiles[0].id
            #expect(await world.run(.rename(id: work, name: "Office")) != nil)
            try world.profiles.deleteProfile(id: work)

            world.undo.undo()
            await waitUntil {
                world.errors.message != nil
            } tracking: {
                _ = world.errors.message
            }
            #expect(world.undo.canRedo)

            world.errors.message = nil
            world.undo.redo()
            await waitUntil {
                world.wire.asked.count == 3
            } tracking: {
                _ = world.wire.asked
            }
            #expect(world.errors.message == nil)
        }
    }

    // MARK: The page

    @Test("The page in the settings process shows what the app says and has the app save a new profile")
    func pageInSettingsProcess() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            try world.wire.send()
            let size = CGSize(width: 760, height: 2400)
            let pane = ProfileSettingsPane(profileManager: world.childProfiles, remote: world.wire.remote)
            let page = OffscreenRender(
                AnyView(pane.environment(world.childState).environment(\.settingsPaneTitle, nil).frame(width: size.width, height: size.height)),
                size: size
            )
            await page.settle { page.texts().contains("What will change") }
            #expect(page.texts().contains("What will change"), "the app's preview of the selected profile has arrived")
            #expect(!page.texts().contains("This profile couldn't be read."))
            #expect(world.wire.asked == [Link.perform])

            let field = try #require(page.views(NSTextField.self).filter(\.isEditable).first)
            page.type("Desk", into: field)
            try page.press("Save Current")
            await world.waitForNames(["Work", "Desk"])
            #expect(world.childProfiles.profiles.map(\.name) == ["Work"], "the page waits for the app's list")
            await page.settle { field.stringValue.isEmpty }
            #expect(field.stringValue.isEmpty, "the name field empties once the app has saved the profile")

            try world.wire.send()
            let listsDesk = { page.elements().contains { OffscreenAccessibility.label(of: $0)?.hasPrefix("Desk,") == true } }
            await page.settle { listsDesk() }
            #expect(listsDesk(), "the new profile has a row once the app's list has come")
            let undo = try #require(page.host.undoManager)
            #expect(undo.undoActionName == "Create Profile")
            undo.undo()
            await world.waitForNames(["Work"])
        }
    }

    // MARK: In the app's own window

    @Test("Without a remote the runner acts on the page's own profiles before it returns, and undoes there")
    func runsHere() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let errors = Errors()
            let undo = UndoManager()
            let runner = ProfilePageRunner(
                performer: ProfilePagePerformer(profileManager: world.profiles, appState: world.appState),
                remote: nil,
                undoManager: undo,
                errorMessage: errors.binding
            )
            var outcomes = [ProfilePageOutcome?]()
            runner.run(.rename(id: world.profiles.profiles[0].id, name: "Office")) { outcomes.append($0) }
            #expect(world.namesInApp == ["Office"])
            #expect(outcomes.count == 1)
            #expect(undo.undoActionName == "Rename Profile")
            undo.undo()
            #expect(world.namesInApp == ["Work"])
            undo.redo()
            #expect(world.namesInApp == ["Office"])

            runner.run(.delete(id: UUID())) { outcomes.append($0) }
            #expect(outcomes.count == 2 && outcomes[1] == nil)
            #expect(errors.message != nil)
            #expect(world.wire.asked.isEmpty, "nothing is asked of another process")
        }
    }
}
