//
//  SettingsLinkHotkeysTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawUI

private typealias Link = HotkeysSettingsLink

/// The app as the relay sees it: hotkeys with no app behind them, and a registry that only keeps count.
@MainActor
private final class FakeApp {
    let swap = Hotkey(action: .toggleSwap)
    let zen = Hotkey(action: .toggleZenMode)
    var items = [String: Hotkey]()
    var profiles = [UUID: Hotkey]()
    /// The hotkeys whose combination the registry holds.
    var claimed = Set<ObjectIdentifier>()
    /// Stands for a combination that can't be claimed, such as one another app holds.
    var refuses = false
    var boundItems = [String]()
    var captures = 0

    init() {
        follow(swap)
        follow(zen)
    }

    /// Claims a combination as it is assigned, as a hotkey with the app behind it does.
    func follow(_ hotkey: Hotkey) {
        hotkey.keyCombinationDidChange = { [unowned self, unowned hotkey] in self.setRegistered(hotkey, true) }
    }

    func setRegistered(_ hotkey: Hotkey, _ isRegistered: Bool) {
        if isRegistered, hotkey.keyCombination != nil, !refuses {
            claimed.insert(ObjectIdentifier(hotkey))
        } else {
            claimed.remove(ObjectIdentifier(hotkey))
        }
    }

    var app: SettingsHotkeysRelay.App {
        let actions = [swap, zen]
        return SettingsHotkeysRelay.App(
            actions: { actions },
            items: { self.items },
            profiles: { self.profiles },
            bindItem: { identifier, _ in self.boundItems.append(identifier) },
            isRegistered: { self.claimed.contains(ObjectIdentifier($0)) },
            setRegistered: { self.setRegistered($0, $1) }
        )
    }
}

/// The models the pages in the settings process read their hotkeys from.
@MainActor
private final class FakePages {
    let swap = Hotkey(action: .toggleSwap)
    var present = Set<String>()
    var items = [String: Hotkey]()
    var profiles = [UUID: Hotkey]()

    var models: SettingsHotkeysMirror.Models {
        SettingsHotkeysMirror.Models(
            actions: [swap],
            presentItems: { self.present },
            showItems: { self.items = $0 },
            showProfiles: { self.profiles = $0 }
        )
    }
}

@Suite("Settings process link, Shortcuts page")
@MainActor
struct SettingsLinkHotkeysTests {
    private let fake = FakeApp()
    private let pages = FakePages()
    private let sent = SettingsLinkOutbox()
    private let optionA = KeyCombination(key: .a, modifiers: .option)
    private let controlB = KeyCombination(key: .b, modifiers: .control)
    private let profileID = UUID()
    private let swapTarget = Link.Target(kind: .action, id: HotkeyAction.toggleSwap.rawValue)
    private let zenTarget = Link.Target(kind: .action, id: HotkeyAction.toggleZenMode.rawValue)
    private let clockTarget = Link.Target(kind: .item, id: "clock")

    private func appFeature() -> SettingsAppFeature {
        .hotkeys(relay: SettingsHotkeysRelay(app: fake.app)) { [fake] in fake.captures += 1 }
    }

    private func mirror() -> SettingsHotkeysMirror {
        SettingsHotkeysMirror(models: pages.models, remote: { [sent] in sent.remote })
    }

    private func payload(_ value: some Encodable) throws -> Data {
        try #require(SettingsLinkPayload.encode(value))
    }

    private func bindings(_ feature: SettingsAppFeature) throws -> Link.Bindings {
        try #require(feature.statuses[Link.bindings]?().flatMap { SettingsLinkPayload.decode(Link.Bindings.self, from: $0) })
    }

    private func run(_ feature: SettingsAppFeature, _ name: String, _ value: some Encodable) throws {
        try feature.commands[name]?(payload(value))
    }

    // MARK: Payloads

