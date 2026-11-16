//
//  AppearanceSettingsLinkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Observation
import os
import Testing
@testable import Thaw

/// What the settings process sent, as the app would receive it.
@MainActor
private final class SentMessages {
    private(set) var messages = [SettingsLinkMessage]()
    private(set) lazy var remote = SettingsRemote { [weak self] in self?.messages.append($0) }

    /// The payloads of the commands sent under this name, decoded.
    func commands<Payload: Decodable>(_ name: String, as _: Payload.Type = Payload.self) -> [Payload] {
        messages.compactMap { message in
            guard case .command(name, let payload) = message else { return nil }
            return SettingsLinkPayload.decode(Payload.self, from: payload)
        }
    }
}

/// The Appearance page across the app and its settings process: one appearance manager stands for
/// each, both on one throwaway defaults suite, as the two processes share the real one.
@Suite("Settings process link, Appearance page", .serialized, .scratchDefaults)
@MainActor
struct AppearanceSettingsLinkTests {
    private typealias Link = AppearanceSettingsLink

    private let appAppearance = MenuBarAppearanceManager()
    private let appMenuBar = MenuBarManager()
    private let childAppearance = MenuBarAppearanceManager()
    private let childMenuBar = MenuBarManager()
    private let sent = SentMessages()

    /// A look that differs from the default in a plain value and in a color.
    private var customLook: MenuBarAppearanceConfigurationV2 {
        var look = MenuBarAppearanceConfigurationV2.defaultConfiguration
        look.isInset.toggle()
        look.staticConfiguration.tintKind = .solid
        look.staticConfiguration.tintColor = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        return look
    }

    private func appFeature() -> SettingsAppFeature {
        Link.app(appearance: appAppearance, menuBar: appMenuBar)
    }

    private func childFeature() -> SettingsChildFeature {
        Link.child(appearance: childAppearance, menuBar: childMenuBar, remote: { [sent] in sent.remote })
    }

