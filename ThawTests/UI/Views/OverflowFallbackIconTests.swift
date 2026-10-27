//
//  OverflowFallbackIconTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// Which image a slot shows for an item, from its capture, its app and the user's icon choice.
@Suite("Overflow fallback icon", .serialized, .scratchDefaults)
@MainActor
struct OverflowFallbackIconTests {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    private static func item(
        _ namespace: MenuBarItemTag.Namespace,
        title: String = "Item",
        sourcePID: pid_t? = ownPID,
        width: CGFloat = 24
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0),
            windowID: 0xFFFF_FE00,
            ownerPID: sourcePID ?? 0,
            sourcePID: sourcePID,
            bounds: CGRect(x: 100, y: 0, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// A capture of the given point size, filled or fully transparent.
    private static func capture(width: Int, height: Int = 16, filled: Bool = true, scale: CGFloat = 1) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if filled {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
    }

    @Test("A capture is usable up to the width limit, or the item's own width when it is wider")
    func captureWidthLimit() {
        #expect(!OverflowFallbackIcon.isUsableCapture(width: nil))
        #expect(OverflowFallbackIcon.isUsableCapture(width: 240))
        #expect(!OverflowFallbackIcon.isUsableCapture(width: 241))
        #expect(OverflowFallbackIcon.isUsableCapture(width: 300, itemWidth: 296))
        #expect(!OverflowFallbackIcon.isUsableCapture(width: 800, itemWidth: 2000), "no item is wider than the item cap")
    }

    @Test("A blank or missing capture is not usable, a drawn one is")
    func blankCaptures() throws {
        #expect(!OverflowFallbackIcon.isUsableCapture(nil))
        #expect(try !OverflowFallbackIcon.isUsableCapture(Self.capture(width: 20, filled: false)))
        #expect(try OverflowFallbackIcon.isUsableCapture(Self.capture(width: 20)))
        #expect(try !OverflowFallbackIcon.isUsableCapture(Self.capture(width: 400)))
        #expect(try OverflowFallbackIcon.isUsableCapture(Self.capture(width: 400), for: Self.item(.string("com.example"), width: 400)))
    }

    @Test("System hosts keep their captures, other apps can draw from their app icon")
    func systemPreviewRules() {
        #expect(OverflowFallbackIcon.usesCapturedSystemPreview(Self.item(.controlCenter)))
        #expect(OverflowFallbackIcon.usesCapturedSystemPreview(Self.item(.menuBarAgent)))
        #expect(!OverflowFallbackIcon.usesCapturedSystemPreview(Self.item(.string("com.example"))))

        #expect(!OverflowFallbackIcon.canRenderAppIconWithoutCapture(for: Self.item(.controlCenter)))
        #expect(OverflowFallbackIcon.canRenderAppIconWithoutCapture(for: Self.item(.textInputMenuAgent)))
        #expect(OverflowFallbackIcon.canRenderAppIconWithoutCapture(for: Self.item(.string("com.example"))))
        #expect(!OverflowFallbackIcon.canRenderAppIconWithoutCapture(for: Self.item(.string("com.example"), sourcePID: nil)))
    }

    @Test("Only an item with a known section may fall back to its app icon")
    func fallbackNeedsSection() {
        #expect(!OverflowFallbackIcon.supportsMissingCaptureFallback(for: nil))
        #expect(OverflowFallbackIcon.supportsMissingCaptureFallback(for: .hidden))
    }

    @Test("A usable capture is shown as captured")
    func usableCaptureWins() throws {
        let appState = AppState()
        let capture = try Self.capture(width: 20)
        let image = OverflowFallbackIcon.resolvedImage(
            for: Self.item(.string("com.example")),
            section: .hidden,
            appState: appState,
            capturedImage: capture
        )
        guard case let .capture(shown) = image else {
            Issue.record("expected the capture, got \(String(describing: image))")
            return
        }
        #expect(shown == capture)
    }

    @Test("A missing capture falls back to the owning app's icon")
    func missingCaptureUsesAppIcon() {
        let appState = AppState()
        let image = OverflowFallbackIcon.resolvedImage(
            for: Self.item(.string("com.example")),
            section: .hidden,
            appState: appState,
            capturedImage: nil
        )
        guard case .appIcon = image else {
            Issue.record("expected an app icon, got \(String(describing: image))")
            return
        }
    }

    @Test("Control Center items show the Control Center icon, an unresolved app the generic glyph")
    func iconSources() {
        #expect(OverflowFallbackIcon.image(for: Self.item(.controlCenter)) === ControlCenterIcon.image)
        let generic = OverflowFallbackIcon.image(for: Self.item(.string("com.example.gone"), sourcePID: nil))
        #expect(generic != nil)
        #expect(OverflowFallbackIcon.image(for: Self.item(.menuBarAgent)) != nil, "the agent gets the generic glyph")
    }

    @Test("The always-use-app-icon setting prefers the app icon over a good capture")
    func alwaysUseAppIcon() throws {
        let appState = AppState()
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems = true
        let item = Self.item(.string("com.example"))
        #expect(OverflowFallbackIcon.shouldPreferAppIcon(for: item, in: .visible, appState: appState, hasUsableCapture: true))
        #expect(!OverflowFallbackIcon.shouldPreferAppIcon(for: Self.item(.controlCenter), in: .visible, appState: appState, hasUsableCapture: true))
        #expect(!OverflowFallbackIcon.shouldPreferAppIcon(for: item, in: nil, appState: appState, hasUsableCapture: false))
        let quit = Self.item(.string("com.example.quit"), sourcePID: nil)
        #expect(!OverflowFallbackIcon.shouldPreferAppIcon(for: quit, in: .visible, appState: appState, hasUsableCapture: true))

        let image = try OverflowFallbackIcon.resolvedImage(for: item, section: .visible, appState: appState, capturedImage: Self.capture(width: 20))
        guard case .appIcon = image else {
            Issue.record("expected an app icon, got \(String(describing: image))")
            return
        }
    }

    @Test("Thaw's own icon follows the visible section's state")
    func selectedThawIcon() {
        let appState = AppState()
        let control = MenuBarItem(
            tag: .visibleControlItem,
            windowID: 0xFFFF_FE01,
            ownerPID: Self.ownPID,
            sourcePID: Self.ownPID,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: MenuBarItemTag.visibleControlItem.title,
            isOnScreen: true
        )
        #expect(OverflowFallbackIcon.selectedThawIcon(for: Self.item(.string("com.example")), appState: appState) == nil)
        let shown = OverflowFallbackIcon.selectedThawIcon(for: control, appState: appState, visibleControlItemState: .showSection)
        let hidden = OverflowFallbackIcon.selectedThawIcon(for: control, appState: appState, visibleControlItemState: .hideSection)
        let fallback = OverflowFallbackIcon.selectedThawIcon(for: control, appState: appState)
        #expect(shown != nil || hidden != nil || fallback != nil || appState.settings.thawIcon.hidden.nsImage(for: appState) == nil)
        #expect(OverflowFallbackIcon.preferredImage(for: control, appState: appState) != nil)
    }

    @Test("The icon cache answers the same image until the process is forgotten")
    func iconCache() {
        let first = OverflowFallbackIcon.cachedAppIcon(forPID: Self.ownPID)
        let second = OverflowFallbackIcon.cachedAppIcon(forPID: Self.ownPID)
        #expect(first === second)
        OverflowFallbackIcon.forgetIcon(forPID: Self.ownPID)
        #expect(OverflowFallbackIcon.cachedAppIcon(forPID: -12345) == nil)
        OverflowFallbackIcon.forgetIcon(forPID: -12345)
    }

    @Test("Resolving many items keys each image by its tag")
    func resolvedImages() {
        let appState = AppState()
        let items = [Self.item(.string("com.example.a"), title: "A"), Self.item(.string("com.example.b"), title: "B")]
        let images = OverflowFallbackIcon.resolvedImages(
            for: items,
            appState: appState,
            imageCache: appState.imageCache
        ) { _ in .hidden }
        #expect(Set(images.keys) == Set(items.map(\.tag)))
    }
}

@Suite("Menu bar item glyph")
@MainActor
struct MenuBarItemGlyphTests {
    private static func capture(width: Int, height: Int, scale: CGFloat) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: width - 8, height: height - 8))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
    }

    @Test("A capture's size is in points and it fits a shorter row without upscaling in a taller one")
    func captureSizing() throws {
        let image = try MenuBarItemDisplayImage.capture(Self.capture(width: 40, height: 32, scale: 2))
        #expect(image.pointSize == CGSize(width: 20, height: 16))
        #expect(!image.isTemplate)
        #expect(image.isReinkable, "one black ink on transparency reads as a single-ink glyph")
        #expect(image.targetSize(fittingHeight: 8) == CGSize(width: 10, height: 8))
        #expect(image.targetSize(fittingHeight: 40) == CGSize(width: 20, height: 16))
        #expect(image.targetSize(fittingHeight: nil) == CGSize(width: 20, height: 16))
        #expect(image.targetSize(fittingHeight: 0) == CGSize(width: 20, height: 16))
    }

    @Test("An app icon keeps its own size and template flag")
    func appIconSizing() {
        let icon = NSImage(size: CGSize(width: 18, height: 18))
        icon.isTemplate = true
        let image = MenuBarItemDisplayImage.appIcon(icon)
        #expect(image.pointSize == CGSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.isReinkable)
        let empty = MenuBarItemDisplayImage.appIcon(NSImage(size: .zero))
        #expect(empty.targetSize(fittingHeight: 10) == .zero)
    }

    @Test("The glyph draws at its fitted size")
    func glyphDraws() throws {
        let image = try MenuBarItemDisplayImage.capture(Self.capture(width: 40, height: 32, scale: 2))
        let glyph = MenuBarItemGlyph(image: image, fittingHeight: 8, reinksCaptures: true)
        let host = NSHostingView(rootView: glyph)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize == CGSize(width: 10, height: 8))
        let render = OffscreenRender(glyph, size: CGSize(width: 10, height: 8))
        #expect(try render.pixels().contains { $0 != 0 })
    }
}
