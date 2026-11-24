//
//  ImagePNGTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Images encoded as PNG")
struct ImagePNGTests {
    @Test("A CGImage's PNG data decodes to the same pixels")
    func cgImageRoundTrips() throws {
        let image = try ItemsFixture.image(width: 12, height: 7)
        let png = try #require(image.pngData())
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.pixelsWide == 12)
        #expect(decoded.pixelsHigh == 7)
    }

    @Test("Writing a PNG reports whether the file was finished")
    func writeReportsTheResult() throws {
        let image = try ItemsFixture.image(width: 4, height: 4)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("image.png")
        #expect(image.writePNG(to: url))
        #expect(NSBitmapImageRep(data: try Data(contentsOf: url))?.pixelsWide == 4)
        #expect(!image.writePNG(to: folder.appendingPathComponent("missing/image.png")))
    }

    @Test("A point size records the pixel density, and without one a point is a pixel", arguments: [
        (NSSize(width: 10, height: 5), NSSize(width: 10, height: 5)),
        (nil, NSSize(width: 30, height: 15)),
    ] as [(NSSize?, NSSize)])
    func nsImageKeepsItsDensity(pointSize: NSSize?, decodedSize: NSSize) throws {
        let image = NSImage(size: NSSize(width: 10, height: 5), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        let png = try #require(image.pngData(pixelsWide: 30, pixelsHigh: 15, pointSize: pointSize))
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.pixelsWide == 30)
        #expect(decoded.size == decodedSize)
    }
}
