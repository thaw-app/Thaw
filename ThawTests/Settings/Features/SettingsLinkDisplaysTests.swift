//
//  SettingsLinkDisplaysTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation
import Testing
@testable import Thaw

/// Stands in for the app's session with the menu bar agent: records each request and answers with accepts.
@MainActor
private final class FakePresentation: MenuBarPresentationControlling {
    var isSupported = true
    var accepts = true
    var calls: [String] = []

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
        record("hidden \(hidden) in \(spaceID)")
    }

    func setSystemMenuBarAutoShowDisabled(_ disabled: Bool, spaceID: UInt64) async -> Bool {
        record("autoShowDisabled \(disabled) in \(spaceID)")
    }

    func setSystemMenuBarAutohideHeight(_ height: Double, spaceID: UInt64) async -> Bool {
        record("height \(height) in \(spaceID)")
    }

    func clearSystemMenuBarOverrides(forSpace spaceID: UInt64) async -> Bool {
        record("clear \(spaceID)")
    }

    func setFullScreenAppearanceOnUserSpace(_ enabled: Bool) async -> Bool {
        record("fullScreen \(enabled)")
    }
}

/// What the settings process sent the app, what the page was told failed, and what a stand-in for the spacing engine was asked.
@MainActor
private final class Recorder {
    var messages: [SettingsLinkMessage] = []
    var failures: [DisplayCommitFailure] = []
    var applies: [(forceRelaunch: Bool, relaunchApps: Bool)] = []
    var prompts = 0
    var asked = 0
    /// The remote whose requests are answered, which its own send closure cannot name.
    weak var remote: SettingsRemote?

    /// The commands sent to the app, each with its payload decoded as text.
    var commands: [String] {
        messages.map { message in
            guard case let .command(name, payload) = message else { return "\(message)" }
            return "\(name) \(SettingsLinkPayload.decode(String.self, from: payload) ?? "?")"
        }
    }

    /// The names of the requests made of the app.
    var requests: [String] {
        messages.compactMap { message in
            if case let .request(_, name, _) = message { name } else { nil }
        }
    }
}

@Suite("Displays page over the settings link", .serialized, .scratchDefaults)
@MainActor
struct SettingsLinkDisplaysTests {
    private typealias Link = DisplaysSettingsLink
    private static let studio = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    private let recorder = Recorder()

    /// An app state that is never started, profiles in a throwaway folder with the first of them
    /// active, and one saved display that is not connected. Spacing is only ever written.
    private struct World {
        let appState: AppState
        let settings: DisplaySettingsManager
        let profiles: ProfileManager
        let directory: URL
    }

    private func withWorld(profiles names: [String] = [], _ body: (World) async throws -> Void) async throws {
        let directory = try ProfileTestDirectory.make(seeding: names)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appState = ProfileManager.$directoryOverride.withValue(directory) { AppState() }
        let profiles = appState.profileManager
        profiles.activeProfileID = profiles.profiles.first?.id
        let settings = appState.settings.displaySettings
        settings.spacingApplyMode = .writeOnly
        settings.knownDisplays[Self.studio] = KnownDisplay(name: "Studio", hasNotch: false)
        settings.configurations[Self.studio] = DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(4)
        try await body(World(appState: appState, settings: settings, profiles: profiles, directory: directory))
    }

    private func appFeature(_ world: World, presentation: FakePresentation = FakePresentation()) -> SettingsAppFeature {
        Link.app(world.appState, presentation: presentation)
    }

    /// A remote whose requests the feature answers, as the app's host has it answer them.
    private func linkedRemote(to feature: SettingsAppFeature) -> SettingsRemote {
        let remote = SettingsRemote { [recorder] message in
            recorder.messages.append(message)
            guard case let .request(id, name, payload) = message else { return }
            Task {
                do {
                    let answer = try await feature.requests[name]?(payload)
                    recorder.remote?.answered(id: id, payload: answer, failure: nil)
                } catch {
                    recorder.remote?.answered(id: id, payload: nil, failure: error.localizedDescription)
                }
            }
        }
        recorder.remote = remote
        return remote
    }

