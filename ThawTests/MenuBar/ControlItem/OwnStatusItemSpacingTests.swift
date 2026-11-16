//
//  OwnStatusItemSpacingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Spacing of Thaw's own status items")
@MainActor
struct OwnStatusItemSpacingTests {
    private func icon(width: CGFloat = 17, isTemplate: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 17), flipped: false) { bounds in
            NSColor.black.setFill()
            bounds.fill()
            return true
        }
        image.isTemplate = isTemplate
        image.accessibilityDescription = "Icon"
        return image
    }

    @Test("A padded image is wider by the padding and keeps its height, template flag and description")
    func paddedImageIsWider() throws {
        let image = icon()
        let padded = try #require(OwnStatusItemSpacing.padded(image, by: 16))
        #expect(padded.size == NSSize(width: 33, height: 17))
        #expect(padded.isTemplate)
        #expect(padded.accessibilityDescription == "Icon")
        #expect(OwnStatusItemSpacing.padded(icon(isTemplate: false), by: 16)?.isTemplate == false)
    }

    @Test("The padding is clear on both sides and the image sits in the middle")
    func marginsAreClear() throws {
        let padded = try #require(OwnStatusItemSpacing.padded(icon(width: 10), by: 10))
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 17, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        padded.draw(in: NSRect(x: 0, y: 0, width: 20, height: 17))
        NSGraphicsContext.restoreGraphicsState()
        #expect(bitmap.colorAt(x: 2, y: 8)?.alphaComponent == 0)
        #expect(bitmap.colorAt(x: 17, y: 8)?.alphaComponent == 0)
        #expect(bitmap.colorAt(x: 10, y: 8)?.alphaComponent == 1)
    }

    @Test("The same image and padding give the same padded image, and a new padding a new one")
    func paddedImageIsReused() {
        let image = icon()
        let first = OwnStatusItemSpacing.padded(image, by: 16)
        #expect(OwnStatusItemSpacing.padded(image, by: 16) === first)
        #expect(OwnStatusItemSpacing.padded(image, by: 12) !== first)
    }

    @Test("No padding, or no image, leaves the image as it is")
    func nothingToPad() {
        let image = icon()
        #expect(OwnStatusItemSpacing.padded(image, by: 0) === image)
        #expect(OwnStatusItemSpacing.padded(nil, by: 16) == nil)
    }

    @Test("The launch arguments get the spacing at zero and keep what they held")
    func argumentsGetNoSpacing() {
        let arguments = OwnStatusItemSpacing.withNoSpacing(["Kept": true, OwnStatusItemSpacing.spacingKey: 12])
        #expect(arguments[OwnStatusItemSpacing.spacingKey] as? Int == 0)
        #expect(arguments["Kept"] as? Bool == true)
    }

    @Test("The padding is the user's spacing, the default when it was never set, and nothing while macOS adds it")
    func paddingFollowsTheSystemSpacing() {
        #expect(OwnStatusItemSpacing.padding(isInstalled: true, systemSpacing: 12) == 12)
        #expect(OwnStatusItemSpacing.padding(isInstalled: true, systemSpacing: nil) == 16)
        #expect(OwnStatusItemSpacing.padding(isInstalled: false, systemSpacing: 12) == 0)
        #expect(OwnStatusItemSpacing.padded(length: 20, by: 12) == 32)
    }

    @Test("A collapsed divider keeps one point once macOS adds no spacing, and none before")
    func collapsedDividerLength() {
        #expect(OwnStatusItemSpacing.collapsedDividerLength(isInstalled: true) == 1)
        #expect(OwnStatusItemSpacing.collapsedDividerLength(isInstalled: false) == 0)
    }
}
