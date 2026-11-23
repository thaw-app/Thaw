//
//  GlyphCapturePolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Pins the rules that decide whether a crop is a real glyph and which of two
/// crops the cache keeps: MenuBarItemImageCache.isTrustedGlyph(_:) and
/// preferredCachedImage(existing:candidate:).
@MainActor
@Suite("Glyph capture policy")
struct GlyphCapturePolicyTests {
    /// A crop of the given point width, 16 points tall. Opaque white unless blank, which
    /// leaves every pixel transparent; inkHeight and inkWidth centre a smaller block of ink in it.
    private static func capture(
        width: CGFloat,
        scale: CGFloat = 1,
        blank: Bool = false,
        inkHeight: CGFloat? = nil,
        inkWidth: CGFloat? = nil
    ) throws -> MenuBarItemGlyphCapture {
        try ItemsFixture.centredInkGlyph(
            width: width, inkWidth: inkWidth, inkHeight: inkHeight, scale: scale, color: blank ? nil : CGColor(gray: 1, alpha: 1)
        )
    }

    // MARK: isTrustedGlyph

    @Test("A crop exactly at the minimum width is trusted")
    func minimumWidthIsTrusted() throws {
        let width = MenuBarItemImageCache.minimumTrustedGlyphWidth
        #expect(try MenuBarItemImageCache.isTrustedGlyph(Self.capture(width: width)))
        #expect(try MenuBarItemImageCache.isTrustedGlyph(Self.capture(width: width + 9)))
    }

    @Test("A crop one point under the minimum width is chevron bleed")
    func underMinimumWidthIsNotTrusted() throws {
        let width = MenuBarItemImageCache.minimumTrustedGlyphWidth - 1
        #expect(try !MenuBarItemImageCache.isTrustedGlyph(Self.capture(width: width)))
    }

    @Test("The width is measured in points, not device pixels")
    func widthIsMeasuredInPoints() throws {
        // 28 px at 2x is 14 pt: wide enough in pixels, too narrow in points.
        #expect(try !MenuBarItemImageCache.isTrustedGlyph(Self.capture(width: 14, scale: 2)))
        #expect(try MenuBarItemImageCache.isTrustedGlyph(Self.capture(width: 15, scale: 2)))
    }

    @Test("A blank crop is never trusted, however wide")
    func blankIsNotTrusted() throws {
        #expect(try !MenuBarItemImageCache.isTrustedGlyph(Self.capture(width: 24, blank: true)))
    }

    // MARK: preferredCachedImage