    private func payload(_ value: some Encodable) throws -> Data {
        try #require(SettingsLinkPayload.encode(value))
    }

    private func survives<Value: Codable & Equatable>(_ value: Value) -> Bool {
        SettingsLinkPayload.encode(value).flatMap { SettingsLinkPayload.decode(Value.self, from: $0) } == value
    }

    private func savedOffset(_ world: World) -> Double {
        world.settings.configuration(forUUID: Self.studio).itemSpacingOffset
    }

    private func profile(_ name: String, in world: World) throws -> Profile {
        let meta = try #require(world.profiles.profiles.first { $0.name == name })
        return try world.profiles.loadProfile(id: meta.id)
    }

    private func removeActiveProfileFile(_ world: World) throws {
        let id = try #require(world.profiles.activeProfileID)
        try FileManager.default.removeItem(at: world.directory.appendingPathComponent("\(id.uuidString).json"))
    }

    /// A stand-in for the spacing engine, which asks before a relaunch and is always told no.
    private func installSpacingHost(_ world: World) {
        world.settings.spacingHost = DisplaySpacingApplyHost(
            spacingManager: MenuBarItemSpacingManager(),
            applyOffset: { [recorder] forceRelaunch, relaunchApps in
                recorder.applies.append((forceRelaunch, relaunchApps))
                return MenuBarItemSpacingManager.ApplyOutcome(didRelaunch: false, recoveredBundleIDs: [], failedAppNames: [])
            },
            noteSettling: { _ in },
            reapplyActiveProfile: {},
            confirmRelaunch: { [recorder] in
                recorder.prompts += 1
                return false
            }
        )
        world.settings.spacingApplyMode = .relaunchApps
        world.settings.confirmSpacingRelaunch = true
    }

    @Test("Everything the page sends over the link survives being encoded and decoded")
    func payloads() {
        let template = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(5)
        let spacing = DisplayProfileCommit(change: .spacing(displayID: Self.studio, offset: 6), scope: .allProfiles, activeProfileID: UUID())
        let snapshot = DisplaySettingsManager.Snapshot(configurations: [Self.studio: template], globalConfiguration: template)
        let failure = DisplayCommitFailure(message: "The profile is gone.", displayID: Self.studio)
        #expect(survives(spacing))
        #expect(survives(DisplayProfileCommit(change: .template(template), scope: nil, activeProfileID: nil)))
        #expect(survives(Link.CommitRequest(commit: spacing, settings: snapshot)))
        #expect(survives(Link.CommitResult(settings: snapshot, failure: failure)))
        #expect(survives(Link.SpacingApply(isReapplying: true, failure: "Could not relaunch: Clock")))
        #expect(survives(Link.Spaces(active: 7, listed: [7, 8], takesPresentationRequests: true)))
        #expect(survives(Link.ActiveProfile(id: nil)) && survives(Link.ActiveProfile(id: UUID())))
        let requests: [RemoteMenuBarPresentation.Request] = [
            .reveal, .hidden(true), .autoShowEnabled(false), .hiddenInSpace(true, spaceID: 9), .autoShowDisabledInSpace(true, spaceID: 9),
            .autohideHeight(12, spaceID: 9), .clearOverrides(spaceID: 9), .fullScreenAppearance(true),
        ]
        #expect(requests.allSatisfy(survives))
    }

    @Test("The app sends the spacing apply's progress, the Spaces and the active profile as they are now")
    func appSendsLiveState() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let presentation = FakePresentation()
            let feature = appFeature(world, presentation: presentation)
            @MainActor func status<Value: Decodable>(_ topic: String, _: Value.Type) -> Value? {
                feature.statuses[topic]?().flatMap { SettingsLinkPayload.decode(Value.self, from: $0) }
            }
            #expect(status(Link.spacingApply, Link.SpacingApply.self) == Link.SpacingApply(isReapplying: false, failure: nil))
            world.settings.isReapplyingSpacing = true
            world.settings.lastSpacingApplyFailure = "Could not relaunch: Clock"
            #expect(status(Link.spacingApply, Link.SpacingApply.self) == Link.SpacingApply(isReapplying: true, failure: "Could not relaunch: Clock"))

