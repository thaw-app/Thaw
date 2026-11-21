//
//  SettingsLinkTriggersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation
import os
import SwiftUI
import Testing
@testable import Thaw
import ThawModuleKit
import ThawUI

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

/// The Triggers page across the app and its settings process. Both read one throwaway defaults
/// suite, as the two processes share the real one.
@Suite("Settings process link, Triggers page", .serialized, .scratchDefaults)
@MainActor
struct SettingsLinkTriggersTests {
    private typealias Page = OffscreenRender<AnyView>

    private static let size = CGSize(width: 760, height: 900)
    private static let moduleURL = URL(filePath: "/Modules/triggers.app")

    private let sent = SentMessages()
    private let start = ContinuousClock.now

    private func item(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: 7, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: 10, y: 0, width: 24, height: 24), title: title, isOnScreen: true
        )
    }

    private func glyph(red: CGFloat) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: 6, height: 6, bitsPerComponent: 8, bytesPerRow: 24,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 6, height: 6))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
    }

    private func payload(_ value: some Encodable) throws -> Data {
        try #require(SettingsLinkPayload.encode(value))
    }

    /// The list's model as the settings process has it, reaching the app through sent.
    private func pageChoices() -> AlertRevealChoices {
        let choices = AlertRevealChoices()
        choices.remote = { [sent] in sent.remote }
        return choices
    }

    /// An app state as the settings process has it: never started, and with a way to the app.
    private func settingsAppState() -> AppState {
        let appState = AppState()
        appState.moduleHost.remote = { [sent] in sent.remote }
        appState.alertRevealWatcher.choices.remote = { [sent] in sent.remote }
        return appState
    }

    private func page(_ view: some View, appState: AppState) -> Page {
        OffscreenRender(
            AnyView(
                view
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
    }

    private func switches(on page: Page) -> [NSObject] {
        page.elements().filter { OffscreenAccessibility.role(of: $0) == .checkBox }
    }

    /// Whether the page shows the spinner the list waits behind.
    private func isWaiting(_ page: Page) -> Bool {
        page.elements().contains { OffscreenAccessibility.role(of: $0) == .busyIndicator }
    }

    private func shows(_ page: Page, _ text: String) -> Bool {
        page.texts().contains { $0.contains(text) }
    }

    /// Whether anything that reads value would be told to redraw while body runs.
    private func redraws(reading value: @autoclosure () -> some Any, during body: () -> Void) -> Bool {
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = value()
        } onChange: {
            changed.withLock { $0 = true }
        }
        body()
        return changed.withLock { $0 }
    }

    private func modulesState(_ state: ModuleHost.State?, enabled: Bool) throws -> Data {
        let manifest = ModuleManifest(identifier: ModuleIdentifier.triggers.rawValue, name: "Triggers", bundleIdentifier: "com.thaw.module.triggers", version: "1", minimumAPIVersion: 1)
        let modules = state.map { [Self.moduleURL: ModuleHost.Module(manifest: manifest, verdict: .launch, state: $0)] } ?? [:]
        return try #require(ModulesLink.State(modules: modules, enabled: enabled ? [ModuleIdentifier.triggers.rawValue] : []).payload)
    }

    // MARK: The settings process's side

    @Test("The list waits for the app's items in the settings process, and never in the app")
    func listWaitsForTheAppsItems() throws {
        #expect(!AlertRevealChoices().awaitsItems, "The app lists its own items")

        let choices = pageChoices()
        let feature = SettingsChildFeature.triggers(choices: choices)
        #expect(choices.awaitsItems)

        feature.statuses[SettingsItemsLink.cache]?(Data("not an item list".utf8))
        #expect(choices.awaitsItems, "A payload it can't read is not the app's items")

        try feature.statuses[SettingsItemsLink.cache]?(payload(MenuBarItemCache(displayID: nil)))
        #expect(!choices.awaitsItems, "An app with nothing in its list has still answered")

        var later = MenuBarItemCache(displayID: 1)
        later[.hidden] = [item("Clock")]
        let laterPayload = try payload(later)
        #expect(!redraws(reading: choices.awaitsItems) { feature.statuses[SettingsItemsLink.cache]?(laterPayload) })
        #expect(!choices.awaitsItems)
    }

    @Test("The list follows the choice the app saved, and a reload for another setting redraws nothing")
    func listFollowsTheAppsChoice() {
        let choices = pageChoices()
        let feature = SettingsChildFeature.triggers(choices: choices)

        MenuBarItemAlertReveals.setEnabled(true, for: "com.example.Clock:Clock")
        #expect(choices.identifiers.isEmpty, "The saved choice is not observable")
        feature.reload()
        #expect(choices.identifiers == ["com.example.Clock:Clock"])

        #expect(!redraws(reading: choices.identifiers) { feature.reload() })

        MenuBarItemAlertReveals.setEnabled(false, for: "com.example.Clock:Clock")
        #expect(redraws(reading: choices.identifiers) { feature.reload() })
        #expect(choices.identifiers.isEmpty)
    }

    @Test("The list shows a wait until the app's items arrive, then what the app has hidden, and its switches save")
    func listShowsTheAppsItems() async throws {
        let appState = settingsAppState()
        let mirror = SettingsItemsMirror(appState: appState, pictureFile: nil) { _ in }
        // The session hands each status to every feature that reads it, the item mirror among them.
        let features: [SettingsChildFeature] = [.items(mirror: mirror), .triggers(appState)]
        let page = page(ThawForm { AlertRevealItemList() }, appState: appState)

        await page.settle(within: .milliseconds(300)) { shows(page, "Hide an item first") }
        #expect(!shows(page, "Hide an item first"), "Nothing is known about the app's items yet")
        #expect(isWaiting(page))
        #expect(switches(on: page).isEmpty)

        let nothingHidden = try payload(MenuBarItemCache(displayID: 1))
        features.forEach { $0.statuses[SettingsItemsLink.cache]?(nothingHidden) }
        #expect(await page.settle { shows(page, "Hide an item first") }, "The app has nothing hidden")
        #expect(!isWaiting(page))

        let clock = item("Clock")
        var cache = MenuBarItemCache(displayID: 1)
        cache[.hidden] = [clock]
        let hidden = try payload(cache)
        features.forEach { $0.statuses[SettingsItemsLink.cache]?(hidden) }
        MenuBarItemAlertReveals.setEnabled(true, for: "com.example.gone:Gone")
        features.forEach { $0.reload() }
        #expect(await page.settle { switches(on: page).count == 2 }, "the hidden item and the opt-in the app saved")
        #expect(shows(page, "com.example.gone:Gone (not currently in the menu bar)"))
        #expect(!shows(page, "Hide an item first"))

        // Present items come first, so the first switch is the hidden item's.
        OffscreenAccessibility.press(try #require(switches(on: page).first))
        #expect(await page.settle { MenuBarItemAlertReveals.contains(clock.tag.tagIdentifier) })
        #expect(sent.messages.isEmpty, "The choice is saved to the defaults, which the link tells the app about")
    }

    // MARK: The app's side

    @Test("A choice saved from the page decides what the app's watcher reveals and whether it captures off screen")
    func savedChoiceReachesTheApp() throws {
        let page = pageChoices()
        let clock = item("Clock").tag
        let identifier = clock.tagIdentifier
        let watcher = MenuBarItemAlertRevealWatcher()
        let imageCache = MenuBarItemImageCache()
        let controller = RecordingSectionController()
        controller.sectionAssignment = [identifier: .hidden]

        try watcher.process([clock: glyph(red: 1)], sectionController: controller, now: start)
        try watcher.process([clock: glyph(red: 0.2)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty, "Not chosen yet")
        #expect(!imageCache.hasBackgroundCaptureDemand(triggersOn: true))

        page.setEnabled(true, for: identifier)
        #expect(sent.messages.isEmpty, "Nothing but the saved choice goes to the app")
        #expect(imageCache.hasBackgroundCaptureDemand(triggersOn: true))
        #expect(!imageCache.hasBackgroundCaptureDemand(triggersOn: false), "With Triggers off nothing reads the pictures")
        #expect(!imageCache.hasBackgroundCaptureDemand(), "Without an app state the module counts as off")
        try watcher.process([clock: glyph(red: 1)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty, "The first picture after the choice is only compared against")
        try watcher.process([clock: glyph(red: 0.2)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals == [identifier])
        #expect(controller.scheduledConceals == [identifier])

        try watcher.process([clock: glyph(red: 1)], sectionController: controller, triggersOn: false, now: start + .seconds(60))
        try watcher.process([clock: glyph(red: 0.2)], sectionController: controller, triggersOn: false, now: start + .seconds(61))
        #expect(controller.temporaryReveals.count == 1, "Nothing is revealed while the Triggers module is off")

        page.setEnabled(false, for: identifier)
        #expect(!imageCache.hasBackgroundCaptureDemand(triggersOn: true))
        try watcher.process([clock: glyph(red: 1)], sectionController: controller, now: start + .seconds(120))
        try watcher.process([clock: glyph(red: 0.5)], sectionController: controller, now: start + .seconds(121))
        #expect(controller.temporaryReveals.count == 1, "Withdrawn from the page, the item stays hidden")
    }

    // MARK: The page and its module

    @Test("The page follows the app's Triggers module: unknown, not installed, off and on")
    func pageFollowsTheAppsModule() async throws {
        let appState = settingsAppState()
        let modules = SettingsChildFeature.modules(host: appState.moduleHost, profiles: appState.profilesFeature)
        let page = page(TriggersSettingsPane(), appState: appState)

        #expect(await page.settle { shows(page, "When an app runs") })
        await page.settle(within: .milliseconds(300)) { shows(page, "Not installed") }
        #expect(!shows(page, "Not installed"), "The app hasn't said which modules it has")
        #expect(switches(on: page).isEmpty)
        #expect(!shows(page, "When an icon changes"))

        try modules.statuses[ModulesLink.state]?(modulesState(nil, enabled: false))
        #expect(await page.settle { shows(page, "Not installed") })
        #expect(switches(on: page).isEmpty)
        #expect(!shows(page, "When an icon changes"))

        // No process has the highest pid, so opening the module lets no running app forward.
        try modules.statuses[ModulesLink.state]?(modulesState(.running(.max), enabled: false))
        #expect(await page.settle { switches(on: page).count == 1 }, "An installed module that is off has its switch")
        #expect(!shows(page, "Not installed"))
        #expect(page.elements(role: .button, label: "Open…").isEmpty)
        #expect(!shows(page, "When an icon changes"), "Icon changes are only watched while the module is on")

        // The switch is AppKit's, and is clicked as a pointer clicks it.
        try #require(page.views(NSSwitch.self).first).performClick(nil)
        #expect(await page.settle { !page.elements(role: .button, label: "Open…").isEmpty })
        #expect(sent.commands(ModulesLink.setEnabled) == [ModulesLink.Switch(identifier: ModuleIdentifier.triggers.rawValue, enabled: true)])
        #expect(await page.settle { shows(page, "When an icon changes") })
        #expect(isWaiting(page), "The list waits for the app's items")
        #expect(!shows(page, "Hide an item first"))

        try page.press("Open…")
        #expect(await page.settle { !sent.commands(ModulesLink.start, as: ModulesLink.Start.self).isEmpty })
        #expect(sent.commands(ModulesLink.start) == [ModulesLink.Start(identifier: ModuleIdentifier.triggers.rawValue, showingWindow: true)])

        try modules.statuses[ModulesLink.state]?(modulesState(.stopped, enabled: false))
        #expect(await page.settle { !shows(page, "When an icon changes") }, "Switched off in the app, the list goes")
    }

    // MARK: Where the page runs

    @Test("Triggers runs in the settings process under either of its names, with its share of the link")
    func pageIsRegistered() throws {
        #expect(SettingsProcessRoute.ownProcessPanes.contains(SettingsNavigationIdentifier.triggers.rawValue))
        let stored = try #require(SettingsNavigationIdentifier(storedValue: "Automation"))
        #expect(SettingsProcessRoute.runsInOwnProcess(pane: stored.rawValue, simpleMode: false, isEnabled: true))

        let appState = settingsAppState()
        let choices = appState.alertRevealWatcher.choices
        let features = SettingsLinkFeatures.child(appState)
        #expect(choices.awaitsItems)

        var cache = MenuBarItemCache(displayID: 1)
        cache[.alwaysHidden] = [item("Clock")]
        let items = try payload(cache)
        features.forEach { $0.statuses[SettingsItemsLink.cache]?(items) }
        #expect(!choices.awaitsItems)
        #expect(appState.itemManager.itemCache == cache, "The item mirror fills the list the page reads")

        MenuBarItemAlertReveals.setEnabled(true, for: "com.example.Clock:Clock")
        features.forEach { $0.reload() }
        #expect(choices.identifiers == ["com.example.Clock:Clock"])
    }
}
