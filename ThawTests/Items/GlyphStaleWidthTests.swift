//
//  GlyphStaleWidthTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Pins how a picture that no longer fits its item gives way to a much narrower one, as when an
/// icon stops showing text, while a crop of the overflow arrows still loses.
@MainActor
@Suite("Glyph stale width")
struct GlyphStaleWidthTests {
    /// A crop of the given point width, 16 points tall, with opaque ink inkWidth wide centred in it.
    private static func capture(width: CGFloat, inkWidth: CGFloat) throws -> MenuBarItemGlyphCapture {
        let scale: CGFloat = 2
        let context = try #require(CGContext(
            data: nil,
            width: Int(width * scale),
            height: Int(16 * scale),
            bitsPerComponent: 8,
            bytesPerRow: Int(width * scale) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: (width - inkWidth) / 2 * scale, y: 0, width: inkWidth * scale, height: 16 * scale))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
    }

    /// An icon that stopped showing text: a wide picture with text, and a narrow one without.
    private static func withAndWithoutText() throws -> (wide: MenuBarItemGlyphCapture, narrow: MenuBarItemGlyphCapture) {
        try (capture(width: 60, inkWidth: 52), capture(width: 22, inkWidth: 16))
    }

    private static func item(_ app: String, windowID: CGWindowID, width: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(app), title: "Item-0", windowID: windowID, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 900, y: 4, width: width, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    // MARK: preferredCachedImage

    @Test("A much narrower new icon replaces a picture that no longer fits its item")
    func narrowerIconReplacesStalePicture() throws {
        let (wide, narrow) = try Self.withAndWithoutText()

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: wide, candidate: narrow, oldPictureIsStale: true) == narrow)
        #expect(MenuBarItemImageCache.preferredCachedImage(existing: wide, candidate: narrow) == wide,
                "without the item saying otherwise, a much narrower crop may be the overflow arrows")
    }

    @Test("A crop narrower than a trusted glyph loses even to a stale picture")
    func untrustedCropLosesToStalePicture() throws {
        let wide = try Self.capture(width: 60, inkWidth: 52)
        let arrows = try Self.capture(width: 14, inkWidth: 10)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: wide, candidate: arrows, oldPictureIsStale: true) == wide)
    }

    // MARK: preferredRevealedImage

    @Test("A revealed picture replaces the old one when the item's recorded width disagrees with it")
    func revealedUsesTheRecordedWidth() throws {
        let (wide, narrow) = try Self.withAndWithoutText()

        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: wide, candidate: narrow, recordedItemWidth: 22) == narrow)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: wide, candidate: narrow, recordedItemWidth: 60) == wide)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: wide, candidate: narrow) == wide)
    }

    @Test("A revealed picture also gives way when only the item list, read again since, has the new width")
    func revealedUsesTheListedWidth() throws {
        // The record held from before the reveal still has the old width.
        let (wide, narrow) = try Self.withAndWithoutText()

        #expect(MenuBarItemImageCache.preferredRevealedImage(
            existing: wide,
            candidate: narrow,
            recordedItemWidth: 60,
            listedItemWidth: 22
        ) == narrow)
        #expect(MenuBarItemImageCache.preferredRevealedImage(
            existing: wide,
            candidate: narrow,
            recordedItemWidth: 60,
            listedItemWidth: 60
        ) == wide)
    }

    @Test("A revealed item's picture is judged by its recorded width and its width in the item list")
    func revealedItemUsesBothWidths() throws {
        let (wide, narrow) = try Self.withAndWithoutText()
        let held = Self.item("com.example.vpn", windowID: 7, width: 60)
        let listed = Self.item("com.example.vpn", windowID: 40, width: 22)

        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: wide, candidate: narrow, revealing: held, listedWidths: [listed.tag: 22]) == narrow)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: wide, candidate: narrow, revealing: held, listedWidths: [:]) == wide)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: wide, candidate: narrow, revealing: listed, listedWidths: [:]) == narrow)
    }

    // MARK: oldPictureIsStale

    @Test("A picture is stale when any width Thaw has for its item disagrees with it")
    func staleWhenAnyWidthDisagrees() throws {
        let picture = try Self.capture(width: 60, inkWidth: 52)

        #expect(MenuBarItemImageCache.oldPictureIsStale(picture, itemWidths: [60, 22]))
        #expect(!MenuBarItemImageCache.oldPictureIsStale(picture, itemWidths: [60, nil]))
        #expect(!MenuBarItemImageCache.oldPictureIsStale(picture, itemWidths: []))
        #expect(!MenuBarItemImageCache.oldPictureIsStale(picture, itemWidths: [8]), "a width too narrow to trust says nothing")
    }

    // MARK: The item list

    @Test("The item list's width is found for a tag with an older window ID, but not for a system item")
    func listedWidthMatchesOlderWindowIDs() {
        let listed = MenuBarItemTag(namespace: .string("com.example.vpn"), title: "Item-0", windowID: 40, instanceIndex: 0)
        let held = MenuBarItemTag(namespace: .string("com.example.vpn"), title: "Item-0", windowID: 7, instanceIndex: 0)

        #expect(MenuBarItemImageCache.listedWidth(of: listed, in: [listed: 22]) == 22)
        #expect(MenuBarItemImageCache.listedWidth(of: held, in: [listed: 22]) == 22)
        #expect(MenuBarItemImageCache.listedWidth(of: held, in: [:]) == nil)
    }

    @Test("A pass's new pictures replace stale ones by the item list's widths, and keep ones that fit")
    func mergeUsesTheListedWidths() throws {
        let (wide, narrow) = try Self.withAndWithoutText()
        let stopped = Self.item("com.example.stopped", windowID: 1, width: 22)
        let showing = Self.item("com.example.showing", windowID: 2, width: 60)
        let added = Self.item("com.example.added", windowID: 3, width: 22)
        var bar = MenuBarItemCache(displayID: nil)
        bar[.visible] = [stopped, showing, added]
        let appState = AppState()
        appState.itemManager.itemCache = bar
        let imageCache = MenuBarItemImageCache()
        imageCache.appState = appState

        #expect(imageCache.listedItemWidths() == [stopped.tag: 22, showing.tag: 60, added.tag: 22])

        var images = [stopped.tag: wide, showing.tag: wide]
        imageCache.mergeNewImages([stopped.tag: narrow, showing.tag: narrow, added.tag: narrow], into: &images)

        #expect(images == [stopped.tag: narrow, showing.tag: wide, added.tag: narrow])
    }

    @Test("Without an item list, a much narrower new picture loses as before")
    func mergeWithoutItemList() throws {
        let (wide, narrow) = try Self.withAndWithoutText()
        let tag = Self.item("com.example.stopped", windowID: 1, width: 22).tag
        let imageCache = MenuBarItemImageCache()

        #expect(imageCache.listedItemWidths().isEmpty)

        var images = [tag: wide]
        imageCache.mergeNewImages([tag: narrow], into: &images)

        #expect(images == [tag: wide])
    }
}