            let spaces = Link.Spaces(
                active: world.appState.activeSpace.spaceID,
                listed: world.appState.spaceDirectory.spaces.map(\.spaceID),
                takesPresentationRequests: true
            )
            #expect(status(Link.spaces, Link.Spaces.self) == spaces)
            presentation.isSupported = false
            #expect(status(Link.spaces, Link.Spaces.self)?.takesPresentationRequests == false)

            #expect(status(Link.activeProfile, Link.ActiveProfile.self) == Link.ActiveProfile(id: world.profiles.activeProfileID))
            world.profiles.activeProfileID = nil
            #expect(status(Link.activeProfile, Link.ActiveProfile.self) == Link.ActiveProfile(id: nil))
        }
    }

    @Test("The app takes the settings process's display settings, makes its spacing change and saves it to every profile")
    func appRunsSpacingCommit() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let remote = linkedRemote(to: appFeature(world))
            // An edit the settings process made a moment ago, which the app has not read yet.
            var edited = world.settings.snapshot
            edited.configurations[Self.studio] = edited.configurations[Self.studio]?.withGridColumns(7)
            let commit = DisplayProfileCommit(
                change: .spacing(displayID: Self.studio, offset: 6), scope: .allProfiles, activeProfileID: world.profiles.activeProfileID
            )
            let result: Link.CommitResult = try await remote.request(Link.commit, Link.CommitRequest(commit: commit, settings: edited))

            #expect(savedOffset(world) == 6)
            #expect(world.settings.configuration(forUUID: Self.studio).gridColumns == 7, "the earlier edit is kept")
            #expect(try profile("Work", in: world).displayConfigurations[Self.studio]?.itemSpacingOffset == 6)
            #expect(try profile("Home", in: world).displayConfigurations[Self.studio]?.itemSpacingOffset == 6)
            #expect(result == Link.CommitResult(settings: world.settings.snapshot, failure: nil))
        }
    }

    @Test("A spacing the app cannot save to the active profile goes back, and the app says so")
    func appRollsSpacingCommitBack() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let remote = linkedRemote(to: appFeature(world))
            try removeActiveProfileFile(world)
            let commit = DisplayProfileCommit(
                change: .spacing(displayID: Self.studio, offset: 6), scope: .activeProfile, activeProfileID: world.profiles.activeProfileID
            )
            let result: Link.CommitResult = try await remote.request(Link.commit, Link.CommitRequest(commit: commit, settings: world.settings.snapshot))

            #expect(savedOffset(world) == 4, "the unsaved spacing is rolled back")
            #expect(result.settings == world.settings.snapshot)
            #expect(result.failure?.displayID == Self.studio)
            #expect(result.failure?.message.isEmpty == false)
        }
    }

    @Test("The app copies the settings process's template onto every display, and puts the displays back when the profile can't keep it")
    func appRunsTemplateCommit() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let remote = linkedRemote(to: appFeature(world))
            let template = DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(2).withGridColumns(5)
            var request = Link.CommitRequest(
                commit: DisplayProfileCommit(change: .template(template), scope: .allProfiles, activeProfileID: world.profiles.activeProfileID),
                settings: world.settings.snapshot
            )
            let kept: Link.CommitResult = try await remote.request(Link.commit, request)
            #expect(world.settings.globalConfiguration == template)
            #expect(world.settings.displays.allSatisfy { world.settings.configurations[$0.id] == template })
            #expect(try profile("Work", in: world).globalDisplayConfiguration == template)
            #expect(kept == Link.CommitResult(settings: world.settings.snapshot, failure: nil))

            try removeActiveProfileFile(world)
            let before = world.settings.configurations
            let next = template.withItemSpacingOffset(-2)
            request.commit = DisplayProfileCommit(change: .template(next), scope: .activeProfile, activeProfileID: world.profiles.activeProfileID)
            request.settings = world.settings.snapshot
            let result: Link.CommitResult = try await remote.request(Link.commit, request)
            #expect(world.settings.configurations == before, "the copy is rolled back")
            #expect(result.failure != nil && result.failure?.displayID == nil)
            #expect(result.settings == world.settings.snapshot)
        }
    }

    @Test("Asked to reapply spacing, the app relaunches without asking again, and still asks for its own")
    func appReappliesSpacing() async throws {
        try await withWorld { world in
            let uuid = try #require(world.settings.activeMenuBarDisplayUUID, "the test host has a display that owns the menu bar")
            let feature = appFeature(world)
            installSpacingHost(world)
            try feature.commands[Link.reapplySpacing]?(payload(uuid))
            #expect(await settingsLinkWait { recorder.applies.count == 1 && !world.settings.isReapplyingSpacing })
            #expect(recorder.applies.first?.forceRelaunch == true)
            #expect(recorder.prompts == 0, "the question was answered in the settings process")

            world.settings.reapplySpacing(forDisplayUUID: uuid)
            #expect(recorder.prompts == 1, "the app's own reapply asks as before")
            #expect(recorder.applies.count == 1)
        }
    }

    @Test("After the settings process saved, the app reads the display settings again and assigns only what changed")
    func appReadsStoredSettings() async throws {
        try await withWorld { world in
            let feature = appFeature(world)
            let settings = world.settings
            let template = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(5)
            let encoder = JSONEncoder()
            try Defaults.set(encoder.encode([Self.studio: template.withItemSpacingOffset(8)]), forKey: .displayThawBarConfigurations)
            try Defaults.set(encoder.encode(template), forKey: .globalDisplayConfiguration)
            try Defaults.set(encoder.encode(["B": KnownDisplay(name: "Bench", hasNotch: true), "C": KnownDisplay(name: " ", hasNotch: false)]), forKey: .knownDisplays)
            Defaults.set(false, forKey: .confirmSpacingRelaunch)
            Defaults.set(SpacingProfileSaveScope.allProfiles.rawValue, forKey: .unconfirmedSpacingProfileScope)
            Defaults.set(SpacingApplyMode.relaunchApps.rawValue, forKey: .spacingApplyMode)
            Defaults.set(true, forKey: .showEveryItemOnWideDisplays)
            Defaults.set(2560.0, forKey: .wideDisplayMinimumWidth)
            feature.reload()

            #expect(savedOffset(world) == 8)
            #expect(settings.globalConfiguration == template)
            #expect(settings.knownDisplays == ["B": KnownDisplay(name: "Bench", hasNotch: true)], "a display without a name is left out")
            #expect(!settings.confirmSpacingRelaunch)
            #expect(settings.unconfirmedSpacingProfileScope == .allProfiles)
            #expect(settings.spacingApplyMode == .relaunchApps)
            #expect(settings.wideDisplayRule.isEnabled && settings.wideDisplayRule.minimumWidth == 2560)

            nonisolated(unsafe) var assigned = false
            withObservationTracking {
                _ = (settings.configurations, settings.globalConfiguration, settings.knownDisplays, settings.confirmSpacingRelaunch)
                _ = (settings.unconfirmedSpacingProfileScope, settings.spacingApplyMode, settings.wideDisplayRule.isEnabled, settings.wideDisplayRule.minimumWidth)
            } onChange: {
                assigned = true
            }
            feature.reload()
            #expect(!assigned, "values that stayed the same are not assigned again")
        }
    }

    @Test("Each Spaces control asks the app, which makes the request with its own session and answers whether macOS took it")
    func appAsksTheMenuBarAgent() async throws {
        try await withWorld { world in
            let presentation = FakePresentation()
            let remote = linkedRemote(to: appFeature(world, presentation: presentation))
            let controls = RemoteMenuBarPresentation { remote }
            let taken = [
                await controls.revealSystemMenuBar(), await controls.setSystemMenuBarHidden(true), await controls.setSystemMenuBarAutoShowEnabled(false),
                await controls.setSystemMenuBarHidden(true, spaceID: 9), await controls.setSystemMenuBarAutoShowDisabled(true, spaceID: 9),
                await controls.setSystemMenuBarAutohideHeight(12, spaceID: 9), await controls.clearSystemMenuBarOverrides(forSpace: 9),
                await controls.setFullScreenAppearanceOnUserSpace(true),
            ]
            #expect(taken == Array(repeating: true, count: 8))
            #expect(presentation.calls == [
                "reveal", "hidden true", "autoShow false", "hidden true in 9", "autoShowDisabled true in 9",
                "height 12.0 in 9", "clear 9", "fullScreen true",
            ])
            #expect(recorder.requests == Array(repeating: Link.presentation, count: 8))

            presentation.accepts = false
            #expect(await controls.setSystemMenuBarHidden(false) == false, "what macOS declines is declined here")
            await #expect(throws: SettingsRequestError.failed(SettingsRequestError.unreadable.localizedDescription)) {
                let _: Bool = try await remote.request(Link.presentation, "not a request")
            }
            #expect(presentation.calls.count == 9, "a request the app can't read reaches no session")
        }
    }

    @Test("The settings process sets its own objects to what the app sends")
    func settingsProcessMirrorsTheApp() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let presentation = RemoteMenuBarPresentation { nil }
            let feature = Link.child(world.appState, presentation: presentation)
            let active = world.profiles.activeProfileID
            world.profiles.activeProfileID = nil

            try feature.statuses[Link.spacingApply]?(payload(Link.SpacingApply(isReapplying: true, failure: "Could not relaunch: Clock")))
            #expect(world.settings.isReapplyingSpacing)
            #expect(world.settings.lastSpacingApplyFailure == "Could not relaunch: Clock")

            try feature.statuses[Link.spaces]?(payload(Link.Spaces(active: 4242, listed: [4242], takesPresentationRequests: true)))
            #expect(world.appState.activeSpace.spaceID == 4242)
            #expect(presentation.isSupported)

            try feature.statuses[Link.activeProfile]?(payload(Link.ActiveProfile(id: active)))
            #expect(world.profiles.activeProfileID == active)

            try Defaults.set(JSONEncoder().encode([Self.studio: DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(-4)]), forKey: .displayThawBarConfigurations)
            feature.reload()
            #expect(savedOffset(world) == -4, "what the app saved is read again")
        }
    }

    @Test("In the app a commit runs here before the page goes on, and a save that fails is handed back at once")
    func commitHere() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let failed: (DisplayCommitFailure) -> Void = { [recorder] in recorder.failures.append($0) }
            let active = world.profiles.activeProfileID
            DisplayProfileCommit(change: .spacing(displayID: Self.studio, offset: 6), scope: .activeProfile, activeProfileID: active)
                .perform(on: world.appState, remote: nil, failed: failed)
            #expect(savedOffset(world) == 6 && recorder.failures.isEmpty)
            #expect(try profile("Work", in: world).displayConfigurations[Self.studio]?.itemSpacingOffset == 6)

            try removeActiveProfileFile(world)
            DisplayProfileCommit(change: .spacing(displayID: Self.studio, offset: 8), scope: .activeProfile, activeProfileID: active)
                .perform(on: world.appState, remote: nil, failed: failed)
            #expect(savedOffset(world) == 6, "the unsaved spacing is rolled back")
            #expect(recorder.failures.map(\.displayID) == [Self.studio] && recorder.failures.first?.message.isEmpty == false)
        }
    }

    @Test("From the settings process a commit goes to the app with this process's display settings, and the page takes what the app left")
    func commitInTheApp() async throws {
        try await withWorld(profiles: ["Work"]) { app in
            try await withWorld { page in
                let remote = linkedRemote(to: appFeature(app))
                let failed: (DisplayCommitFailure) -> Void = { [recorder] in recorder.failures.append($0) }
                let active = app.profiles.activeProfileID
                // An edit the page made a moment ago, which the app has not read yet.
                page.settings.configurations[Self.studio] = page.settings.configurations[Self.studio]?.withGridColumns(7)
                DisplayProfileCommit(change: .spacing(displayID: Self.studio, offset: 6), scope: .activeProfile, activeProfileID: active)
                    .perform(on: page.appState, remote: remote, failed: failed)
                #expect(recorder.requests == [Link.commit], "the request leaves before the page goes on")
                #expect(savedOffset(page) == 4, "the app makes the change")
                #expect(await settingsLinkWait { savedOffset(page) == 6 })
                #expect(app.settings.configuration(forUUID: Self.studio).gridColumns == 7, "the earlier edit is kept")
                #expect(page.settings.snapshot == app.settings.snapshot && recorder.failures.isEmpty)

                try removeActiveProfileFile(app)
                DisplayProfileCommit(change: .spacing(displayID: Self.studio, offset: 8), scope: .activeProfile, activeProfileID: active)
                    .perform(on: page.appState, remote: remote, failed: failed)
                #expect(await settingsLinkWait { recorder.failures.count == 1 })
                #expect(recorder.failures.first?.displayID == Self.studio && recorder.failures.first?.message.isEmpty == false)
                #expect(savedOffset(page) == 6 && savedOffset(app) == 6, "the app rolled the spacing back")

                // An app that gives no answer to use fails the commit too.
                DisplayProfileCommit(change: .template(.defaultConfiguration), scope: nil, activeProfileID: nil)
                    .perform(on: page.appState, remote: linkedRemote(to: SettingsAppFeature()), failed: failed)
                #expect(await settingsLinkWait { recorder.failures.count == 2 })
                #expect(recorder.failures.last?.displayID == nil && savedOffset(page) == 6)
            }
        }
    }

    @Test("Reapply Spacing asks in the settings process and has the app relaunch, and relaunches here in the app")
    func reapplyHereOrInTheApp() async throws {
        try await withWorld { world in
            let uuid = try #require(world.settings.activeMenuBarDisplayUUID, "the test host has a display that owns the menu bar")
            let remote = SettingsRemote { [recorder] in recorder.messages.append($0) }
            let settings = world.settings
            installSpacingHost(world)
            let answer: (Bool) -> @MainActor () -> Bool = { [recorder] approves in
                {
                    recorder.asked += 1
                    return approves
                }
            }
            settings.requestSpacingReapply(forDisplayUUID: uuid, remote: remote, confirm: answer(false))
            settings.requestSpacingReapply(forDisplayUUID: "NOT-THE-ACTIVE-DISPLAY", remote: remote, confirm: answer(true))
            #expect(recorder.asked == 1 && recorder.messages.isEmpty, "Cancel and another display send nothing")

            settings.requestSpacingReapply(forDisplayUUID: uuid, remote: remote, confirm: answer(true))
            settings.confirmSpacingRelaunch = false
            settings.requestSpacingReapply(forDisplayUUID: uuid, remote: remote, confirm: answer(true))
            let command = "\(Link.reapplySpacing) \(uuid)"
            #expect(recorder.asked == 2 && recorder.commands == [command, command], "with confirmations off it goes without asking")
            #expect(recorder.applies.isEmpty, "the settings process relaunches nothing itself")

            settings.isReapplyingSpacing = true
            settings.requestSpacingReapply(forDisplayUUID: uuid, remote: remote, confirm: answer(true))
            #expect(recorder.messages.count == 2, "nothing is sent while the app is relaunching")
            settings.isReapplyingSpacing = false

            settings.requestSpacingReapply(forDisplayUUID: uuid, remote: nil)
            #expect(await settingsLinkWait { recorder.applies.count == 1 && !settings.isReapplyingSpacing })
            #expect(recorder.messages.count == 2)
        }
    }

    @Test("The Spaces controls use this process's session in the app and the app's from the settings process, where no answer counts as declined")
    func presentationHereOrInTheApp() async {
        let silent = SettingsRemote { [recorder] in recorder.messages.append($0) }
        #expect(MenuBarPresentationProvider.forSettings(remote: nil) === MenuBarPresentationProvider.current)
        #expect(MenuBarPresentationProvider.forSettings(remote: silent) === RemoteMenuBarPresentation.shared)

        let unanswered = RemoteMenuBarPresentation(patience: .milliseconds(20)) { silent }
        #expect(await unanswered.setFullScreenAppearanceOnUserSpace(true) == false)
        #expect(recorder.requests == [Link.presentation])
        #expect(await RemoteMenuBarPresentation { nil }.revealSystemMenuBar() == false, "with no app to ask, nothing is taken")
    }
}
