//
//  RevealCapturePrewarmTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Reveal capture prewarm", .timeLimit(.minutes(1)))
struct RevealCapturePrewarmTests {
    /// The bar and the cache a prewarm reads, and everything it did.
    @MainActor
    private final class World {
        var sections: [MenuBarSection.Name: [MenuBarItem]] = [:]
        var appIsGone = false
        var locked: Set<String> = []
        var mayReveal = true
        var nativeOverflow = false
        var allowsCaptureReveal = false
        var images: [MenuBarItemTag: MenuBarItemGlyphCapture] = [:]
        var blacklisted: Set<MenuBarItemTag> = []
        var displayID: CGDirectDisplayID = 42
        var newPictures: Set<MenuBarItemTag> = []

        var forgotten: [Set<MenuBarItemTag>] = []
        var captured: [(items: [MenuBarItemTag], displayID: CGDirectDisplayID)] = []
        var saves = 0
        let slot = RevealCaptureSlot()

        func prewarm() -> RevealCapturePrewarm {
            RevealCapturePrewarm(
                slot: slot,
                isLocked: { self.locked.contains($0) },
                mayReveal: { self.mayReveal },
                sectionItems: { self.appIsGone ? nil : self.sections[$0] ?? [] },
                displayID: { self.displayID },
                isNativeOverflowActive: { _ in self.nativeOverflow },
                allowsCaptureReveal: { self.allowsCaptureReveal },
                cachedImage: { self.images[$0] },
                wouldAttemptCapture: { !self.blacklisted.contains($0.tag) },
                forgetFailures: { self.forgotten.append($0) },
                captureSection: { items, displayID in
                    self.captured.append((items.map(\.tag), displayID))
                    for item in items where self.newPictures.contains(item.tag) {
                        self.slot.tally?.tags.insert(item.tag)
                    }
                },
                save: { self.saves += 1 }
            )
        }

        func run(_ sections: [MenuBarSection.Name], onlyMissingImages: Bool = true, tally: RequestedCaptureTally? = nil) async {
            await prewarm().capture(sections: sections, onlyMissingImages: onlyMissingImages, tally: tally)
        }
    }

