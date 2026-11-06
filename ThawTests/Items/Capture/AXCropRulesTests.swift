//
//  AXCropRulesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw
import ThawCapture

@MainActor
@Suite("Accessibility bounds crop rules")
struct AXCropRulesTests {
    private typealias Rejection = AXCropRules.Rejection

    private static let display = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test("A clean glyph inside its bounds is cropped and claims its rectangle")
    func cleanGlyphIsCropped() throws {
        let item = makeItem()
        let verdict = try verdict(for: item)

        guard case let .cropped(glyph, cropRect) = verdict else {
            Issue.record("Expected a crop, got \(verdict)")
            return
        }
        #expect(!glyph.isEffectivelyBlank)
        #expect(cropRect == CGRect(x: 2000, y: 9, width: 48, height: 48))
    }

    @Test("The failure ledger is asked only for items the pass did not forgive", arguments: [false, true])
    func ledgerSkipsUnforgivenItems(forgiven: Bool) throws {
        let item = makeItem()
        var asked = false
        let verdict = try verdict(for: item, rules: rules(forgivenTags: forgiven ? [item.tag] : [])) { _ in
            asked = true
            return true
        }

        #expect(asked == !forgiven)
        #expect(forgiven ? verdict.isCropped : verdict.rejection == .keepPrior)
    }

    @Test("Ownership, concealment and neighbour rules decide before any pixel is read")
    func identityRules() throws {
        let item = makeItem()
        let wide = makeItem(title: "Wide", x: 990, width: 60)
        let neighbour = ["neighbour": CGRect(x: 1000, y: 4.5, width: 24, height: 24)]

        #expect(try verdict(for: item, rules: rules(ambiguous: [item.uniqueIdentifier])).rejection == .invalidateUnconditionally)
        #expect(try verdict(for: item, rules: rules(concealed: [item.uniqueIdentifier])).rejection == .keepPrior)
        #expect(try verdict(for: item, rules: rules(overflow: [item.bounds])).rejection == .invalidate)
        #expect(try verdict(for: wide, rules: rules(captureTimeBounds: neighbour)).rejection == .invalidateUnconditionally)
    }

    @Test("A re-read position costs the capture only when it disagrees or the catalog says the item moved")
    func freshnessRules() throws {
        let item = makeItem()
        let moved = [item.uniqueIdentifier: item.bounds.offsetBy(dx: 24, dy: 0)]

        #expect(try verdict(for: item, rules: rules(validate: true, postCapture: moved)).rejection == .keepPrior)
        #expect(try verdict(for: item, rules: rules(validate: true, absenceMeansMoved: true)).rejection == .keepPrior)
        #expect(try verdict(for: item, rules: rules(validate: true, absenceMeansMoved: false)).isCropped)
        #expect(try verdict(for: item, rules: rules(validate: true, postCapture: [item.uniqueIdentifier: item.bounds])).isCropped)
    }

    @Test("Bounds outside the capture keep the picture on another display's bar and drop it when parked")
    func placementRules() throws {
        let otherBar = makeItem(x: 1600)
        let parked = makeItem(y: 400)
        let displays = [Self.display, CGRect(x: 1470, y: 0, width: 1470, height: 956)]

        #expect(try verdict(for: otherBar, displays: displays).rejection == .keepPrior)
        #expect(try verdict(for: otherBar, displays: [Self.display]).rejection == .invalidate)
        #expect(try verdict(for: parked, displays: displays).rejection == .invalidate)
    }

    @Test("Degenerate, clipped and shared crop rectangles fall back to the app icon")
    func cropRectangleRules() throws {
        let item = makeItem()
        let capture = try CaptureFixture.barCapture(opaque: false)
        let unscaled = ScreenCapture.MenuBarHostingCapture(image: capture.image, windowFrame: capture.windowFrame, scale: 0)
        let prior = MenuBarItemTag(namespace: .string("com.example.prior"), title: "Prior", instanceIndex: 0)
        let claimed = [CGRect(x: 2000, y: 9, width: 48, height: 48): prior]

        #expect(try verdict(for: item, capture: unscaled).rejection == .invalidate)
        #expect(try verdict(for: makeItem(x: 1460)).rejection == .invalidate)
        #expect(try verdict(for: item, claimed: claimed).rejection == .sharesCropRect(with: prior))
    }