    @Test("A blank existing image loses to any candidate")
    func blankExistingLoses() throws {
        let existing = try Self.capture(width: 24, blank: true)
        let narrow = try Self.capture(width: 8)
        let blank = try Self.capture(width: 20, blank: true)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: narrow) == narrow)
        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: blank) == blank)
    }

    @Test("A blank candidate loses to a settled glyph")
    func blankCandidateLoses() throws {
        let existing = try Self.capture(width: 20)
        let candidate = try Self.capture(width: 24, blank: true)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == existing)
    }

    @Test("A revealed item's picture drawn much smaller, as while it scales in, loses to the one it has")
    func shrunkenRevealLoses() throws {
        let existing = try Self.capture(width: 24, scale: 2, inkHeight: 16, inkWidth: 22)
        let candidate = try Self.capture(width: 24, scale: 2, inkHeight: 10, inkWidth: 14)

        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate) == existing)
        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == candidate,
                "A live item's glyph may really get shorter, like a graph or a level")
    }

    @Test("Without Native hiding, which rebuilds the bar on a reveal, a revealed picture drawn much smaller wins")
    func smallerRevealWinsUnderStandardHiding() throws {
        let existing = try Self.capture(width: 24, scale: 2, inkHeight: 16, inkWidth: 22)
        let candidate = try Self.capture(width: 24, scale: 2, inkHeight: 10, inkWidth: 14)

        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate, revealRebuildsBar: false) == candidate)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate, revealRebuildsBar: true) == existing)
    }

    @Test("A redesigned icon that is much shorter but about as wide wins, as Docker Desktop's new whale")
    func shorterRedesignWins() throws {
        // The old icon's ink was 22 × 17.5 pt and the new one's 21 × 13 pt: 74% of the height, 95% of the width.
        let existing = try Self.capture(width: 24, scale: 2, inkHeight: 16, inkWidth: 22)
        let candidate = try Self.capture(width: 24, scale: 2, inkHeight: 12, inkWidth: 21)

        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate) == candidate)
        #expect(!MenuBarItemImageCache.looksScaledDown(candidate, from: existing))
    }

    @Test("A revealed item's picture about as tall as the one it has wins")
    func sameHeightRevealWins() throws {
        let existing = try Self.capture(width: 24, scale: 2, inkHeight: 16)
        let candidate = try Self.capture(width: 24, scale: 2, inkHeight: 14)

        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate) == candidate)
    }

    @Test("A revealed item's picture still follows the blank and width rules")
    func revealedFollowsTheCachedRules() throws {
        let existing = try Self.capture(width: 20)
        let blank = try Self.capture(width: 24, blank: true)
        let narrow = try Self.capture(width: 14)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: blank) == existing)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: narrow) == existing)
    }

    @Test("A candidate under three quarters of the existing width loses")
    func muchNarrowerCandidateLoses() throws {
        let existing = try Self.capture(width: 20)
        let candidate = try Self.capture(width: 14)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == existing)
    }

    @Test("A candidate at exactly three quarters of the existing width wins")
    func threeQuarterWidthCandidateWins() throws {
        let existing = try Self.capture(width: 20)
        let candidate = try Self.capture(width: 15)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == candidate)
    }

    @Test("A candidate at least as wide replaces the existing glyph")
    func wideCandidateWins() throws {
        let existing = try Self.capture(width: 20)
        let same = try Self.capture(width: 20)
        let wider = try Self.capture(width: 32)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: same) == same)
        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: wider) == wider)
    }
}

/// Pins how a picture retaken after the spacing shrank replaces the wider one:
/// GlyphMarginChange and its part in preferredCachedImage(existing:candidate:).
@MainActor
@Suite("Glyph margin change")
struct GlyphMarginChangeTests {
    /// A crop of the given point width, 16 points tall, with ink inkWidth wide centred in it;
    /// inkHeight centres a shorter band vertically.
    private static func capture(
        width: CGFloat,
        inkWidth: CGFloat,
        inkHeight: CGFloat? = nil,
        scale: CGFloat = 2
    ) throws -> MenuBarItemGlyphCapture {
        try ItemsFixture.centredInkGlyph(width: width, inkWidth: inkWidth, inkHeight: inkHeight, scale: scale)
    }

    // MARK: onlyMarginsShrank

    @Test("The same icon with less space beside it counts as a margin change")
    func sameIconLessSpace() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)
        let candidate = try Self.capture(width: 22, inkWidth: 15)

        #expect(GlyphMarginChange.onlyMarginsShrank(from: existing, to: candidate))
    }

    @Test("Icons within a point of each other count as the same icon")
    func inkTolerance() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)

        #expect(try GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 16)))
        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 17)))
    }

    @Test("A different icon is not a margin change")
    func differentIcon() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)

        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 10)))
        #expect(try !GlyphMarginChange.onlyMarginsShrank(
            from: existing,
            to: Self.capture(width: 22, inkWidth: 15, inkHeight: 10)
        ))
    }

    @Test("A picture that is not narrower is not a margin change")
    func notNarrower() throws {
        let existing = try Self.capture(width: 22, inkWidth: 15)

        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 15)))
        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 36, inkWidth: 15)))
    }

    // MARK: preferredCachedImage

    @Test("A picture taken after the spacing shrank replaces the wider one")
    func narrowerSameIconWins() throws {
        // Rocket at spacing 16 was 36 pt wide; at spacing 2 it is 22 pt, under three quarters.
        let existing = try Self.capture(width: 36, inkWidth: 15)
        let candidate = try Self.capture(width: 22, inkWidth: 15)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == candidate)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate) == candidate)
    }

    @Test("A much narrower picture of another icon still loses")
    func narrowerOtherIconLoses() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)
        let candidate = try Self.capture(width: 22, inkWidth: 8)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == existing)
    }

    @Test("A crop narrower than a trusted glyph loses even when its ink matches")
    func untrustedCropLoses() throws {
        let existing = try Self.capture(width: 24, inkWidth: 10)
        let candidate = try Self.capture(width: 14, inkWidth: 10)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == existing)
    }
}