    /// Whether anything that draws the look would be told to draw again while body runs.
    private func redraws(_ appearance: MenuBarAppearanceManager, during body: () -> Void) -> Bool {
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = appearance.effectiveConfiguration
        } onChange: {
            changed.withLock { $0 = true }
        }
        body()
        return changed.withLock { $0 }
    }

    // MARK: Payloads

    @Test("Each payload survives the link")
    func payloads() throws {
        let surroundings = Link.Surroundings(activeSpaceID: 7, activeSpaceKey: "K", isMenuBarHiddenBySystem: true)
        let look = Link.Look(configuration: customLook, spaceOverrides: ["K": .defaultConfiguration])
        let preview = Link.Preview(configuration: customLook.staticConfiguration)
        let stopped = Link.Preview(configuration: nil)

        #expect(try SettingsLinkPayload.decode(from: #require(SettingsLinkPayload.encode(surroundings))) == surroundings)
        #expect(try SettingsLinkPayload.decode(from: #require(SettingsLinkPayload.encode(look))) == look)
        #expect(try SettingsLinkPayload.decode(from: #require(SettingsLinkPayload.encode(preview))) == preview)
        #expect(try SettingsLinkPayload.decode(from: #require(SettingsLinkPayload.encode(stopped))) == stopped)
    }

    // MARK: App side

    @Test("The app says which Space is active and whether macOS hides the menu bar")
    func appSendsSurroundings() throws {
        let status = try #require(appFeature().statuses[Link.surroundings])
        let first = try #require(status().flatMap { SettingsLinkPayload.decode(Link.Surroundings.self, from: $0) })
        #expect(first.activeSpaceID == appAppearance.activeSpaceID)
        #expect(first.activeSpaceKey == appAppearance.activeSpaceKey)
        #expect(!first.isMenuBarHiddenBySystem)

        appMenuBar.isMenuBarHiddenBySystemUserDefaults = true
        let second = try #require(status().flatMap { SettingsLinkPayload.decode(Link.Surroundings.self, from: $0) })
        #expect(second.isMenuBarHiddenBySystem)
    }

    @Test("The app takes over a look the settings process sends, without saving it a second time")
    func appAdoptsSentLook() throws {
        let command = try #require(appFeature().commands[Link.look])
        let look = Link.Look(configuration: customLook, spaceOverrides: ["K": .defaultConfiguration])
        var savedCount = 0
        appAppearance.onLookSaved = { savedCount += 1 }

        try command(#require(SettingsLinkPayload.encode(look)))
        #expect(appAppearance.configuration == customLook)
        #expect(appAppearance.spaceOverrides == look.spaceOverrides)
        #expect(Defaults.data(forKey: .menuBarAppearanceConfigurationV2) == nil, "The settings process saved it already")
        #expect(Defaults.data(forKey: .menuBarAppearanceSpaceOverrides) == nil)
        #expect(savedCount == 0)

        command(Data("not a look".utf8))
        #expect(appAppearance.configuration == customLook, "A payload that isn't a look changes nothing")

        appAppearance.configuration.isInset.toggle()
        #expect(savedCount == 1, "The app's own edits are saved as before")
        #expect(Defaults.data(forKey: .menuBarAppearanceConfigurationV2) != nil)
    }

    @Test("The app reads the saved look again after the settings process wrote the defaults, and only redraws for a change")
    func appReloadsSavedLook() {
        let feature = appFeature()
        childAppearance.configuration = customLook
        childAppearance.saveOverrideForActiveSpace()

        #expect(redraws(appAppearance) { feature.reload() })
        #expect(appAppearance.configuration == customLook)
        #expect(appAppearance.spaceOverrides == childAppearance.spaceOverrides)

        #expect(!redraws(appAppearance) { feature.reload() }, "An unrelated defaults write leaves the menu bar alone")
    }

    @Test("A reload with nothing saved, or with something unreadable, keeps the look the app has")
    func appKeepsLookWithoutSavedOne() {
        let feature = appFeature()
        feature.reload()
        #expect(appAppearance.configuration == .defaultConfiguration)

        appAppearance.configuration = customLook
        Defaults.set(Data("not a look".utf8), forKey: .menuBarAppearanceConfigurationV2)
        Defaults.set(Data("not a look".utf8), forKey: .menuBarAppearanceSpaceOverrides)
        feature.reload()
        #expect(appAppearance.configuration == customLook)
        #expect(appAppearance.spaceOverrides.isEmpty)
    }

    @Test("The app shows a preview while it is held, and drops it when the settings process ends")
    func appPreviews() throws {
        let feature = appFeature()
        let command = try #require(feature.commands[Link.preview])
        let shown = customLook.staticConfiguration

        try command(#require(SettingsLinkPayload.encode(Link.Preview(configuration: shown))))
        #expect(appAppearance.previewConfiguration == shown)
        command(Data("not a preview".utf8))
        #expect(appAppearance.previewConfiguration == shown, "A payload that isn't a preview changes nothing")
        try command(#require(SettingsLinkPayload.encode(Link.Preview(configuration: nil))))
        #expect(appAppearance.previewConfiguration == nil)

        try command(#require(SettingsLinkPayload.encode(Link.Preview(configuration: shown))))
        feature.processEnded()
        #expect(appAppearance.previewConfiguration == nil, "A process that ended can't let go of the button")
        feature.processEnded()
        #expect(appAppearance.previewConfiguration == nil)
    }

    @Test("The settings process starts with the saved look, and reads it again after the app wrote the defaults")
    func childReadsSavedLook() {
        appAppearance.configuration = customLook
        let feature = childFeature()
        #expect(childAppearance.configuration == customLook)

        appAppearance.configuration.isInset.toggle()
        feature.reload()
        #expect(childAppearance.configuration == appAppearance.configuration)
        #expect(sent.messages.isEmpty, "A look read from the defaults is not sent back to the app")
    }

    @Test("The settings process sends each look it saves, shared or a Space's own")
    func childSendsSavedLook() {
        _ = childFeature()
        childAppearance.editedConfiguration = customLook
        childAppearance.saveOverrideForActiveSpace()

        let looks: [Link.Look] = sent.commands(Link.look)
        #expect(looks.count == 2)
        #expect(looks.first == Link.Look(configuration: customLook, spaceOverrides: [:]))
        #expect(looks.last == Link.Look(configuration: customLook, spaceOverrides: childAppearance.spaceOverrides))
        #expect(!childAppearance.spaceOverrides.isEmpty)
    }

    @Test("The settings process edits the look of the Space the app says is active")
    func childMirrorsSurroundings() throws {
        let status = try #require(childFeature().statuses[Link.surroundings])
        var ownLook = customLook
        ownLook.isInset.toggle()

        try status(#require(SettingsLinkPayload.encode(Link.Surroundings(activeSpaceID: 7, activeSpaceKey: "K", isMenuBarHiddenBySystem: true))))
        #expect(childAppearance.activeSpaceID == 7)
        #expect(childAppearance.activeSpaceKey == "K")
        #expect(childMenuBar.isMenuBarHiddenBySystemUserDefaults)

        childAppearance.saveOverrideForActiveSpace()
        childAppearance.editedConfiguration = ownLook
        #expect(childAppearance.spaceOverrides == ["K": ownLook], "The Space's own look is kept under the key the app gave")
        #expect(childAppearance.configuration == .defaultConfiguration)

        try status(#require(SettingsLinkPayload.encode(Link.Surroundings(activeSpaceID: 8, activeSpaceKey: nil, isMenuBarHiddenBySystem: false))))
        #expect(childAppearance.activeSpaceKey == nil)
        #expect(!childAppearance.activeSpaceHasOverride)
        #expect(childAppearance.editedConfiguration == .defaultConfiguration, "Another Space shows the shared look")
        #expect(!childMenuBar.isMenuBarHiddenBySystemUserDefaults)

        status(Data("not surroundings".utf8))
        #expect(childAppearance.activeSpaceID == 8, "A payload that isn't the surroundings changes nothing")
    }

    // MARK: Both sides

    @Test("An edit in the settings process reaches the app's menu bar through the link")
    func editReachesTheApp() {
        let app = appFeature()
        let remote = SettingsRemote { message in
            if case let .command(name, payload) = message {
                app.commands[name]?(payload)
            }
        }
        _ = Link.child(appearance: childAppearance, menuBar: childMenuBar, remote: { remote })

        childAppearance.editedConfiguration = customLook
        #expect(appAppearance.effectiveConfiguration == customLook)

        childAppearance.saveOverrideForActiveSpace()
        #expect(appAppearance.spaceOverrides == childAppearance.spaceOverrides)

        #expect(!redraws(appAppearance) { app.reload() }, "The defaults hold what the app already shows")
    }

    @Test("A preview is shown here in the app, and asked of the app from the settings process")
    func previewLocalOrRemote() {
        let shown = customLook.staticConfiguration

        appAppearance.showPreview(shown, remote: nil)
        #expect(appAppearance.previewConfiguration == shown)
        appAppearance.showPreview(nil, remote: nil)
        #expect(appAppearance.previewConfiguration == nil)

        childAppearance.showPreview(shown, remote: sent.remote)
        childAppearance.showPreview(nil, remote: sent.remote)
        #expect(childAppearance.previewConfiguration == nil, "The settings process has no menu bar overlay to show it on")
        #expect(sent.commands(Link.preview) == [Link.Preview(configuration: shown), Link.Preview(configuration: nil)])
    }

    @Test("The Appearance pane runs in the settings process, with its share of the link on both sides")
    func registered() {
        let appState = AppState()
        #expect(SettingsProcessRoute.ownProcessPanes.contains(SettingsNavigationIdentifier.menuBarAppearance.rawValue))
        #expect(SettingsLinkFeatures.app(appState).contains { $0.commands[Link.look] != nil && $0.statuses[Link.surroundings] != nil })
        #expect(SettingsLinkFeatures.child(appState).contains { $0.statuses[Link.surroundings] != nil })
    }
}
