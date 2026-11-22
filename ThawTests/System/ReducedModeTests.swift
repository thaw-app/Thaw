//
//  ReducedModeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
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

@MainActor
@Suite("Reduced mode choice", .serialized, .scratchDefaults)
struct ReducedModeChoiceTests {
    @Test("Choosing it from Troubleshooting keeps it with Accessibility granted")
    func troubleshootingChoiceIsKept() {
        ReducedModeController.choose(keepingWithAccessibility: true)
        #expect(ReducedModeController.isChosen)
        #expect(ReducedModeController.isKeptWithAccessibility)
    }

    @Test("Onboarding's choice still gives way to the full app once access is granted")
    func onboardingChoiceGivesWay() {
        ReducedModeController.isChosen = true
        #expect(!ReducedModeController.isKeptWithAccessibility)
    }

    @Test("Switching to the full app clears both, however it was chosen")
    func leavingClearsBoth() {
        ReducedModeController.choose(keepingWithAccessibility: true)
        ReducedModeController.leave()
        #expect(!ReducedModeController.isChosen)
        #expect(!ReducedModeController.isKeptWithAccessibility)
    }
}

@MainActor
struct ReducedModeURLCommandTests {
    private func command(_ string: String) throws -> ReducedModeURLCommand? {
        try ReducedModeURLCommand(#require(URL(string: string)))
    }

    @Test
    func `reads each request the reduced mode answers`() throws {
        #expect(try command("thaw://toggle-hidden") == .toggleHidden)
        #expect(try command("thaw://list-apps") == .listApps)
        #expect(try command("thaw://hide-app?bundle=com.example.a") == .hideApp("com.example.a"))
        #expect(try command("thaw://show-app?bundle=com.example.a") == .showApp("com.example.a"))
    }

    @Test
    func `ignores the case of the request's name`() throws {
        #expect(try command("thaw://Toggle-Hidden") == .toggleHidden)
    }

    @Test
    func `refuses a hide or show that names no app`() throws {
        #expect(try command("thaw://hide-app") == nil)
        #expect(try command("thaw://show-app?bundle=") == nil)
        #expect(try command("thaw://hide-app?app=com.example.a") == nil)
    }

    @Test
    func `refuses the full app's requests`() throws {
        for request in ["open-settings", "set?key=showOnHover&value=true", "toggle-thawbar", "search", "dump-items"] {
            #expect(try command("thaw://\(request)") == nil)
        }
    }
}

@MainActor
struct ReducedModeInventoryTests {
    private func app(_ bundleID: String?, _ name: String? = nil, background: Bool = false) -> ReducedModeInventory.Running {
        .init(bundleID: bundleID, name: name, isBackgroundOnly: background)
    }

    @Test
    func `lists other developers' apps by name and leaves out Thaw, Apple and background processes`() {
        let apps = ReducedModeInventory.candidates(
            running: [
                app("com.example.zeta", "Zeta"),
                app("com.apple.Safari", "Safari"),
                app("com.stonerl.Thaw", "Thaw"),
                app("com.example.daemon", "Daemon", background: true),
                app(nil, "Nameless"),
                app("com.example.alpha", "alpha"),
            ],
            tableKeys: nil,
            isOwn: { $0 == "com.stonerl.Thaw" }
        )
        #expect(apps.map(\.bundleID) == ["com.example.alpha", "com.example.zeta"])
    }

    @Test
    func `keeps only apps with a row in the position table when the table can be read`() {
        let apps = ReducedModeInventory.candidates(
            running: [app("com.example.withitem", "With"), app("com.example.noitem", "Without")],
            tableKeys: ["status:com.example.withitem::Item-0", "module:Clock"],
            isOwn: { _ in false }
        )
        #expect(apps.map(\.bundleID) == ["com.example.withitem"])
    }

    @Test
    func `lists an app once when it runs twice, under whichever name it has`() {
        let apps = ReducedModeInventory.candidates(
            running: [app("com.example.twice", nil), app("com.example.twice", "Twice"), app("com.example.bare", nil)],
            tableKeys: nil,
            isOwn: { _ in false }
        )
        #expect(apps == [
            ReducedModeApp(bundleID: "com.example.bare", name: "com.example.bare"),
            ReducedModeApp(bundleID: "com.example.twice", name: "Twice"),
        ])
    }

    @Test
    func `maps each hidden app to an identifier the kit can conceal`() {
        let input = ReducedModeHider.input(hiding: ["com.example.b", "com.example.a"])
        #expect(input.assignment == ["reduced:com.example.a": .hidden, "reduced:com.example.b": .hidden])
        #expect(input.owners == ["reduced:com.example.a": "com.example.a", "reduced:com.example.b": "com.example.b"])
    }
}