/// Pins how a picture that no longer fits its item gives way to a much narrower one, as when an
/// icon stops showing text, while a crop of the overflow arrows still loses.
@MainActor
@Suite("Glyph stale width")
struct GlyphStaleWidthTests {
    /// A crop of the given point width, 16 points tall, with opaque ink inkWidth wide centred in it.
    private static func capture(width: CGFloat, inkWidth: CGFloat) throws -> MenuBarItemGlyphCapture {
        try ItemsFixture.centredInkGlyph(width: width, inkWidth: inkWidth, scale: 2)
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

/// A picture taken while the icon still slides in keeps its right edge and loses its left part.
/// The reveal path keeps the complete picture it has, and a complete one replaces a cut one it
/// kept. Live recaptures take what the item really draws, even when that loses its left part.
@MainActor
@Suite("Glyph leading cut")
struct GlyphLeadingCutTests {
    private typealias Cache = MenuBarItemImageCache

    /// A 16 pt tall crop, with ink from inkFrom to inkTo points across its width.
    private static func crop(
        width: CGFloat, inkFrom: CGFloat, inkTo: CGFloat, scale: CGFloat = 2, alpha: CGFloat = 1
    ) throws -> MenuBarItemGlyphCapture {
        let pixelHeight = Int(16 * scale)
        return try ItemsFixture.glyph(
            width: Int(width * scale), height: pixelHeight, scale: scale,
            ink: CGRect(x: inkFrom * scale, y: 0, width: (inkTo - inkFrom) * scale, height: CGFloat(pixelHeight)),
            color: CGColor(red: 0, green: 0, blue: 0, alpha: alpha)
        )
    }

    @Test("A reveal catch missing its left part loses to the complete one")
    func leftCutLosesOnReveal() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let cut = try Self.crop(width: 24, inkFrom: 12, inkTo: 20)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: cut) == complete)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: cut, revealRebuildsBar: false) == complete,
                "Standard hiding's reveals can still be caught mid-slide")
    }

    @Test("A live item whose left ink disappears updates, as right-aligned text getting shorter")
    func leftCutWinsLive() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let cut = try Self.crop(width: 24, inkFrom: 12, inkTo: 20)
        #expect(Cache.preferredCachedImage(existing: complete, candidate: cut) == cut)
    }

    @Test("A reveal catch that is a sliver of the icon loses to the complete one")
    func sliverLosesOnReveal() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let sliver = try Self.crop(width: 24, inkFrom: 18, inkTo: 20)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: sliver) == complete)
    }

    @Test("A complete picture replaces a cut one already kept")
    func completeReplacesCut() throws {
        let cut = try Self.crop(width: 24, inkFrom: 12, inkTo: 20)
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        #expect(Cache.preferredCachedImage(existing: cut, candidate: complete) == complete)
        #expect(Cache.preferredRevealedImage(existing: cut, candidate: complete) == complete)
    }

    @Test("Text that gets shorter and a narrower centred symbol still replace the old picture")
    func realNarrowingWins() throws {
        let wide = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let shorterText = try Self.crop(width: 24, inkFrom: 4, inkTo: 12)
        let narrowerSymbol = try Self.crop(width: 24, inkFrom: 8, inkTo: 16)
        #expect(Cache.preferredCachedImage(existing: wide, candidate: shorterText) == shorterText)
        #expect(Cache.preferredCachedImage(existing: wide, candidate: narrowerSymbol) == narrowerSymbol)
    }

    @Test("An item that changed width is a new picture, not a cut one")
    func resizedItemWins() throws {
        let wide = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let resized = try Self.crop(width: 22, inkFrom: 12, inkTo: 20)
        #expect(Cache.preferredCachedImage(existing: wide, candidate: resized) == resized)
    }

    @Test("Ink that runs into the left edge marks a picture as clipped; a padded or blank one is not")
    func clippedAtLeadingEdge() throws {
        #expect(try Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 0, inkTo: 6)))
        #expect(try Cache.isClippedAtLeadingEdge(Self.crop(width: 17, inkFrom: 0, inkTo: 0.5)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 4, inkTo: 20)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 0.5, inkTo: 20)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 10, inkTo: 10)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 0, inkTo: 20, alpha: 0.3)), "Faint residue of the bar is not ink")
    }

    @Test("Ink that runs into the right edge marks a picture as clipped there, and only there")
    func clippedAtTrailingEdge() throws {
        let pushedRight = try Self.crop(width: 24, inkFrom: 15, inkTo: 24)
        #expect(Cache.isClippedAtTrailingEdge(pushedRight))
        #expect(!Cache.isClippedAtLeadingEdge(pushedRight))
        #expect(try !Cache.isClippedAtTrailingEdge(Self.crop(width: 24, inkFrom: 0, inkTo: 9)))
        #expect(try !Cache.isClippedAtTrailingEdge(Self.crop(width: 24, inkFrom: 4, inkTo: 20)))
        #expect(try !Cache.isClippedAtTrailingEdge(Self.crop(width: 24, inkFrom: 4, inkTo: 24, alpha: 0.3)), "Faint residue of the bar is not ink")
    }

    @Test("A capture the user asked for retakes a picture clipped at its right edge too")
    func rightClippedPictureIsRetakenOnRequest() throws {
        let pushedRight = try Self.crop(width: 24, inkFrom: 15, inkTo: 24)
        #expect(Cache.prewarmNeedsCapture(cachedImage: pushedRight, wouldAttemptCapture: true, retakesClipped: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: pushedRight, wouldAttemptCapture: true))
    }

    @Test("A reveal catch pushed against the left edge loses to the padded picture, and a padded one replaces it")
    func clippedCatchLosesOnReveal() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let pushedLeft = try Self.crop(width: 24, inkFrom: 0, inkTo: 9)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: pushedLeft) == complete)
        #expect(Cache.preferredRevealedImage(existing: pushedLeft, candidate: complete) == complete)
        #expect(Cache.preferredCachedImage(existing: complete, candidate: pushedLeft) == pushedLeft, "A live item is taken as drawn")
    }

    @Test("An icon that always draws to its left edge, or an item that changed width, still updates on reveal")
    func edgeToEdgeIconStillUpdates() throws {
        let fullWidth = try Self.crop(width: 24, inkFrom: 0, inkTo: 24)
        let fullWidthAgain = try Self.crop(width: 24, inkFrom: 0, inkTo: 23)
        #expect(Cache.preferredRevealedImage(existing: fullWidth, candidate: fullWidthAgain) == fullWidthAgain)

        let padded = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let resizedToEdge = try Self.crop(width: 30, inkFrom: 0, inkTo: 30)
        #expect(Cache.preferredRevealedImage(existing: padded, candidate: resizedToEdge) == resizedToEdge)
    }

    @Test("Only a capture the user asked for retakes a clipped picture")
    func clippedPictureNeedsARequestedCapture() throws {
        let clipped = try Self.crop(width: 24, inkFrom: 0, inkTo: 6)
        let padded = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        #expect(Cache.prewarmNeedsCapture(cachedImage: clipped, wouldAttemptCapture: true, retakesClipped: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: clipped, wouldAttemptCapture: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: clipped, wouldAttemptCapture: false, retakesClipped: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: padded, wouldAttemptCapture: true, retakesClipped: true))
    }

    @Test("Ink bounds are in points, and a blank picture has none")
    func inkBounds() throws {
        let bounds = try #require(Cache.inkBounds(of: Self.crop(width: 24, inkFrom: 4, inkTo: 20)))
        #expect(abs(bounds.minX - 4) < 0.01 && abs(bounds.maxX - 20) < 0.01)
        #expect(abs(bounds.height - 16) < 0.01)
        #expect(try Cache.inkBounds(of: Self.crop(width: 24, inkFrom: 10, inkTo: 10)) == nil)
    }
}
