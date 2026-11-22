//
//  ThawBarOpeningCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Thaw Bar first icon row")
struct ThawBarOpeningCaptureTests {
    private func item(_ id: CGWindowID) -> MenuBarItem {
        let name = String(id)
        return MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("test.app"), title: name, windowID: id),
            windowID: id, ownerPID: 1, sourcePID: nil,
            bounds: .zero, title: name, isOnScreen: false
        )
    }

    /// Red stands in for the full-color app icon. Captures use their original pixels.
    private func pixels(
        _ opening: ThawBarOpeningCapture, cache: MenuBarItemImageCache, dark: Bool,
        prefersAppIcons: Bool = false, canCapture: Bool = true
    ) throws -> Data {
        let items = [item(1), item(2)]
        let view = opening.row(for: items, cache: cache, prefersAppIcons: prefersAppIcons, canCapture: canCapture) {
            HStack {
                ForEach(items, id: \.windowID) { item in
                    let capture = cache.image(for: item.tag)
                    if MenuBarItemIconFallback.shouldUseAppIcon(
                        for: item,
                        hasCapture: capture != nil,
                        prefersAppIcon: prefersAppIcons
                    ) {
                        Color.red.frame(width: 8, height: 8)
                    } else if let capture {
                        Image(decorative: capture.cgImage, scale: 1)
                    }
                }
            }
        }
        .frame(width: 200, height: 32)
        .background(dark ? Color.black : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
        let image = try #require(ImageRenderer(content: view).cgImage)
        return try #require(image.dataProvider?.data) as Data
    }

    @Test("Cold and partial openings reach the same glyph pixels as warm and repeated openings", arguments: [false, true])
    func firstRow(dark: Bool) throws {
        let cache = MenuBarItemImageCache()
        let opening = ThawBarOpeningCapture()
        let fallback = try pixels(opening, cache: cache, dark: dark, canCapture: false)
        let loading = try pixels(opening, cache: cache, dark: dark)
        #expect(loading != fallback)
        let glyph = try #require(ImageRenderer(content: (dark ? Color.white : .black).frame(width: 8, height: 8)).cgImage)
        let capture = MenuBarItemImageCache.CapturedImage(cgImage: glyph, scale: 1)
        cache.images[item(1).tag] = capture
        #expect(try pixels(opening, cache: cache, dark: dark) == loading)
        cache.images[item(2).tag] = capture
        let firstGlyphs = try pixels(opening, cache: cache, dark: dark)
        #expect(firstGlyphs != loading)
        #expect(firstGlyphs != fallback)
        opening.isPending = false
        #expect(try pixels(opening, cache: cache, dark: dark) == firstGlyphs)
        #expect(try pixels(ThawBarOpeningCapture(), cache: cache, dark: dark) == firstGlyphs)
        // An unavailable app icon leaves its capture in place even when app icons are preferred.
        #expect(try pixels(opening, cache: cache, dark: dark, prefersAppIcons: true) == firstGlyphs)
    }

    @Test("Capture failure releases fallback only for its own presentation")
    func fallbackAfterAttempt() throws {
        let cache = MenuBarItemImageCache()
        let old = ThawBarOpeningCapture()
        let next = ThawBarOpeningCapture()
        let pending = try pixels(next, cache: cache, dark: false)
        old.isPending = false
        let fallback = try pixels(old, cache: cache, dark: false)
        #expect(fallback != pending)
        #expect(try pixels(next, cache: cache, dark: false) == pending)
        #expect(try pixels(next, cache: cache, dark: false, canCapture: false) == fallback)
        #expect(try pixels(next, cache: cache, dark: false, prefersAppIcons: true) == fallback)
    }
}
