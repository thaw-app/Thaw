//
//  SettingsLinkThawBarTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
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

/// The Thaw Bar page across the app and its settings process: one set of models stands for each,
/// both on one throwaway defaults suite, as the two processes share the real one.
@Suite("Settings process link, Thaw Bar page", .serialized, .scratchDefaults)
@MainActor
struct SettingsLinkThawBarTests {
    private typealias Link = ThawBarSettingsLink
    private static let studio = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    private let appDisplays = DisplaySettingsManager()
    private let appHiding = NativeAppHidingExperiment()
    private let childDisplays = DisplaySettingsManager()
    private let childHiding = NativeAppHidingExperiment()
    private let sent = SentMessages()

    private func payload(_ value: some Encodable) throws -> Data {
        try #require(SettingsLinkPayload.encode(value))
    }

    private func appFeature(show: @escaping Link.Show = { _, _ in }) -> SettingsAppFeature {
        Link.app(displaySettings: appDisplays, hiding: appHiding, show: show)
    }

    private func item(_ title: String, app bundleID: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, windowID: 5), windowID: 5, ownerPID: 1, sourcePID: 2,
            bounds: CGRect(x: 10, y: 0, width: 24, height: 22), title: title, isOnScreen: true
        )
    }

    // MARK: Payloads

    @Test("The request to open the bar survives the link")
    func payloads() throws {
        childDisplays.updateConfiguration(forDisplayUUID: Self.studio) { $0.withThawBarLayout(.grid).withGridColumns(4) }
        let open = Link.Open(section: .alwaysHidden, displayID: 42, settings: childDisplays.snapshot)
        #expect(try SettingsLinkPayload.decode(Link.Open.self, from: payload(open)) == open)
        #expect(SettingsLinkPayload.decode(Link.Open.self, from: Data("7".utf8)) == nil)
    }

    // MARK: The page's edits

    @Test("A display's Thaw Bar setting edited on the page is the app's once it reads the defaults again")
    func displayEditReachesTheApp() {
        let layout = childDisplays.binding(for: .display(Self.studio), \.thawBarLayout) { $0.withThawBarLayout($1) }
        let isOn = childDisplays.binding(for: .display(Self.studio), \.useThawBar) { $0.withUseThawBar($1) }
        layout.wrappedValue = .grid
        isOn.wrappedValue.toggle()
        #expect(appDisplays.snapshot != childDisplays.snapshot)

        appDisplays.loadStoredValues()
        #expect(appDisplays.snapshot == childDisplays.snapshot)
        #expect(appDisplays.configuration(forUUID: Self.studio).thawBarLayout == .grid)
    }

    @Test("An option for all displays edited on the page is the app's once it reads the defaults again")
    func appWideEditReachesTheApp() {
        let app = ThawBarSettings()
        let child = ThawBarSettings()
        child.lockThawBarPosition.toggle()
        child.openHiddenItemsInMenuBar.toggle()
        child.useThawBarOnNotchOverflow.toggle()
        child.thawBarLocationOnHotkey.toggle()

        app.loadInitialState()
        #expect(app.lockThawBarPosition == child.lockThawBarPosition)
        #expect(app.openHiddenItemsInMenuBar == child.openHiddenItemsInMenuBar)
        #expect(app.useThawBarOnNotchOverflow == child.useThawBarOnNotchOverflow)
        #expect(app.thawBarLocationOnHotkey == child.thawBarLocationOnHotkey)
    }

    @Test("The bar's own look edited on the page is sent to the app as it is saved")
    func lookEditReachesTheApp() throws {
        let appAppearance = MenuBarAppearanceManager()
        let childAppearance = MenuBarAppearanceManager()
        let app = AppearanceSettingsLink.app(appearance: appAppearance, menuBar: MenuBarManager())
        _ = AppearanceSettingsLink.child(appearance: childAppearance, menuBar: MenuBarManager(), remote: { [sent] in sent.remote })

        childAppearance.configuration.thawBarAppearance.overridesMenuBar.toggle()
        let look = try #require(sent.commands(AppearanceSettingsLink.look, as: AppearanceSettingsLink.Look.self).last)
        try app.commands[AppearanceSettingsLink.look]?(payload(look))
        #expect(appAppearance.configuration.thawBarAppearance == childAppearance.configuration.thawBarAppearance)
    }

    // MARK: The preview's items

    @Test("The app names the apps the bar leaves out, in one order")
    func switchedOffAppsAreSent() throws {
        let feature = appFeature()
        let status = try #require(feature.statuses[Link.switchedOffApps])
        #expect(try SettingsLinkPayload.decode([String].self, from: #require(status())) == [])

        appHiding.mirrorUserSwitchedOffApps(["com.example.b", "com.example.a", "com.example.c"])
        let first = try #require(status())
        #expect(SettingsLinkPayload.decode([String].self, from: first) == ["com.example.a", "com.example.b", "com.example.c"])
        #expect((0 ..< 20).allSatisfy { _ in status() == first })
    }

    @Test("The preview leaves out the items of the apps the app names")
    func switchedOffAppsAreLeftOut() throws {
        let appState = AppState()
        var cache = MenuBarItemCache(displayID: 1)
        cache[.hidden] = [item("Kept", app: "com.example.kept"), item("Off", app: "com.example.off")]
        appState.itemManager.itemCache = cache
        let hiding = appState.menuBarManager.nativeAppHidingExperiment
        let feature = Link.child(appState)
        func previewed() -> [String] {
            ThawBarItems.items(in: .hidden, itemManager: appState.itemManager, switchedOff: hiding.userSwitchedOffBundleIDs).compactMap(\.title)
        }
        #expect(previewed() == ["Kept", "Off"])

        try feature.statuses[Link.switchedOffApps]?(payload(["com.example.off"]))
        #expect(previewed() == ["Kept"])
        feature.statuses[Link.switchedOffApps]?(Data("not a list".utf8))
        #expect(previewed() == ["Kept"], "A payload that can't be read changes nothing")
        try feature.statuses[Link.switchedOffApps]?(payload([String]()))
        #expect(previewed() == ["Kept", "Off"])
    }

    @Test("Hearing the same apps again tells nobody who watches them")
    func sameAppsAreNoChange() throws {
        let feature = Link.child(hiding: childHiding)
        try feature.statuses[Link.switchedOffApps]?(payload(["com.example.off"]))
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = childHiding.userSwitchedOffBundleIDs
        } onChange: {
            changed.withLock { $0 = true }
        }
        try feature.statuses[Link.switchedOffApps]?(payload(["com.example.off"]))
        #expect(!changed.withLock { $0 })
        #expect(childHiding.userSwitchedOffBundleIDs == ["com.example.off"])
    }

    // MARK: Opening the bar

    @Test("The button opens the bar here in the app, and asks the app from the settings process")
    func openLocalOrRemote() {
        var shown = [String]()
        let show: Link.Show = { shown.append("\($0.rawValue) on \($1)") }
        Link.openBar(.hidden, on: 42, settings: childDisplays, remote: nil, show: show)
        #expect(shown == ["hidden on 42"])
        #expect(sent.messages.isEmpty)

        childDisplays.updateConfiguration(forDisplayUUID: Self.studio) { $0.withGridColumns(7) }
        Link.openBar(.alwaysHidden, on: 43, settings: childDisplays, remote: sent.remote, show: show)
        #expect(shown == ["hidden on 42"], "The settings process has no bar of its own to open")
        #expect(sent.commands(Link.open) == [Link.Open(section: .alwaysHidden, displayID: 43, settings: childDisplays.snapshot)])
        #expect(sent.messages.count == 1)
    }

    @Test("The app opens the bar with the display settings the page had, such as a bar just turned on")
    func appOpensTheBar() throws {
        let wasOn = childDisplays.configuration(forUUID: Self.studio).useThawBar
        var shown = [String]()
        let feature = appFeature { [appDisplays] section, displayID in
            let isOn = appDisplays.configuration(forUUID: Self.studio).useThawBar
            shown.append("\(section.rawValue) on \(displayID), bar \(isOn == wasOn ? "as it was" : "switched")")
        }
        // Turn On & Open: the page changes the setting and asks for the bar before the app has read the defaults.
        childDisplays.updateConfiguration(forDisplayUUID: Self.studio) { $0.withUseThawBar(!wasOn) }
        Link.openBar(.hidden, on: 42, settings: childDisplays, remote: sent.remote) { _, _ in }
        let request = try #require(sent.commands(Link.open, as: Link.Open.self).last)

        try feature.commands[Link.open]?(payload(request))
        #expect(shown == ["hidden on 42, bar switched"])
        #expect(appDisplays.snapshot == childDisplays.snapshot)

        feature.commands[Link.open]?(Data("not a request".utf8))
        #expect(shown.count == 1, "A request that can't be read opens nothing")
    }

    // MARK: Sampling for the preview

    @Test("The preview samples here in the app, and asks the app from the settings process")
    func sampleLocalOrRemote() async {
        var sampledHere = [CGDirectDisplayID]()
        await Link.sampleColors(for: 7, remote: nil) { sampledHere.append($0) }
        #expect(sampledHere == [7])
        #expect(sent.messages.isEmpty)

        await Link.sampleColors(for: 8, remote: sent.remote) { sampledHere.append($0) }
        #expect(sampledHere == [7], "The settings process reads no screen")
        #expect(sent.commands(SettingsItemsLink.sampleColors) == [CGDirectDisplayID(8)])
    }

    // MARK: Routing

    @Test("The Thaw Bar pane runs in the settings process, with its share of the link on both sides")
    func registered() {
        let appState = AppState()
        #expect(SettingsProcessRoute.ownProcessPanes.contains(SettingsNavigationIdentifier.thawBar.rawValue))
        #expect(SettingsProcessRoute.runsInOwnProcess(pane: "Thaw Bar", simpleMode: false, isEnabled: true))
        #expect(SettingsLinkFeatures.app(appState).contains {
            $0.commands[Link.open] != nil && $0.statuses[Link.switchedOffApps] != nil
        })
        #expect(SettingsLinkFeatures.child(appState).contains { $0.statuses[Link.switchedOffApps] != nil })
    }
}
