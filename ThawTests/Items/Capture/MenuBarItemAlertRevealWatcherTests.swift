//
//  MenuBarItemAlertRevealWatcherTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("An opted-in hidden item is revealed when its icon changes", .scratchDefaults)
struct MenuBarItemAlertRevealWatcherTests {
    private let tagA = MenuBarItemTag(namespace: .string("com.example.alert"), title: "A", instanceIndex: 0)
    private let tagB = MenuBarItemTag(namespace: .string("com.example.alert"), title: "B", instanceIndex: 0)
    private let start = ContinuousClock.now

    private static func glyph(red: CGFloat) -> MenuBarItemGlyphCapture {
        let context = CGContext(
            data: nil, width: 6, height: 6, bitsPerComponent: 8, bytesPerRow: 24,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 6, height: 6))
        return MenuBarItemGlyphCapture(cgImage: context.makeImage()!, scale: 1)
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
        #expect(controller.temporaryReveals.isEmpty, "the same pixels in a new image are no change")

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
