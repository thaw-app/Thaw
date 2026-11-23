//
//  MenuBarItemAlertRevealsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("The alert reveal opt-ins are stored by tag identifier", .scratchDefaults)
struct MenuBarItemAlertRevealsTests {
    @Test("Nothing is opted in by default")
    func emptyByDefault() {
        #expect(MenuBarItemAlertReveals.identifiers().isEmpty)
        #expect(!MenuBarItemAlertReveals.contains("com.example.app:Item"))
    }

    @Test("Enabling stores the identifier sorted, and disabling removes it")
    func enableAndDisable() {
        MenuBarItemAlertReveals.setEnabled(true, for: "b:B")
        MenuBarItemAlertReveals.setEnabled(true, for: "a:A")
        MenuBarItemAlertReveals.setEnabled(true, for: "a:A")

        #expect(MenuBarItemAlertReveals.identifiers() == ["a:A", "b:B"])
        #expect(Defaults.stringArray(forKey: .menuBarItemAlertReveals) == ["a:A", "b:B"])
        #expect(MenuBarItemAlertReveals.contains("b:B"))

        MenuBarItemAlertReveals.setEnabled(false, for: "b:B")

        #expect(MenuBarItemAlertReveals.identifiers() == ["a:A"])
        #expect(!MenuBarItemAlertReveals.contains("b:B"))
    }
}

@Suite("An icon change reveals its item at most once per cooldown")
struct AlertRevealPolicyTests {
    private let start = ContinuousClock.now

    @Test("A second change inside the cooldown does not reveal again")
    func holdsInsideCooldown() {
        var policy = AlertRevealPolicy()
        let first = policy.shouldReveal("a", now: start)
        let early = policy.shouldReveal("a", now: start + policy.cooldown - .milliseconds(1))
        #expect(first)
        #expect(!early)
        #expect(policy.lastReveals["a"] == start)
    }

    @Test("A change once the cooldown has passed reveals again")
    func revealsAfterCooldown() {
        var policy = AlertRevealPolicy()
        let first = policy.shouldReveal("a", now: start)
        let later = policy.shouldReveal("a", now: start + policy.cooldown)
        #expect(first)
        #expect(later)
        #expect(policy.lastReveals["a"] == start + policy.cooldown)
    }

    @Test("Each item has its own cooldown")
    func cooldownIsPerItem() {
        var policy = AlertRevealPolicy()
        let first = policy.shouldReveal("a", now: start)
        let other = policy.shouldReveal("b", now: start)
        #expect(first)
        #expect(other)
    }
}

@MainActor
@Suite("An opted-in hidden item is revealed when its icon changes", .scratchDefaults)
struct MenuBarItemAlertRevealWatcherTests {
    private let tagA = MenuBarItemTag(namespace: .string("com.example.alert"), title: "A", instanceIndex: 0)
    private let tagB = MenuBarItemTag(namespace: .string("com.example.alert"), title: "B", instanceIndex: 0)
    private let start = ContinuousClock.now

    private static func glyph(red: CGFloat) -> MenuBarItemGlyphCapture {
        try! ItemsFixture.glyph(width: 6, height: 6, color: CGColor(red: red, green: 0, blue: 0, alpha: 1))
    }

    private func controller(_ assignment: [MenuBarItemTag: MenuBarSectionName]) -> RecordingSectionController {
        let controller = RecordingSectionController()
        controller.sectionAssignment = Dictionary(uniqueKeysWithValues: assignment.map { ($0.key.tagIdentifier, $0.value) })
        return controller
    }

    @Test("The first sighting only sets the baseline, and a changed icon reveals the item and schedules its conceal")
    func changeReveals() {
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        let controller = controller([tagA: .hidden])
        let watcher = MenuBarItemAlertRevealWatcher()

        watcher.process([tagA: Self.glyph(red: 1)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty)
        watcher.process([tagA: Self.glyph(red: 1)], sectionController: controller, now: start)
        // The same pixels in a new image are no change.
        #expect(controller.temporaryReveals.isEmpty)

        watcher.process([tagA: Self.glyph(red: 0.2)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals == [tagA.tagIdentifier])
        #expect(controller.scheduledConceals == [tagA.tagIdentifier])
    }

    @Test("A visible, unassigned or not opted-in item is never revealed")
    func onlyConcealedOptedInItems() {
        let tagC = MenuBarItemTag(namespace: .string("com.example.alert"), title: "C", instanceIndex: 0)
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        MenuBarItemAlertReveals.setEnabled(true, for: tagB.tagIdentifier)
        let controller = controller([tagA: .visible, tagC: .hidden])
        let watcher = MenuBarItemAlertRevealWatcher()

        watcher.process([tagA: Self.glyph(red: 1), tagB: Self.glyph(red: 1), tagC: Self.glyph(red: 1)], sectionController: controller, now: start)
        watcher.process([tagA: Self.glyph(red: 0), tagB: Self.glyph(red: 0), tagC: Self.glyph(red: 0)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty)
    }

    @Test("A second change inside the cooldown does not reveal again, one after it does")
    func cooldown() {
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        let controller = controller([tagA: .alwaysHidden])
        let watcher = MenuBarItemAlertRevealWatcher()

        watcher.process([tagA: Self.glyph(red: 1)], sectionController: controller, now: start)
        watcher.process([tagA: Self.glyph(red: 0)], sectionController: controller, now: start)
        watcher.process([tagA: Self.glyph(red: 1)], sectionController: controller, now: start + .seconds(10))
        #expect(controller.temporaryReveals.count == 1)
        watcher.process([tagA: Self.glyph(red: 0)], sectionController: controller, now: start + .seconds(46))
        #expect(controller.temporaryReveals.count == 2)
    }

    @Test("Turning every opt-in off forgets the baselines")
    func noOptInsForgetBaselines() {
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        let controller = controller([tagA: .hidden])
        let watcher = MenuBarItemAlertRevealWatcher()
        watcher.process([tagA: Self.glyph(red: 1)], sectionController: controller, now: start)

        MenuBarItemAlertReveals.setEnabled(false, for: tagA.tagIdentifier)
        watcher.process([tagA: Self.glyph(red: 0.5)], sectionController: controller, now: start)
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        watcher.process([tagA: Self.glyph(red: 0)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty)
    }

    @Test("An item opted out while others stay in loses its baseline")
    func optedOutItemLosesBaseline() {
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        MenuBarItemAlertReveals.setEnabled(true, for: tagB.tagIdentifier)
        let controller = controller([tagA: .hidden])
        let watcher = MenuBarItemAlertRevealWatcher()
        watcher.process([tagA: Self.glyph(red: 1)], sectionController: controller, now: start)

        MenuBarItemAlertReveals.setEnabled(false, for: tagA.tagIdentifier)
        watcher.process([:], sectionController: controller, now: start)
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        watcher.process([tagA: Self.glyph(red: 0)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty)
    }

    @Test("Without a section controller nothing is revealed or remembered")
    func noControllerDoesNothing() {
        MenuBarItemAlertReveals.setEnabled(true, for: tagA.tagIdentifier)
        let controller = controller([tagA: .hidden])
        let watcher = MenuBarItemAlertRevealWatcher()
        watcher.process([tagA: Self.glyph(red: 1)], sectionController: nil, now: start)
        watcher.process([tagA: Self.glyph(red: 0)], sectionController: controller, now: start)
        #expect(controller.temporaryReveals.isEmpty)
        #expect(watcher.appState == nil)
    }
}
