//
//  LayoutBarTileTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A Layout tile explains when macOS keeps its icon out of its section")
struct LayoutBarVisibilityLimitTests {
    private func limit(
        section: MenuBarSectionName,
        registered: Bool? = true,
        bundleID: String = "com.example.app",
        native: Bool = false,
        hidesOthers: Bool = true,
        untracked: Set<String> = [],
        leftAlone: Set<String> = [],
        pinned: Bool = false
    ) -> LayoutBarVisibilityLimit? {
        LayoutBarVisibilityLimit.limit(
            section: section,
            ownerHasRegisteredBundle: registered,
            ownerBundleID: bundleID,
            nativeHiding: .init(isActive: native, untrackedBundleIDs: untracked, leftAloneBundleIDs: leftAlone),
            hidesOtherIcons: hidesOthers,
            isPinnedControlCenterModule: pinned
        )
    }

    @Test("A pinned Control Center item cannot show in Visible while others are hidden")
    func pinnedModuleCannotShow() {
        #expect(limit(section: .visible, pinned: true) == .pinnedModuleCannotShow)
        #expect(limit(section: .visible, hidesOthers: false, pinned: true) == nil)
        #expect(limit(section: .visible, native: true, pinned: true) == nil)
        #expect(limit(section: .hidden, pinned: true) == nil)
    }

    @Test("An icon without a registered bundle cannot show in Visible while others are hidden")
    func unregisteredOwnerCannotShow() {
        #expect(limit(section: .visible, registered: false) == .cannotShow)
        #expect(limit(section: .visible, registered: false, hidesOthers: false) == nil)
        #expect(limit(section: .visible, registered: false, native: true) == nil)
        #expect(limit(section: .visible, registered: nil) == nil)
        #expect(limit(section: .visible, registered: true) == nil)
    }

    @Test("An untracked app cannot hide under native app hiding", arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func untrackedAppCannotHide(section: MenuBarSectionName) {
        let untracked: Set = ["com.example.app"]
        #expect(limit(section: section, native: true, untracked: untracked) == .cannotHide)
        #expect(limit(section: section, native: false, untracked: untracked) == nil)
        #expect(limit(section: section, native: true, untracked: ["com.example.other"]) == nil)
        #expect(limit(section: .visible, native: true, untracked: untracked) == nil)
    }

    @Test("An app switched back on in System Settings is left alone, with its own explanation", arguments: [MenuBarSectionName.hidden, .alwaysHidden])
    func appSwitchedBackOnIsLeftAlone(section: MenuBarSectionName) {
        let leftAlone: Set = ["com.example.app"]
        #expect(limit(section: section, native: true, leftAlone: leftAlone) == .leftAlone)
        #expect(limit(section: section, native: false, leftAlone: leftAlone) == nil)
        #expect(limit(section: .visible, native: true, leftAlone: leftAlone) == nil)
        #expect(limit(section: section, native: true, untracked: leftAlone, leftAlone: leftAlone) == .cannotHide, "no record wins")
        #expect(LayoutBarVisibilityLimit.leftAlone.explanation != LayoutBarVisibilityLimit.cannotHide.explanation)
    }
}

/// Pins which captures Layout re-inks: one grey ink on transparency is drawn in the
/// bar's ink, so icons captured over light and dark parts of the bar match.
@MainActor
@Suite("Layout capture ink")
struct LayoutBarCaptureInkTests {
    /// A 20 by 16 crop with a filled square in the middle on transparency.
    private static func glyph(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: 20,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 20 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 5, y: 4, width: 10, height: 8))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }

    @Test("Black and white glyphs are re-inked", arguments: [0.0, 1.0])
    func greyGlyphsAreTemplates(level: CGFloat) throws {
        let image = try LayoutBarCaptureInk.drawImage(for: Self.glyph(red: level, green: level, blue: level))
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 10, height: 8))
    }

    @Test("A colour icon keeps its own pixels")
    func colourIconsStayAsCaptured() throws {
        let image = try LayoutBarCaptureInk.drawImage(for: Self.glyph(red: 0.1, green: 0.4, blue: 0.95))
        #expect(!image.isTemplate)
    }

    @Test("A placeholder icon is lighter as a template and faded while disabled", arguments: [
        (true, true, 0.8), (true, false, 0.9), (false, true, 0.5), (false, false, 0.5),
    ])
    func placeholderFraction(isEnabled: Bool, isTemplate: Bool, expected: CGFloat) {
        #expect(LayoutBarCaptureInk.placeholderFraction(isEnabled: isEnabled, isTemplate: isTemplate) == expected)
    }
}

@MainActor
@Suite("Stand-in preview size")
struct StandInPreviewSizeTests {
    private func item(_ bundleID: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", instanceIndex: 0),
            windowID: 1, ownerPID: 1, sourcePID: 1,
            bounds: CGRect(x: 0, y: 3, width: 32, height: 24), title: "Item-0", isOnScreen: true
        )
    }

    private let standIn = "\(ThawMenuBarIdentity.bundleIdentifier).extra.focus"

    @Test("Thaw's stand-ins are told apart from other apps")
    func recognizesStandIns() {
        #expect(ThawExtraGlyph.isStandIn(item(standIn).tag))
        #expect(!ThawExtraGlyph.isStandIn(item("com.example.app").tag))
        #expect(!ThawExtraGlyph.isStandIn(item("\(ThawMenuBarIdentity.bundleIdentifier).extra.unknown").tag),
                "an extra this build has no glyph for is not drawn as one")
    }

    @Test("A stand-in's symbol keeps its own size in the preview, while an app icon fills the tile")
    func standInKeepsItsSize() {
        let bounds = CGRect(x: 0, y: 0, width: 32, height: 24)
        let symbol = LayoutBarItemView.overflowFallbackDrawRect(for: item(standIn), imageSize: CGSize(width: 16, height: 15), bounds: bounds)
        #expect(symbol.size == CGSize(width: 16, height: 15))
        #expect(symbol.midX == bounds.midX && symbol.midY == bounds.midY)
        let appIcon = LayoutBarItemView.overflowFallbackDrawRect(for: item("com.example.app"), imageSize: CGSize(width: 16, height: 15), bounds: bounds)
        #expect(appIcon.size == CGSize(width: 24, height: 24))
        let chosen = LayoutBarItemView.overflowFallbackDrawRect(
            for: item("com.example.app"), imageSize: CGSize(width: 16, height: 16), bounds: bounds, isChosenIcon: true
        )
        #expect(chosen.size == CGSize(width: 16, height: 16), "an icon the user chose keeps its glyph size")
    }
}