    @Test("Each payload survives the link")
    func payloads() throws {
        let bindings = Link.Bindings(
            revision: 3,
            actions: [swapTarget.id: Link.Binding(combination: optionA, isRegistered: true)],
            items: [clockTarget.id: Link.Binding(combination: controlB, isRegistered: false)],
            profiles: [profileID.uuidString: Link.Binding(combination: nil, isRegistered: false)]
        )
        let assigned = Link.Assignment(target: clockTarget, combination: optionA)
        let cleared = Link.Assignment(target: clockTarget, combination: nil)
        let recording = Link.Recording(target: Link.Target(kind: .profile, id: profileID.uuidString), isRecording: true)

        #expect(try SettingsLinkPayload.decode(from: payload(bindings)) == bindings)
        #expect(try SettingsLinkPayload.decode(from: payload(assigned)) == assigned)
        #expect(try SettingsLinkPayload.decode(from: payload(cleared)) == cleared)
        #expect(try SettingsLinkPayload.decode(from: payload(recording)) == recording)
    }

    // MARK: App side

    @Test("The app sends the combinations it holds and whether it could register each")
    func appSendsBindings() throws {
        let feature = appFeature()
        #expect(try bindings(feature) == Link.Bindings())

        let clock = Hotkey(action: .openMenuBarItem)
        let profile = Hotkey(action: .profileApply)
        fake.follow(clock)
        fake.items = [clockTarget.id: clock, "unbound": Hotkey(action: .openMenuBarItem)]
        fake.profiles = [profileID: profile]
        fake.swap.keyCombination = optionA
        fake.refuses = true
        clock.keyCombination = controlB

        let sent = try bindings(feature)
        #expect(sent.actions == [swapTarget.id: Link.Binding(combination: optionA, isRegistered: true)])
        #expect(sent.items == [clockTarget.id: Link.Binding(combination: controlB, isRegistered: false)], "An item with no shortcut is left out")
        #expect(sent.profiles == [profileID.uuidString: Link.Binding(combination: nil, isRegistered: false)], "Every profile's hotkey is sent")
    }

    @Test("The app assigns what a recorder in the settings process chose, and answers every edit")
    func appAssigns() throws {
        let feature = appFeature()
        let clock = Hotkey(action: .openMenuBarItem)
        let profile = Hotkey(action: .profileApply)
        fake.items = [clockTarget.id: clock]
        fake.profiles = [profileID: profile]

        try run(feature, Link.assign, Link.Assignment(target: swapTarget, combination: optionA))
        try run(feature, Link.assign, Link.Assignment(target: clockTarget, combination: controlB))
        try run(feature, Link.assign, Link.Assignment(target: Link.Target(kind: .profile, id: profileID.uuidString), combination: optionA))
        #expect(fake.swap.keyCombination == optionA)
        #expect(fake.claimed == [ObjectIdentifier(fake.swap)], "Assigning registers, as a recorder in the app does")
        #expect(clock.keyCombination == controlB)
        #expect(profile.keyCombination == optionA)

        let answered = try bindings(feature)
        try run(feature, Link.assign, Link.Assignment(target: swapTarget, combination: optionA))
        #expect(try bindings(feature) != answered, "The same combination again still gets an answer")

        try run(feature, Link.assign, Link.Assignment(target: swapTarget, combination: nil))
        #expect(fake.swap.keyCombination == nil)
        #expect(fake.claimed.isEmpty)

        try run(feature, Link.assign, Link.Assignment(target: Link.Target(kind: .item, id: "new"), combination: optionA))
        try run(feature, Link.assign, Link.Assignment(target: Link.Target(kind: .action, id: "Missing"), combination: optionA))
        try run(feature, Link.assign, Link.Assignment(target: Link.Target(kind: .profile, id: "not an ID"), combination: optionA))
        feature.commands[Link.assign]?(Data("not an assignment".utf8))
        #expect(fake.boundItems == ["new"], "An item the app has no hotkey for yet is saved and gets one")
        #expect(fake.zen.keyCombination == nil)
    }