    private static func item(_ title: String, namespace: MenuBarItemTag.Namespace = .string("com.example.prewarm"), width: CGFloat = 24) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, windowID: 9, instanceIndex: 0),
            windowID: 9,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 900, y: 4, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// Solid ink, pixelWidth wide at scale 2.
    private static func glyph(pixelWidth: Int) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: pixelWidth, height: 48, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: 48))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }

    @Test("The visible section and repeats are dropped, in request order")
    func prewarmSections() {
        #expect(RevealCapturePrewarm.prewarmSections([.alwaysHidden, .visible, .hidden, .alwaysHidden]) == [.alwaysHidden, .hidden])
    }

    @Test("Control Center modules are always left out, blank items only outside a requested Native capture")
    func skips() {
        let module = Self.item("com.apple.menuextra.wifi", namespace: .menuBarAgent)
        let blank = Self.item("Blank", width: 2)
        let normal = Self.item("Normal")
        #expect(RevealCapturePrewarm.skips(module, allowsCaptureReveal: false))
        #expect(RevealCapturePrewarm.skips(module, allowsCaptureReveal: true))
        #expect(RevealCapturePrewarm.skips(blank, allowsCaptureReveal: false))
        #expect(!RevealCapturePrewarm.skips(blank, allowsCaptureReveal: true))
        #expect(!RevealCapturePrewarm.skips(normal, allowsCaptureReveal: false))
    }

    @Test("A missing-only prewarm reveals the items without a trusted picture, leaving out blank ones")
    func missingOnlyFilter() async throws {
        let world = World()
        let good = Self.item("Good"), narrow = Self.item("Narrow"), none = Self.item("None")
        let blank = Self.item("Blank", width: 2), failing = Self.item("Failing")
        world.sections[.hidden] = [good, narrow, none, blank, failing]
        world.images[good.tag] = try Self.glyph(pixelWidth: 40)
        world.images[narrow.tag] = try Self.glyph(pixelWidth: 4)
        world.blacklisted = [failing.tag]

        await world.run([.hidden])

        #expect(world.captured.map(\.items) == [[narrow.tag, none.tag]])
        #expect(world.captured.map(\.displayID) == [42])
        #expect(world.forgotten.isEmpty, "An automatic pass keeps its failures")
        #expect(world.saves == 1)
        #expect(!world.slot.isHeld)
    }

    @Test("A blank item is revealed while Capture Hidden Items runs under Native hiding")
    func blankItemUnderNativeCapture() async {
        let world = World()
        let blank = Self.item("Blank", width: 2)
        world.sections[.hidden] = [blank]
        world.allowsCaptureReveal = true

        await world.run([.hidden])

        #expect(world.captured.map(\.items) == [[blank.tag]])
    }

    @Test("A retake reveals every item that is not skipped and forgets the sections' failures first")
    func retakeForgetsFailures() async throws {
        let world = World()
        let good = Self.item("Good"), always = Self.item("Always")
        world.sections[.hidden] = [good]
        world.sections[.alwaysHidden] = [always]
        world.images[good.tag] = try Self.glyph(pixelWidth: 40)

        await world.run([.hidden, .alwaysHidden], onlyMissingImages: false)

        #expect(world.forgotten == [[good.tag, always.tag]])
        #expect(world.captured.map(\.items) == [[good.tag], [always.tag]])
    }

    @Test("Native overflow on the display leaves the section out")
    func nativeOverflowSkipsTheSection() async {
        let world = World()
        world.sections[.hidden] = [Self.item("Overflowed")]
        world.nativeOverflow = true

        await world.run([.hidden])

        #expect(world.captured.isEmpty)
        #expect(world.saves == 1)
    }

    @Test("A locked screen or a closed gate ends the prewarm before it takes the slot or saves", arguments: [0, 1])
    func refusedBeforeTheSlot(reason: Int) async {
        let world = World()
        world.sections[.hidden] = [Self.item("Hidden")]
        if reason == 0 {
            world.locked = ["prewarmConcealedImages"]
        } else {
            world.mayReveal = false
        }

        await world.run([.hidden], onlyMissingImages: false)

        #expect(world.captured.isEmpty)
        #expect(world.forgotten.isEmpty)
        #expect(world.saves == 0)
    }

    @Test("A screen locked while the prewarm waited its turn ends it without saving, and frees the slot")
    func lockedAfterTheWait() async {
        let world = World()
        world.sections[.hidden] = [Self.item("Hidden")]
        world.locked = ["queued prewarm"]

        await world.run([.hidden])

        #expect(world.captured.isEmpty)
        #expect(world.saves == 0)
        #expect(!world.slot.isHeld)
    }

    @Test("An app that went away stops the walk, and the pass still saves")
    func appGoneStopsTheWalk() async {
        let world = World()
        world.sections[.hidden] = [Self.item("Hidden")]
        world.appIsGone = true

        await world.run([.hidden], onlyMissingImages: false)

        #expect(world.forgotten.isEmpty)
        #expect(world.captured.isEmpty)
        #expect(world.saves == 1)
    }

    @Test("A cancelled prewarm reveals nothing")
    func cancelledBeforeStart() async {
        let world = World()
        world.sections[.hidden] = [Self.item("Hidden")]
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await world.run([.hidden])
        }
        await task.value

        #expect(world.captured.isEmpty)
    }

    @Test("Capture Hidden Items counts new pictures and kept ones, and tries only weak ones unless retaking all", arguments: [false, true])
    func captureHiddenItems(retakingAll: Bool) async throws {
        let world = World()
        let good = Self.item("Good"), weak = Self.item("Weak"), module = Self.item("com.apple.menuextra.wifi", namespace: .menuBarAgent)
        world.sections[.hidden] = [good, weak, module]
        world.images[good.tag] = try Self.glyph(pixelWidth: 40)
        world.newPictures = [weak.tag]

        let result = await world.prewarm().captureHiddenItems(retakingAll: retakingAll)

        #expect(world.captured.map(\.items) == [retakingAll ? [good.tag, weak.tag] : [weak.tag]])
        if retakingAll {
            #expect(result == HiddenItemCaptureResult(captured: 1, total: 2, missing: [good.displayName]))
        } else {
            #expect(result == HiddenItemCaptureResult(captured: 1, total: 1, missing: [], kept: 1))
        }
    }

    @Test("Capture Hidden Items reports nothing when no capture can run")
    func captureHiddenItemsRefused() async {
        let world = World()
        world.mayReveal = false
        #expect(await world.prewarm().captureHiddenItems(retakingAll: false) == nil)
        #expect(world.captured.isEmpty)
    }
}
