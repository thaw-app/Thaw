//
//  ExtensionsGraphicsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Builds a premultiplied-first, 32-bit little-endian RGBA image — the shape
/// the capture paths produce — and runs `draw` against its context.
private func makeCanvas(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ),
        "Could not create a bitmap context"
    )
    draw(context)
    return try #require(context.makeImage(), "Could not snapshot the bitmap context")
}

/// Builds a clear canvas with a single filled rectangle on it.
///
/// The rectangle is given in Core Graphics coordinates (origin bottom left),
/// but every assertion below is written in terms of the trimmed *size*, which
/// is orientation independent.
private func makeCanvas(
    width: Int,
    height: Int,
    fill rect: CGRect,
    background: CGFloat = 0
) throws -> CGImage {
    try makeCanvas(width: width, height: height) { context in
        if background > 0 {
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(rect)
    }
}

/// Covers the graphical extensions in `Utilities/Extensions.swift`.
///
/// Every one of these extensions is declared without `nonisolated` in a module
/// built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the suites that
/// touch them are pinned to the main actor. `CGImage` is the exception — that
/// extension is explicitly `nonisolated`.
///
/// Deliberately out of reach here:
///
/// - `CGImage.averageColor`, `CGImage.isTransparent`, and
///   `CGImage.detachedCopy` are covered by `CGImageAnalysisTests` and
///   `CGImageDetachedCopyTests`.
/// - `CGColor.brightness` cannot be driven down its `nil` branch: every color
///   space that can be constructed from a unit test converts to RGB.
@Suite("Graphics extensions")
struct ExtensionsGraphicsTests {
    // MARK: - CGColor

    /// `brightness` is the W3C perceived-luminance formula, and it decides
    /// whether the menu bar tint is treated as light or dark. The weights are
    /// the whole substance of the function, so each channel is measured on its
    /// own.
    @MainActor
    @Suite("CGColor brightness")
    struct CGColorBrightnessTests {
        private func color(_ components: [Double], alpha: Double = 1) throws -> CGColor {
            let values = components.map { CGFloat($0) } + [CGFloat(alpha)]
            return try #require(
                CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: values),
                "Could not create a device RGB color"
            )
        }

        @Test("Each channel carries its own W3C weight", arguments: [
            ([1.0, 1.0, 1.0], 1.0),
            ([0.0, 0.0, 0.0], 0.0),
            ([1.0, 0.0, 0.0], 0.299),
            ([0.0, 1.0, 0.0], 0.587),
            ([0.0, 0.0, 1.0], 0.114),
            ([0.5, 0.5, 0.5], 0.5),
            ([1.0, 1.0, 0.0], 0.886),
        ])
        func channelWeights(components: [Double], expected: Double) throws {
            let brightness = try #require(color(components).brightness)
            #expect(abs(brightness - CGFloat(expected)) < 0.005, "components: \(components)")
        }

        /// The formula reads three components out of a four-component color,
        /// so a transparent color must measure the same as an opaque one.
        @Test("Alpha does not change the measurement")
        func alphaIsIgnored() throws {
            let opaque = try #require(color([1, 0, 0], alpha: 1).brightness)
            let clear = try #require(color([1, 0, 0], alpha: 0).brightness)

            #expect(abs(opaque - clear) < 0.005)
        }

        /// Grayscale colors have to be converted before they can be measured;
        /// black and white survive any conversion exactly, so they pin the
        /// conversion step without pinning a color management detail.
        @Test("A non-RGB color is converted before it is measured", arguments: [
            (0.0, 0.05),
            (1.0, 0.95),
        ])
        func grayscaleIsConverted(gray: Double, bound: Double) throws {
            let brightness = try #require(CGColor(gray: CGFloat(gray), alpha: 1).brightness)

            if gray == 0 {
                #expect(brightness < CGFloat(bound))
            } else {
                #expect(brightness > CGFloat(bound))
            }
        }
    }

    // MARK: - CGImage transparency trimming

    /// `trimmingTransparency(around:alphaThreshold:)` and its private
    /// `TransparencyContext` are what turn a captured menu bar item into a
    /// tightly cropped icon, so an off-by-one inset or a mishandled empty image
    /// shows up as a visibly misaligned or missing item.
    ///
    /// The cases below assert on the trimmed *dimensions* rather than the
    /// origin, which keeps them independent of the row order of the underlying
    /// bitmap.
    @Suite("CGImage transparency trimming")
    struct TransparencyTrimmingTests {
        @Test("Clear margins are trimmed away from all four edges")
        func allEdgesAreTrimmed() throws {
            let image = try makeCanvas(width: 20, height: 20, fill: CGRect(x: 4, y: 6, width: 8, height: 8))

            let trimmed = try #require(image.trimmingTransparency())

            #expect(trimmed.width == 8)
            #expect(trimmed.height == 8)
        }

        @Test("Only the requested edge is trimmed")
        func onlyRequestedEdgesAreTrimmed() throws {
            // Opaque from x = 4 to the right edge, over the full height.
            let image = try makeCanvas(width: 20, height: 20, fill: CGRect(x: 4, y: 0, width: 16, height: 20))

            let trimmed = try #require(image.trimmingTransparency(around: [.minXEdge]))

            #expect(trimmed.width == 16)
            #expect(trimmed.height == 20)
        }

        @Test("Trimming the horizontal edges leaves the height alone")
        func horizontalTrimKeepsHeight() throws {
            let image = try makeCanvas(width: 20, height: 20, fill: CGRect(x: 4, y: 6, width: 8, height: 8))

            let trimmed = try #require(image.trimmingTransparency(around: [.minXEdge, .maxXEdge]))

            #expect(trimmed.width == 8)
            #expect(trimmed.height == 20)
        }

        @Test("An empty edge set returns the image untouched")
        func emptyEdgeSetIsANoOp() throws {
            let image = try makeCanvas(width: 20, height: 20, fill: CGRect(x: 4, y: 6, width: 8, height: 8))

            let trimmed = try #require(image.trimmingTransparency(around: []))

            #expect(trimmed.width == 20)
            #expect(trimmed.height == 20)
        }

        /// Nothing to crop to. Returning the untouched image instead would hand
        /// the caller a fully clear icon and hide the emptiness.
        @Test("A fully clear image cannot be trimmed")
        func fullyClearImageYieldsNil() throws {
            let image = try makeCanvas(width: 20, height: 20) { _ in }

            #expect(image.trimmingTransparency() == nil)
        }

        @Test("An already tight image is returned unchanged")
        func alreadyTightImageIsUnchanged() throws {
            let image = try makeCanvas(width: 20, height: 20, fill: CGRect(x: 0, y: 0, width: 20, height: 20))

            let trimmed = try #require(image.trimmingTransparency())

            #expect(trimmed.width == 20)
            #expect(trimmed.height == 20)
        }

        @Test("A single opaque pixel trims down to itself")
        func singlePixelTrimsToItself() throws {
            let image = try makeCanvas(width: 16, height: 16, fill: CGRect(x: 7, y: 9, width: 1, height: 1))

            let trimmed = try #require(image.trimmingTransparency())

            #expect(trimmed.width == 1)
            #expect(trimmed.height == 1)
        }

        /// A threshold of one or more would call every pixel transparent, so
        /// the context refuses to be built and the original image is handed
        /// back rather than nothing.
        @Test("A threshold of one or more disables trimming", arguments: [1.0, 1.5])
        func saturatedThresholdDisablesTrimming(threshold: Double) throws {
            let image = try makeCanvas(width: 20, height: 20, fill: CGRect(x: 4, y: 6, width: 8, height: 8))

            let trimmed = try #require(image.trimmingTransparency(alphaThreshold: CGFloat(threshold)))

            #expect(trimmed.width == 20)
            #expect(trimmed.height == 20)
        }

        @Test("The threshold decides which faint pixels survive")
        func thresholdSelectsFaintPixels() throws {
            // A faint wash over the whole canvas, with an opaque square on top.
            let image = try makeCanvas(
                width: 20,
                height: 20,
                fill: CGRect(x: 6, y: 6, width: 8, height: 8),
                background: 0.2
            )

            // At the default threshold the faint wash counts as content.
            let untrimmed = try #require(image.trimmingTransparency())
            #expect(untrimmed.width == 20)
            #expect(untrimmed.height == 20)

            // Raised above the wash, only the opaque square survives.
            let trimmed = try #require(image.trimmingTransparency(alphaThreshold: 0.5))
            #expect(trimmed.width == 8)
            #expect(trimmed.height == 8)
        }
    }

    // MARK: - NSBezierPath

    /// `union` maps AppKit's winding rule onto Core Graphics' fill rule, and
    /// `drawShadow` hangs a shadow off the current graphics context. The
    /// boolean geometry itself belongs to Core Graphics; what is asserted here
    /// is the mapping, the clipping, and the graphics-state balance.
    @MainActor
    @Suite("NSBezierPath")
    struct NSBezierPathTests {
        /// A square with a second, identically wound square inside it: filled
        /// solid under the non-zero rule, and a ring with a hole under the
        /// even-odd rule.
        private func doublyWoundSquare() -> NSBezierPath {
            let path = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
            path.appendRect(CGRect(x: 25, y: 25, width: 50, height: 50))
            return path
        }

        @Test("A union spans both operands", arguments: [
            NSBezierPath.WindingRule.evenOdd,
            NSBezierPath.WindingRule.nonZero,
        ])
        func unionSpansBothOperands(rule: NSBezierPath.WindingRule) {
            let left = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
            let right = NSBezierPath(rect: CGRect(x: 40, y: 20, width: 10, height: 10))

            let bounds = left.union(right, using: rule).bounds

            #expect(abs(bounds.minX) < 0.01)
            #expect(abs(bounds.minY) < 0.01)
            #expect(abs(bounds.maxX - 50) < 0.01)
            #expect(abs(bounds.maxY - 30) < 0.01)
        }

        /// The two rules have to reach Core Graphics as different fill rules;
        /// if the mapping collapsed, the hole would appear (or vanish) in both.
        @Test("The winding rule decides whether an enclosed region is filled")
        func windingRuleDecidesEnclosedRegion() {
            let elsewhere = NSBezierPath(rect: CGRect(x: 200, y: 200, width: 10, height: 10))
            let center = CGPoint(x: 50, y: 50)

            let nonZero = doublyWoundSquare().union(elsewhere, using: .nonZero)
            let evenOdd = doublyWoundSquare().union(elsewhere, using: .evenOdd)

            #expect(nonZero.cgPath.contains(center, using: .winding))
            #expect(!evenOdd.cgPath.contains(center, using: .winding))
        }

        @Test("A shadow without a graphics context is a no-op")
        func shadowWithoutContextIsANoOp() {
            let previous = NSGraphicsContext.current
            defer { NSGraphicsContext.current = previous }
            NSGraphicsContext.current = nil

            NSBezierPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
                .drawShadow(color: .black, radius: 4)

            #expect(NSGraphicsContext.current == nil)
        }

        /// Two things have to hold after `drawShadow` returns: something was
        /// actually drawn outside the path, and the clip and shadow it
        /// installed were popped again. The second is why the method saves and
        /// restores the graphics state; without the restore, the red band drawn
        /// afterwards would be clipped away.
        @Test("A shadow spreads outside the path and restores the graphics state")
        func shadowSpreadsAndRestoresState() throws {
            let size = 60
            let rep = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: size,
                    pixelsHigh: size,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ),
                "Could not create a bitmap representation"
            )
            let context = try #require(
                NSGraphicsContext(bitmapImageRep: rep),
                "Could not create a graphics context for the bitmap"
            )

            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)).fill()

            // Vertically centered so the assertions do not depend on whether
            // the bitmap's rows run top down or bottom up.
            NSBezierPath(rect: CGRect(x: 20, y: 20, width: 20, height: 20))
                .drawShadow(color: .black, radius: 6)

            // Outside the clip drawShadow installed (the path bounds grown by
            // the radius, so x from 14 to 46).
            NSColor.red.setFill()
            NSBezierPath(rect: CGRect(x: 0, y: 0, width: 6, height: size)).fill()
            context.flushGraphics()
            NSGraphicsContext.current = previous

            let shadowed = try #require(
                rep.colorAt(x: 18, y: 30)?.usingColorSpace(.deviceRGB),
                "Could not sample the shadowed pixel"
            )
            #expect(shadowed.redComponent < 0.95, "the shadow should darken the background beside the path")

            let afterwards = try #require(
                rep.colorAt(x: 2, y: 30)?.usingColorSpace(.deviceRGB),
                "Could not sample the pixel drawn after the shadow"
            )
            #expect(afterwards.redComponent > 0.9)
            #expect(afterwards.greenComponent < 0.2, "the clip must not survive drawShadow")
            #expect(afterwards.blueComponent < 0.2)
        }
    }

    // MARK: - NSImage

    /// `resized(to:)` is used for every control item image, where losing the
    /// template flag turns a tinted icon into an opaque one.
    @MainActor
    @Suite("NSImage resizing")
    struct NSImageResizingTests {
        private func image(isTemplate: Bool) throws -> NSImage {
            let cgImage = try makeCanvas(width: 10, height: 10, fill: CGRect(x: 0, y: 0, width: 10, height: 10))
            let result = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
            result.isTemplate = isTemplate
            return result
        }

        @Test("The template flag survives the resize", arguments: [true, false])
        func templateFlagIsRetained(isTemplate: Bool) throws {
            let resized = try image(isTemplate: isTemplate).resized(to: NSSize(width: 4, height: 6))

            #expect(resized.isTemplate == isTemplate)
        }

        @Test("The resized image takes the requested size and the original keeps its own")
        func sizeIsAppliedWithoutMutatingTheOriginal() throws {
            let original = try image(isTemplate: false)

            let resized = original.resized(to: NSSize(width: 4, height: 6))

            #expect(resized.size == NSSize(width: 4, height: 6))
            #expect(original.size == NSSize(width: 10, height: 10))
        }

        /// The size alone would be satisfied by an empty image, so force the
        /// drawing handler to run.
        @Test("The resized image can actually be rendered")
        func resizedImageRenders() throws {
            let resized = try image(isTemplate: false).resized(to: NSSize(width: 8, height: 8))

            #expect(resized.tiffRepresentation != nil)
        }
    }

    // MARK: - NSApplication

    /// The window lookup is how the settings and permissions windows are found
    /// again after they are created. The cases below use a freshly minted
    /// identifier so nothing depends on which windows the host app happens to
    /// have open.
    @MainActor
    @Suite("Window lookup by identifier")
    struct WindowLookupTests {
        @Test("A window is found by its identifier, and an unknown one is not")
        func windowIsFoundByIdentifier() {
            let identifier = "ExtensionsGraphicsTests-\(UUID().uuidString)"
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier(identifier)
            defer { window.close() }

            #expect(NSApplication.shared.window(withIdentifier: identifier) === window)
            #expect(NSApplication.shared.window(withIdentifier: identifier + "-absent") == nil)
        }

        /// Windows without an identifier must not match the empty string.
        @Test("A window with no identifier is not matched by an empty identifier")
        func unidentifiedWindowIsNotMatched() {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }

            #expect(NSApplication.shared.window(withIdentifier: "") !== window)
        }
    }

    // MARK: - NSPanel

    /// `waitUntilClosed(timeout:)` gates the item-move sequences on a menu
    /// actually dismissing. Both cases give the call a timeout far longer than
    /// the suite's time limit, so a broken early-exit or a broken KVO wake-up
    /// fails the test instead of quietly falling through to the timeout.
    @MainActor
    @Suite("Waiting for a panel to close")
    struct PanelClosingTests {
        private func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            return panel
        }

        @Test("A panel that is already hidden is not waited on", .timeLimit(.minutes(1)))
        func hiddenPanelReturnsImmediately() async {
            let panel = makePanel()
            defer { panel.close() }

            #expect(!panel.isVisible)
            await panel.waitUntilClosed(timeout: .seconds(180))
        }

        @Test("A visible panel wakes the waiter as soon as it hides", .timeLimit(.minutes(1)))
        func visiblePanelWakesTheWaiter() async throws {
            let panel = makePanel()
            defer { panel.close() }

            panel.orderFront(nil)
            try #require(panel.isVisible, "The panel could not be ordered in; a window server session is required")

            let closer = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                panel.orderOut(nil)
            }

            await panel.waitUntilClosed(timeout: .seconds(180))
            await closer.value

            #expect(!panel.isVisible)
        }
    }
}