    @Test("A hotkey stands down while its recorder listens, and goes back to work when the settings process ends")
    func appStandsDown() throws {
        let feature = appFeature()
        fake.swap.keyCombination = optionA
        fake.refuses = true
        fake.zen.keyCombination = controlB
        fake.refuses = false
        #expect(fake.claimed == [ObjectIdentifier(fake.swap)])

        try run(feature, Link.recording, Link.Recording(target: swapTarget, isRecording: true))
        #expect(fake.claimed.isEmpty)
        #expect(try bindings(feature).actions[swapTarget.id]?.isRegistered == true, "Standing down is not a failed registration")
        try run(feature, Link.recording, Link.Recording(target: swapTarget, isRecording: false))
        #expect(fake.claimed == [ObjectIdentifier(fake.swap)])

        try run(feature, Link.recording, Link.Recording(target: swapTarget, isRecording: true))
        try run(feature, Link.recording, Link.Recording(target: zenTarget, isRecording: true))
        try run(feature, Link.recording, Link.Recording(target: clockTarget, isRecording: true))
        feature.commands[Link.recording]?(Data("not a recording".utf8))
        #expect(fake.claimed.isEmpty)
        feature.processEnded()
        #expect(fake.claimed == [ObjectIdentifier(fake.swap)], "Only a hotkey that was registered is claimed again")

        fake.claimed = []
        feature.processEnded()
        #expect(fake.claimed.isEmpty, "Nothing is left to undo")
    }

    // MARK: Settings process side

    @Test("The settings process shows the app's bindings without sending them back")
    func childShowsBindings() throws {
        let status = try #require(SettingsChildFeature.hotkeys(mirror: mirror()).statuses[Link.bindings])
        pages.present = [clockTarget.id]
        var shown = Link.Bindings()
        shown.actions[swapTarget.id] = Link.Binding(combination: optionA, isRegistered: true)
        shown.items["quit"] = Link.Binding(combination: controlB, isRegistered: false)
        shown.profiles[profileID.uuidString] = Link.Binding(combination: nil, isRegistered: false)
        try status(payload(shown))

        #expect(pages.swap.keyCombination == optionA)
        #expect(pages.swap.isEnabled)
        #expect(Set(pages.items.keys) == [clockTarget.id, "quit"], "The items in the bar and those with a saved shortcut")
        #expect(pages.items[clockTarget.id]?.keyCombination == nil)
        #expect(pages.items["quit"]?.action == .openMenuBarItem)
        #expect(pages.items["quit"]?.keyCombination == controlB)
        #expect(pages.items["quit"]?.isEnabled == false, "One the app could not register shows as empty")
        #expect(pages.profiles[profileID]?.action == .profileApply)

        let quit = pages.items["quit"]
        shown.actions = [:]
        shown.items["quit"]?.isRegistered = true
        try status(payload(shown))
        #expect(pages.swap.keyCombination == nil)
        #expect(!pages.swap.isEnabled)
        #expect(pages.items["quit"] === quit, "A recorder keeps its hotkey")
        #expect(quit?.isEnabled == true)

        try status(payload(Link.Bindings()))
        status(Data("not bindings".utf8))
        #expect(Set(pages.items.keys) == [clockTarget.id])
        #expect(pages.profiles.isEmpty)
        #expect(sent.messages.isEmpty)
    }

