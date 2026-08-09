//
//  ControlItemImageConversionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Testing
@testable import Thaw

/// Covers ``ControlItemImage``'s conversion to `NSImage` through the
/// `nsImage(customIceIconIsTemplate:)` seam — every case except the
/// `AppState` overload, which only forwards the template flag.
///
/// The stored form and value semantics live in `ControlItemImageTests`;
/// this suite is only about what the cases render to.
///
/// The builtin chevrons are handler-backed images, so requesting a TIFF
/// representation is what actually runs the drawing closure; without it the
/// path-stroking code never executes.
@MainActor
@Suite("Control item image conversion")
struct ControlItemImageConversionTests {
    // MARK: Builtins

    @Test("Builtin chevrons render as templates at their declared sizes")
    func builtinChevronsRender() throws {
        let large = try #require(
            ControlItemImage.builtin(.chevronLarge).nsImage(customIceIconIsTemplate: false)
        )
        let small = try #require(
            ControlItemImage.builtin(.chevronSmall).nsImage(customIceIconIsTemplate: false)
        )

        #expect(large.isTemplate)
        #expect(small.isTemplate)
        #expect(large.size == CGSize(width: 12, height: 12))
        #expect(small.size == CGSize(width: 9, height: 9))
        // Rasterizing runs the drawing handler; a nil TIFF would mean the
        // stroke code produced nothing.
        #expect(large.tiffRepresentation != nil)
        #expect(small.tiffRepresentation != nil)
    }

    // MARK: Symbols

    @Test("A system symbol converts to a template image")
    func symbolConverts() throws {
        let image = try #require(
            ControlItemImage.symbol("circle").nsImage(customIceIconIsTemplate: false)
        )
        #expect(image.isTemplate)
    }

    @Test("An unknown symbol name converts to nil")
    func unknownSymbolIsNil() {
        let image = ControlItemImage.symbol("thaw.definitely.not.a.symbol")
            .nsImage(customIceIconIsTemplate: false)
        #expect(image == nil)
    }

    // MARK: Catalog

    @Test("An unknown catalog name converts to nil")
    func unknownCatalogNameIsNil() {
        let image = ControlItemImage.catalog("ThawDefinitelyNotAnAsset")
            .nsImage(customIceIconIsTemplate: false)
        #expect(image == nil)
    }

    // MARK: Data

    @Test("Image data honours the template flag", arguments: [true, false])
    func dataHonoursTemplateFlag(isTemplate: Bool) throws {
        let source = NSImage(size: CGSize(width: 4, height: 4), flipped: false) { bounds in
            NSColor.black.setFill()
            bounds.fill()
            return true
        }
        let tiff = try #require(source.tiffRepresentation)

        let image = try #require(
            ControlItemImage.data(tiff).nsImage(customIceIconIsTemplate: isTemplate)
        )
        #expect(image.isTemplate == isTemplate)
    }

    @Test("Garbage image data converts to nil")
    func garbageDataIsNil() {
        let image = ControlItemImage.data(Data([0x00, 0x01, 0x02]))
            .nsImage(customIceIconIsTemplate: true)
        #expect(image == nil)
    }
}