    @Test("Background removal rejects a slab the window cannot separate and wallpaper the strip cannot")
    func backgroundRules() throws {
        let item = makeItem()
        let slab = try CaptureFixture.barCapture(opaque: true, glyphXs: [])
        let busy = try CaptureFixture.barCapture(opaque: true, busyBackground: true)

        #expect(try verdict(for: item, capture: slab, source: .barWindow).rejection == .invalidate)
        #expect(try verdict(for: item, capture: busy, source: .displayStrip, rules: rules(knockOut: true)).rejection == .invalidate)
        #expect(try verdict(for: item, capture: CaptureFixture.barCapture(opaque: true), source: .displayStrip, rules: rules(knockOut: true)).isCropped)
    }

    @Test("A blank crop keeps a reflow-transient item's picture and drops anyone else's")
    func blankRules() throws {
        let blank = try CaptureFixture.barCapture(opaque: false, glyphXs: [])
        let system = makeItem(namespace: "com.apple.systemuiserver")

        #expect(try verdict(for: makeItem(), capture: blank).rejection == .invalidate)
        #expect(system.tag.isNonConcealableSystemItem)
        #expect(try verdict(for: system, capture: blank).rejection == .keepPrior)
    }

    @Test("A crop narrower than a trusted glyph is chevron bleed")
    func narrowCropIsRejected() throws {
        let narrow = makeItem(x: 1006, width: 12)

        #expect(try verdict(for: narrow).rejection == .invalidate)
    }

    @Test("Verdicts land in the pass, and a shared rectangle also takes the earlier crop away")
    func passRecordsVerdicts() throws {
        let first = makeItem()
        let second = makeItem(title: "Second", x: 1100)
        let glyph = try MenuBarItemGlyphCapture(cgImage: CaptureFixture.barCapture(opaque: false).image, scale: 2)
        var pass = MenuBarItemImageCache.CapturePass()

        pass.record(.cropped(glyph, cropRect: .zero), for: first)
        pass.record(.rejected(.sharesCropRect(with: first.tag)), for: second)
        pass.record(.rejected(.failedCrop), for: second)

        #expect(pass.captured.isEmpty)
        #expect(pass.recoveredItems.map(\.tag) == [first.tag])
        #expect(pass.unconditionallyInvalidatedTags == [first.tag, second.tag])
        #expect(pass.failedCaptureItems.map(\.tag) == [second.tag])
        #expect(pass.unreadable.map(\.tag) == [second.tag, second.tag])
    }

    private func verdict(
        for item: MenuBarItem,
        capture: ScreenCapture.MenuBarHostingCapture? = nil,
        source: AXCropRules.CaptureSource = .hosting,
        rules: AXCropRules.SourceRules? = nil,
        claimed: [CGRect: MenuBarItemTag] = [:],
        displays: [CGRect] = [display],
        shouldSkip: (MenuBarItem) -> Bool = { _ in false }
    ) throws -> AXCropRules.Verdict {
        try AXCropRules.verdict(
            for: AXCropRules.Candidate(
                item: item,
                bounds: item.bounds,
                capture: capture ?? CaptureFixture.barCapture(opaque: false),
                source: source
            ),
            rules: rules ?? self.rules(),
            claimedCropRects: claimed,
            displayBounds: { displays },
            shouldSkip: shouldSkip
        )
    }

    private func rules(
        knockOut: Bool = false,
        validate: Bool = false,
        absenceMeansMoved: Bool = false,
        postCapture: [String: CGRect] = [:],
        captureTimeBounds: [String: CGRect] = [:],
        overflow: [CGRect] = [],
        concealed: Set<String> = [],
        ambiguous: Set<String> = [],
        forgivenTags: Set<MenuBarItemTag> = []
    ) -> AXCropRules.SourceRules {
        AXCropRules.SourceRules(
            knockOutBackground: knockOut,
            validateFreshBounds: validate,
            absenceMeansMoved: absenceMeansMoved,
            postCaptureBoundsByID: postCapture,
            captureTimeBoundsByID: captureTimeBounds,
            overflowBounds: overflow,
            concealedIdentifiers: concealed,
            ambiguousIdentifiers: ambiguous,
            forgivenTags: forgivenTags
        )
    }

    private func makeItem(
        namespace: String = "com.example.status",
        title: String = "Status",
        x: CGFloat = 1000,
        y: CGFloat = 4.5,
        width: CGFloat = 24
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(namespace), title: title, instanceIndex: 0),
            windowID: 101,
            ownerPID: 999_991,
            sourcePID: 999_991,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}

private extension AXCropRules.Verdict {
    var isCropped: Bool {
        if case .cropped = self {
            true
        } else {
            false
        }
    }

    var rejection: AXCropRules.Rejection? {
        if case let .rejected(rejection) = self {
            rejection
        } else {
            nil
        }
    }
}