    @Test("A recorder in the settings process sends its edits and its listening to the app")
    func childSendsEdits() throws {
        let mirror = mirror()
        pages.present = [clockTarget.id]
        mirror.itemsChanged()
        let clock = try #require(pages.items[clockTarget.id])

        clock.setRecording(true)
        clock.keyCombination = optionA
        clock.setRecording(false)
        pages.swap.keyCombination = nil
        #expect(clock.isEnabled, "The recorder shows the choice before the app answers")
        #expect(sent.commands(Link.recording) == [true, false].map { Link.Recording(target: clockTarget, isRecording: $0) })
        #expect(sent.commands(Link.assign) == [
            Link.Assignment(target: clockTarget, combination: optionA),
            Link.Assignment(target: swapTarget, combination: nil),
        ])

        pages.present = [clockTarget.id, "wifi"]
        mirror.itemsChanged()
        #expect(clock.keyCombination == optionA, "An edit the app has yet to answer outlasts a change to the item list")
        #expect(pages.items["wifi"] != nil)
        #expect(sent.messages.count == 4)
    }

    @Test("With no settings process a recorder stands its own hotkey down and sends nothing")
    func localRecording() {
        let silent = SettingsHotkeysMirror(models: pages.models, remote: { nil })
        pages.swap.keyCombination = optionA
        pages.swap.setRecording(true)
        pages.swap.setRecording(false)
        silent.itemsChanged()

        let hotkey = Hotkey(action: .toggleZenMode, keyCombination: controlB)
        hotkey.setRecording(true)
        hotkey.setRecording(false)
        #expect(!hotkey.isEnabled, "A hotkey with no app behind it registers nothing")
        #expect(sent.messages.isEmpty)
    }

    // MARK: Both sides

    @Test("An edit in the settings process reaches the app's hotkey, and the app's answer comes back")
    func editReachesTheApp() throws {
        let app = appFeature()
        let remote = SettingsRemote { message in
            if case let .command(name, payload) = message {
                app.commands[name]?(payload)
            }
        }
        let mirror = SettingsHotkeysMirror(models: pages.models, remote: { remote })

        pages.swap.keyCombination = optionA
        #expect(fake.swap.keyCombination == optionA)
        #expect(fake.claimed == [ObjectIdentifier(fake.swap)])
        try mirror.show(bindings(app))
        #expect(pages.swap.isEnabled)

        fake.refuses = true
        pages.swap.keyCombination = controlB
        try mirror.show(bindings(app))
        #expect(pages.swap.keyCombination == controlB)
        #expect(!pages.swap.isEnabled, "The app could not claim it, so the recorder shows empty as it does in the app")

        fake.swap.keyCombination = nil
        try mirror.show(bindings(app))
        #expect(pages.swap.keyCombination == nil, "A change made in the app shows here")
        #expect(fake.swap.keyCombination == nil, "and is not sent back")

        app.commands[Link.capture]?(Data())
        #expect(fake.captures == 1)
    }

    @Test("The Shortcuts pane runs in the settings process, with its share of the link on both sides", .scratchDefaults)
    func registered() async throws {
        let appState = AppState()
        #expect(SettingsProcessRoute.ownProcessPanes.contains(SettingsNavigationIdentifier.hotkeys.rawValue))
        let app = try #require(SettingsLinkFeatures.app(appState).first { $0.statuses[Link.bindings] != nil })

        // The app's own models, which register nothing before the app has launched.
        try run(app, Link.assign, Link.Assignment(target: swapTarget, combination: optionA))
        try run(app, Link.assign, Link.Assignment(target: clockTarget, combination: controlB))
        try run(app, Link.recording, Link.Recording(target: swapTarget, isRecording: true))
        try run(app, Link.recording, Link.Recording(target: swapTarget, isRecording: false))
        app.commands[Link.capture]?(Data())
        app.processEnded()
        #expect(appState.settings.hotkeys.hotkey(withAction: .toggleSwap)?.keyCombination == optionA)
        #expect(HotkeyBindingStore.items.rawBindings()[clockTarget.id] != nil)
        #expect(try bindings(app).actions == [swapTarget.id: Link.Binding(combination: optionA, isRegistered: false)])

        // The same models as the settings process has them, where the app's bindings replace their own.
        let status = try #require(SettingsLinkFeatures.child(appState).compactMap { $0.statuses[Link.bindings] }.first)
        var shown = Link.Bindings()
        shown.items[clockTarget.id] = Link.Binding(combination: controlB, isRegistered: true)
        shown.profiles[profileID.uuidString] = Link.Binding(combination: optionA, isRegistered: true)
        try status(payload(shown))
        #expect(appState.settings.hotkeys.hotkey(withAction: .toggleSwap)?.keyCombination == nil)
        #expect(appState.menuBarManager.itemHotkeys[clockTarget.id]?.keyCombination == controlB)
        #expect(appState.profileManager.profileHotkeys[profileID]?.keyCombination == optionA)

        await appState.imageCache.captureForItemHotkeyList(remote: sent.remote)
        await appState.imageCache.captureForItemHotkeyList(remote: nil)
        #expect(sent.messages == [.command(name: Link.capture, payload: Data())])
    }
}
