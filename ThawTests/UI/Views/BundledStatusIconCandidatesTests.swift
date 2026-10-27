//
//  BundledStatusIconCandidatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Which images a fixture app bundle in a temporary folder offers as status icons.
@Suite("Bundled status icon candidates")
@MainActor
struct BundledStatusIconCandidatesTests {
    /// Writes a PNG of the given pixel size, filled with one colour, into folder.
    private static func writePNG(_ name: String, in folder: URL, width: Int, height: Int, color: NSColor) throws {
        let rep = try #require(NSBitmapImageRep(
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
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 2, y: 2, width: width - 4, height: height - 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: folder.appending(path: name))
    }

    /// A minimal app bundle with a mix of images, some fit for the menu bar and some not.
    private static func makeBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BundledStatusIconTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundle = root.appending(path: "Fixture.app", directoryHint: .isDirectory)
        let resources = bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleIconFile": "Fixture.png",
            "CFBundlePackageType": "APPL",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appending(path: "Contents/Info.plist"))

        try writePNG("StatusBarIcon.png", in: resources, width: 18, height: 18, color: .black)
        try writePNG("fluxicon.png", in: resources, width: 18, height: 18, color: .systemBlue)
        try writePNG("Fixture.png", in: resources, width: 18, height: 18, color: .black)
        try writePNG("AppIcon-small.png", in: resources, width: 18, height: 18, color: .black)
        try writePNG("Banner.png", in: resources, width: 200, height: 18, color: .black)
        try writePNG("Tiny.png", in: resources, width: 4, height: 4, color: .black)
        try writePNG("Glyph.png", in: resources, width: 16, height: 16, color: .systemRed)
        try "not an image".write(to: resources.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        return bundle
    }

    @Test("Only menu bar sized images that are not the app icon are offered, status names first")
    func candidates() throws {
        let bundle = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        let candidates = BundledStatusIcon.candidates(forBundleAt: bundle)
        let names = candidates.map(\.name)
        #expect(Set(names) == ["StatusBarIcon.png", "fluxicon.png", "Glyph.png"])
        #expect(names.first == "StatusBarIcon.png")
        let allLoose = candidates.allSatisfy(\.isLoose)
        #expect(allLoose)
        #expect(candidates.first { $0.name == "StatusBarIcon.png" }?.image.isTemplate == true, "one grey ink becomes a template")
        #expect(candidates.first { $0.name == "Glyph.png" }?.image.isTemplate == false, "a coloured image keeps its colours")
        #expect(candidates.first?.id == "StatusBarIcon.png")

        // A second read comes from the cache, even once the files are gone.
        try FileManager.default.removeItem(at: bundle.appending(path: "Contents/Resources"))
        #expect(BundledStatusIcon.candidates(forBundleAt: bundle).map(\.name) == names)
    }

    @Test("The automatic pick takes the status-named image")
    func automaticPick() throws {
        let bundle = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let picked = BundledStatusIcon.image(forBundleAt: bundle)
        #expect(picked === BundledStatusIcon.candidates(forBundleAt: bundle).first { $0.name == "StatusBarIcon.png" }?.image)
    }

    @Test("Without a status-named image the loose icon file is picked, and with neither nothing is")
    func looseIconFallback() throws {
        let bundle = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        try FileManager.default.removeItem(at: bundle.appending(path: "Contents/Resources/StatusBarIcon.png"))
        #expect(BundledStatusIcon.image(forBundleAt: bundle) != nil)
        #expect(BundledStatusIcon.candidates(forBundleAt: bundle).contains { $0.name == "fluxicon.png" })

        let bare = try Self.makeBundle()
        defer { try? FileManager.default.removeItem(at: bare.deletingLastPathComponent()) }
        let resources = bare.appending(path: "Contents/Resources")
        try FileManager.default.removeItem(at: resources.appending(path: "StatusBarIcon.png"))
        try FileManager.default.removeItem(at: resources.appending(path: "fluxicon.png"))
        #expect(BundledStatusIcon.image(forBundleAt: bare) == nil)
    }

    @Test("No bundle, or a folder that is not one, offers nothing")
    func missingBundle() {
        #expect(BundledStatusIcon.candidates(forBundleAt: nil).isEmpty)
        #expect(BundledStatusIcon.image(forBundleAt: nil) == nil)
        let missing = FileManager.default.temporaryDirectory.appending(path: "NoSuchBundle-\(UUID().uuidString).app")
        #expect(BundledStatusIcon.candidates(forBundleAt: missing).isEmpty)
    }
}
