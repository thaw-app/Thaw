//
//  OpenedItemPhotographTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Pins one try at an opened item's picture: where it is cropped, and when it is kept. Moving the crop
/// to where MenuBarAgent draws the item is the cropper's job (AXBoundsCropper.Request.seatsOnDrawnBar).
@MainActor
@Suite("Opened item photograph", .timeLimit(.minutes(1)))
struct OpenedItemPhotographTests {
    private static let driveDx: pid_t = 1096
    private static let axFrame = CGRect(x: 926, y: 4.5, width: 20, height: 24)

    private static func item(bounds: CGRect = axFrame) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.binaryfruit.DriveDx"), title: "Item-0", windowID: 12, instanceIndex: 0),
            windowID: 12,
            ownerPID: driveDx,
            sourcePID: driveDx,
            bounds: bounds,
            title: "Item-0",
            isOnScreen: true
        )
    }

    private static func glyph() throws -> MenuBarItemGlyphCapture {
        try ItemsFixture.glyph(width: 40, height: 48, scale: 2, ink: CGRect(x: 8, y: 8, width: 24, height: 32), color: CGColor(gray: 0, alpha: 1))
    }

    /// The bar and the cache one try reads, and everything it did.
    @MainActor
    private final class World {
        var mayCapture = true
        var shown: MenuBarItem? = OpenedItemPhotographTests.item()
        /// Menu answers in order; the last one repeats.
        var menuOpen = [false]
        var picture: MenuBarItemGlyphCapture?
        var commits = true
        var displays: OpenedItemPhotograph.Displays = (42, 42)

        var holds = 0
        var releases = 0
        var settled: [CGDirectDisplayID] = []
        var admitted: [CGDirectDisplayID?] = []
        var crops: [(frame: CGRect, displayID: CGDirectDisplayID)] = []
        var committed = 0
        var saves = 0
        let slot = RevealCaptureSlot()

        func photograph() -> OpenedItemPhotograph {
            OpenedItemPhotograph(
                slot: slot,
                mayCapture: { self.mayCapture },
                holdCaptures: { self.holds += 1 },
                releaseCaptures: { self.releases += 1 },
                displays: { self.displays },
                shownItem: { item, _ in self.shown.map { (item, $0) } },
                settlePixels: { _, displayID in self.settled.append(displayID) },
                admit: { displayID in
                    self.admitted.append(displayID)
                    return CapturePublicationAdmission(layoutGeneration: 0, displayID: displayID)
                },
                crop: { item, frame, displayID in
                    self.crops.append((frame, displayID))
                    var pass = MenuBarItemImageCache.CapturePass()
                    pass.captured[item.tag] = self.picture
                    return pass
                },
                commit: { _, _, _ in
                    self.committed += 1
                    return self.commits
                },
                save: { self.saves += 1 }
            )
        }

        func take() async -> OpenedItemRecapture.Attempt {
            await photograph().take(OpenedItemPhotographTests.item()) {
                self.menuOpen.count > 1 ? self.menuOpen.removeFirst() : self.menuOpen.first ?? false
            }
        }
    }

    @Test("A shown item is cropped at the frame the bar shows it at, kept and saved")
    func storedAtTheShownFrame() async throws {
        let world = World()
        world.picture = try Self.glyph()
        world.displays = (7, nil)

        #expect(await world.take() == .stored)

        #expect(world.crops.map(\.frame) == [Self.axFrame])
        #expect(world.crops.map(\.displayID) == [7])
        #expect(world.settled == [7])
        #expect(world.admitted == [nil], "admitted against the item cache's display, read once for the try")
        #expect(world.committed == 1)
        #expect(world.saves == 1)
        #expect(world.holds == 1 && world.releases == 1)
        #expect(!world.slot.isHeld)
    }

    @Test("No Screen Recording or a locked screen takes no slot and holds nothing open")
    func refusedBeforeTheSlot() async {
        let world = World()
        world.mayCapture = false

        #expect(await world.take() == .missed)

        #expect(world.holds == 0)
        #expect(world.crops.isEmpty)
        #expect(!world.slot.isHeld)
    }

    @Test("An item no longer shown keeps its old picture")
    func notShown() async {
        let world = World()
        world.shown = nil

        #expect(await world.take() == .missed)

        #expect(world.settled.isEmpty)
        #expect(world.crops.isEmpty)
        #expect(world.releases == 1)
    }

    @Test("A menu open once the pixels settle, or opened during the crop, asks for another try without keeping anything")
    func menuOpenAsksForAnotherTry() async throws {
        let beforeCrop = World()
        beforeCrop.menuOpen = [true]
        #expect(await beforeCrop.take() == .menuOpened)
        #expect(beforeCrop.crops.isEmpty)

        let duringCrop = World()
        duringCrop.picture = try Self.glyph()
        duringCrop.menuOpen = [false, true]
        #expect(await duringCrop.take() == .menuOpened)
        #expect(duringCrop.crops.count == 1)
        #expect(duringCrop.committed == 0)
        #expect(duringCrop.saves == 0)
    }

    @Test("A crop that took no picture keeps the old one")
    func noPicture() async {
        let world = World()

        #expect(await world.take() == .missed)

        #expect(world.crops.count == 1)
        #expect(world.committed == 0)
    }

    @Test("A picture the bar's change kept from publishing isn't saved")
    func rejectedCommit() async throws {
        let world = World()
        world.picture = try Self.glyph()
        world.commits = false

        #expect(await world.take() == .missed)

        #expect(world.committed == 1)
        #expect(world.saves == 0)
        #expect(!world.slot.isHeld)
    }
}
