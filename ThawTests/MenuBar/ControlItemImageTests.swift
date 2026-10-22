//
//  ControlItemImageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The Thaw icon and section divider images, drawn into a bitmap and measured.
@Suite("Control item images", .serialized, .scratchDefaults)
@MainActor
struct ControlItemImageTests {
    /// A PNG of the given size, filled opaque red.
    private func png(width: Int, height: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.red.setFill()
        CGRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    /// The share of the image's pixels that it draws on, from 0 to 1.
    private func inkCoverage(of image: NSImage) throws -> Double {
        let width = max(1, Int(image.size.width * 2))
        let height = max(1, Int(image.size.height * 2))
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        var inked = 0
        for x in 0 ..< width {
            for y in 0 ..< height where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                inked += 1
            }
        }
        return Double(inked) / Double(width * height)
    }

    @Test("Each built-in mark draws a template image at its own size", arguments: [
        (ControlItemImage.ImageBuiltinName.chevronLarge, CGSize(width: 12, height: 12)),
        (.chevronSmall, CGSize(width: 9, height: 9)),
        (.dividerLine, CGSize(width: 4, height: 14)),
        (.dividerDot, CGSize(width: 9, height: 9)),
        (.dividerSlash, CGSize(width: 8, height: 12)),
    ])
    func builtinMarks(name: ControlItemImage.ImageBuiltinName, size: CGSize) throws {
        let image = try #require(ControlItemImage.builtin(name).nsImage(for: AppState()))
        #expect(image.size == size)
        #expect(image.isTemplate)
        let coverage = try inkCoverage(of: image)
        #expect(coverage > 0, "\(name) draws something")
        #expect(coverage < 0.9, "\(name) is a mark, not a filled box")
    }

    @Test("The dot is rounder than the line is wide, and the line is taller than the dot")
    func marksDiffer() throws {
        let appState = AppState()
        let line = try #require(ControlItemImage.builtin(.dividerLine).nsImage(for: appState))
        let dot = try #require(ControlItemImage.builtin(.dividerDot).nsImage(for: appState))
        let slash = try #require(ControlItemImage.builtin(.dividerSlash).nsImage(for: appState))
        #expect(line.size.height > dot.size.height)
        #expect(Set([line.size, dot.size, slash.size]).count == 3)
    }

    @Test("A system symbol is a template, and an unknown one resolves to nothing")
    func symbols() throws {
        let appState = AppState()
        let symbol = try #require(ControlItemImage.symbol("star").nsImage(for: appState))
        #expect(symbol.isTemplate)
        #expect(ControlItemImage.symbol("no.such.symbol.anywhere").nsImage(for: appState) == nil)
    }

    @Test("Catalog art is brought down to fit the menu bar")
    func catalogArt() throws {
        let image = try #require(ControlItemImage.catalog("IceCubeFill").nsImage(for: AppState()))
        #expect(image.size.width <= ControlItemImage.maximumSize.width + 0.5)
        #expect(image.size.height <= ControlItemImage.maximumSize.height + 0.5)
        #expect(ControlItemImage.catalog("NoSuchCatalogImage").nsImage(for: AppState()) == nil)
    }

    @Test("A custom icon is tinted only when it is marked as a template")
    func customIconTemplate() throws {
        let appState = AppState()
        let data = try png(width: 20, height: 16)
        appState.settings.general.customThawIconIsTemplate = false
        #expect(try #require(ControlItemImage.data(data).nsImage(for: appState)).isTemplate == false)
        appState.settings.general.customThawIconIsTemplate = true
        #expect(try #require(ControlItemImage.data(data).nsImage(for: appState)).isTemplate)
        #expect(ControlItemImage.data(Data("not an image".utf8)).nsImage(for: appState) == nil)
    }

    @Test("A custom divider is fitted to the menu bar and keeps its template choice")
    func customDivider() throws {
        let data = try png(width: 50, height: 20)
        let template = try #require(ControlItemImage.dividerImage(for: SectionDividerCustomMark(data: data, isTemplate: true)))
        #expect(template.isTemplate)
        #expect(abs(template.size.width - ControlItemImage.maximumSize.width) < 0.5, "the wide side reaches the limit")
        #expect(abs(template.size.height - 10) < 0.5, "the shape is kept")
        let colored = try #require(ControlItemImage.dividerImage(for: SectionDividerCustomMark(data: data, isTemplate: false)))
        #expect(!colored.isTemplate)
        #expect(try inkCoverage(of: colored) > 0.9, "a photo-like image keeps its pixels")
    }

    @Test("A custom divider whose data isn't an image draws nothing")
    func undecodableDivider() {
        #expect(ControlItemImage.dividerImage(for: SectionDividerCustomMark(data: Data([1, 2, 3]), isTemplate: true)) == nil)
    }

    @Test("A tall image is fitted by its height")
    func tallImage() throws {
        let image = try #require(NSImage(data: png(width: 10, height: 34)))
        let fitted = try #require(ControlItemImage.scaledToFitMenuBar(image))
        #expect(abs(fitted.size.height - ControlItemImage.maximumSize.height) < 0.5)
        #expect(abs(fitted.size.width - 5) < 0.5)
    }
}
