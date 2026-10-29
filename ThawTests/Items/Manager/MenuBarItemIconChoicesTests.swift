//
//  MenuBarItemIconChoicesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Picked item icons are stored as PNG and survive a relaunch")
struct MenuBarItemIconChoicesTests {
    private let suites = ScratchSuites(prefix: "MenuBarItemIconChoicesTests")

    private let item = MenuBarItem(
        tag: MenuBarItemTag(namespace: .string("com.example.icons"), title: "Item", instanceIndex: 0),
        windowID: 3,
        ownerPID: 999_974,
        sourcePID: 999_974,
        bounds: CGRect(x: 0, y: 0, width: 22, height: 24),
        title: "Item",
        isOnScreen: true
    )

    /// A 2x image with one filled square, so the PNG keeps its pixels.
    private func makeImage(isTemplate: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            rect.insetBy(dx: 3, dy: 3).fill()
            return true
        }
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        if let rep {
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
        }
        let result = NSImage(size: image.size)
        if let rep {
            result.addRepresentation(rep)
        }
        result.isTemplate = isTemplate
        return result
    }

    @Test("An item without a choice has no image")
    func noChoice() throws {
        let choices = try MenuBarItemIconChoices(defaults: #require(suites.make()))
        #expect(!choices.hasChoice(for: item))
        #expect(choices.image(for: item) == nil)
        #expect(choices.revision == 0)
    }

    @Test("A chosen image is kept with its template flag and reloads from the store")
    func choiceRoundTrip() throws {
        let defaults = try #require(suites.make())
        let choices = MenuBarItemIconChoices(defaults: defaults)

        choices.setImage(makeImage(isTemplate: true), for: item)

        #expect(choices.hasChoice(for: item))
        #expect(choices.revision == 1)
        let image = try #require(choices.image(for: item))
        #expect(image.isTemplate)
        #expect(image.representations.map(\.pixelsHigh).max() == 32)
        // The decoded image is cached for the next read.
        #expect(choices.image(for: item) === image)

        let reloaded = MenuBarItemIconChoices(defaults: defaults)
        #expect(reloaded.hasChoice(for: item))
        #expect(reloaded.image(for: item)?.isTemplate == true)
    }

    @Test("Clearing a choice removes it and bumps the revision")
    func clearChoice() throws {
        let defaults = try #require(suites.make())
        let choices = MenuBarItemIconChoices(defaults: defaults)
        choices.setImage(makeImage(isTemplate: false), for: item)

        choices.setImage(nil, for: item)

        #expect(!choices.hasChoice(for: item))
        #expect(choices.image(for: item) == nil)
        #expect(choices.revision == 2)
        #expect(!MenuBarItemIconChoices(defaults: defaults).hasChoice(for: item))
    }

    @Test("An unreadable store starts with no choices")
    func unreadableStore() throws {
        let defaults = try #require(suites.make())
        defaults.set(Data("garbage".utf8), forKey: "MenuBarItemManager.iconChoices")
        #expect(!MenuBarItemIconChoices(defaults: defaults).hasChoice(for: item))
    }
}
