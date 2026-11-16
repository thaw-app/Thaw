//
//  MenuBarOverlayContentRasterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
struct MenuBarOverlayContentRasterTests {
    /// Fills the left half red and leaves the right half clear.
    private final class HalfRedView: NSView {
        private(set) var drawCount = 0

        override func draw(_: NSRect) {
            drawCount += 1
            NSColor.red.setFill()
            NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height).fill()
        }
    }

    private func alpha(of image: CGImage, atFraction fraction: CGFloat) -> CGFloat? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let x = Int(CGFloat(bitmap.pixelsWide) * fraction)
        return bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.alphaComponent
    }

    @Test
    func `the bitmap holds what draw painted and nothing else`() throws {
        let view = HalfRedView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))

        let image = try #require(view.bitmapOfOwnDrawing())

        #expect(view.drawCount == 1)
        #expect(image.width >= 80)
        #expect(image.height >= 20)
        #expect(alpha(of: image, atFraction: 0.25) == 1)
        #expect(alpha(of: image, atFraction: 0.75) == 0)
    }

    @Test
    func `a view with no area gives no bitmap and is not drawn`() {
        let view = HalfRedView(frame: .zero)

        #expect(view.bitmapOfOwnDrawing() == nil)
        #expect(view.drawCount == 0)
    }

    @Test
    func `the layer shows the bitmap at the bitmap's own scale`() throws {
        let view = HalfRedView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        view.wantsLayer = true

        view.showBitmapOfOwnDrawing()

        let layer = try #require(view.layer)
        let contents = try #require(layer.contents)
        #expect(CFGetTypeID(contents as CFTypeRef) == CGImage.typeID)
        #expect(layer.contentsScale >= 1)
        #expect(view.drawCount == 1)
    }

    @Test
    func `a view without a layer is left alone`() {
        let view = HalfRedView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))

        view.showBitmapOfOwnDrawing()

        #expect(view.drawCount == 0)
    }
}

@MainActor
struct WallpaperPaletteGradientTests {
    private func swatch(_ red: Double, weight: Double) -> WallpaperPalette.Swatch {
        WallpaperPalette.Swatch(red: red, green: 0.2, blue: 0.4, weight: weight)
    }

    @Test
    func `a palette with swatches gives a gradient at the asked opacity`() throws {
        let palette = WallpaperPalette(swatches: [swatch(1, weight: 0.7), swatch(0, weight: 0.3)])

        let gradient = try #require(palette.gradient(opacity: 0.5))

        #expect(gradient.numberOfColorStops == 2)
        #expect(abs(gradient.interpolatedColor(atLocation: 0).alphaComponent - 0.5) < 0.01)
    }

    @Test
    func `an empty palette gives no gradient`() {
        #expect(WallpaperPalette(swatches: []).gradient(opacity: 1) == nil)
    }
}
