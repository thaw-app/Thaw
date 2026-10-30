//
//  ReducedModeControllerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
struct ReducedModeControllerTests {
    @MainActor
    private final class Recorder {
        var saved: Set<String> = []
        var hides: [Set<String>] = []
        var available = true
    }

    private func makeController(_ recorder: Recorder) -> (ReducedModeController, NSMenu) {
        let controller = ReducedModeController(environment: .init(
            hidingIsAvailable: { recorder.available },
            hide: { recorder.hides.append($0) },
            apps: { [ReducedModeApp(bundleID: "com.example.a", name: "A"), ReducedModeApp(bundleID: "com.example.b", name: "B")] },
            loadHidden: { recorder.saved },
            saveHidden: { recorder.saved = $0 }
        ))
        return (controller, NSMenu())
    }

    private func choose(_ title: String, in menu: NSMenu, of controller: ReducedModeController) throws {
        controller.menuNeedsUpdate(menu)
        let index = try #require(menu.items.firstIndex { $0.title == title })
        menu.performActionForItem(at: index)
    }

    @Test
    func `ticking an app saves it and hides it, and ticking again shows it`() throws {
        let recorder = Recorder()
        let (controller, menu) = makeController(recorder)

        try choose("A", in: menu, of: controller)
        #expect(recorder.saved == ["com.example.a"])
        #expect(recorder.hides.last == ["com.example.a"])
        controller.menuNeedsUpdate(menu)
        #expect(menu.items.first { $0.title == "A" }?.state == .on)
        #expect(menu.items.first { $0.title == "B" }?.state == .off)

        try choose("A", in: menu, of: controller)
        #expect(recorder.saved.isEmpty)
        #expect(recorder.hides.last == [])
    }

    @Test
    func `the toggle shows the hidden apps without forgetting them, then hides them again`() throws {
        let recorder = Recorder()
        recorder.saved = ["com.example.b"]
        let (controller, menu) = makeController(recorder)

        try choose("Show Hidden Apps", in: menu, of: controller)
        #expect(recorder.hides.last == [])
        #expect(recorder.saved == ["com.example.b"])

        try choose("Hide Chosen Apps", in: menu, of: controller)
        #expect(recorder.hides.last == ["com.example.b"])
    }

    @Test
    func `a URL can hide an app, show it and toggle, the same as the menu`() throws {
        let recorder = Recorder()
        let (controller, _) = makeController(recorder)

        try controller.handle(#require(URL(string: "thaw://hide-app?bundle=com.example.a")), senderIsApproved: true)
        #expect(recorder.saved == ["com.example.a"])
        #expect(recorder.hides.last == ["com.example.a"])

        try controller.handle(#require(URL(string: "thaw://toggle-hidden")), senderIsApproved: true)
        #expect(recorder.hides.last == [])
        #expect(recorder.saved == ["com.example.a"])

        try controller.handle(#require(URL(string: "thaw://show-app?bundle=com.example.a")), senderIsApproved: true)
        #expect(recorder.saved.isEmpty)

        let before = recorder.hides.count
        try controller.handle(#require(URL(string: "thaw://hide-app")), senderIsApproved: true)
        try controller.handle(#require(URL(string: "thaw://open-settings")), senderIsApproved: true)
        #expect(recorder.hides.count == before)
    }

    @Test
    func `only an approved sender can change which apps are saved as hidden`() throws {
        let recorder = Recorder()
        let (controller, _) = makeController(recorder)

        try controller.handle(#require(URL(string: "thaw://hide-app?bundle=com.example.a")), senderIsApproved: false)
        #expect(recorder.saved.isEmpty)
        #expect(recorder.hides.isEmpty)

        try controller.handle(#require(URL(string: "thaw://hide-app?bundle=com.example.a")), senderIsApproved: true)
        try controller.handle(#require(URL(string: "thaw://show-app?bundle=com.example.a")), senderIsApproved: false)
        #expect(recorder.saved == ["com.example.a"])

        // Showing and hiding the saved set changes nothing that is saved, so anyone may ask.
        try controller.handle(#require(URL(string: "thaw://toggle-hidden")), senderIsApproved: false)
        #expect(recorder.hides.last == [])
        #expect(recorder.saved == ["com.example.a"])
    }

    @Test
    func `a click shows the hidden apps and the next hides them, and a right click asks for the menu`() {
        let recorder = Recorder()
        recorder.saved = ["com.example.a"]
        let (controller, _) = makeController(recorder)

        #expect(controller.clicked(secondary: false) == .toggled)
        #expect(recorder.hides.last == [])
        #expect(controller.clicked(secondary: false) == .toggled)
        #expect(recorder.hides.last == ["com.example.a"])

        let before = recorder.hides.count
        #expect(controller.clicked(secondary: true) == .openMenu)
        #expect(recorder.hides.count == before)
    }

    @Test
    func `a click opens the menu while no app is chosen`() {
        let recorder = Recorder()
        let (controller, _) = makeController(recorder)
        #expect(controller.clicked(secondary: false) == .openMenu)
        #expect(recorder.hides.isEmpty)
    }

    @Test
    func `the toggle is off while no app is chosen`() {
        let recorder = Recorder()
        let (controller, menu) = makeController(recorder)
        controller.menuNeedsUpdate(menu)
        #expect(menu.items.first?.isEnabled == false)
    }

    @Test
    func `the menu says so and lists no apps when hiding is not available`() {
        let recorder = Recorder()
        recorder.available = false
        let (controller, menu) = makeController(recorder)
        controller.menuNeedsUpdate(menu)
        #expect(menu.items.contains { $0.title == "A" } == false)
        #expect(menu.items.first?.isEnabled == false)
    }
}

/// The reduced mode's menu with nothing to offer, its read-only request and its stored choice.
@MainActor
@Suite("Reduced mode controller edges", .scratchDefaults)
struct ReducedModeControllerEdgeTests {
    private final class Recorder {
        var hides: [Set<String>] = []
        var saves: [Set<String>] = []
    }

    private func makeController(_ recorder: Recorder, apps: [ReducedModeApp]) -> ReducedModeController {
        ReducedModeController(environment: .init(
            hidingIsAvailable: { true },
            hide: { recorder.hides.append($0) },
            apps: { apps },
            loadHidden: { ["com.example.a"] },
            saveHidden: { recorder.saves.append($0) }
        ))
    }

    @Test("With no apps to offer, the menu says so in a row that can't be chosen")
    func emptyAppListIsNamed() throws {
        let controller = makeController(Recorder(), apps: [])
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        let row = try #require(menu.items.first { $0.title == String(localized: "No apps found") })
        #expect(!row.isEnabled)
    }

    @Test("Listing the apps on offer hides, shows and saves nothing, even for a sender that isn't approved")
    func listingChangesNothing() throws {
        let recorder = Recorder()
        let controller = makeController(recorder, apps: [ReducedModeApp(bundleID: "com.example.a", name: "A")])

        try controller.handle(#require(URL(string: "thaw://list-apps")), senderIsApproved: false)

        #expect(recorder.hides.isEmpty)
        #expect(recorder.saves.isEmpty)
    }

    @Test("Choosing to run without Accessibility is kept in settings")
    func choiceIsStored() {
        #expect(!ReducedModeController.isChosen)
        ReducedModeController.isChosen = true
        #expect(Defaults.bool(forKey: .reducedModeChosen))
        #expect(ReducedModeController.isChosen)
    }
}
