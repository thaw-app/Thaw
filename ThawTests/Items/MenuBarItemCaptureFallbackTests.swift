//
//  MenuBarItemCaptureFallbackTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import os
import Testing
@testable import Thaw
import ThawCapture

@MainActor
@Suite("Thumbnail capture fallback", .bug("https://github.com/thaw-app/Thaw/issues/1153"))
struct MenuBarItemCaptureFallbackTests {
    @Test("Layout and Simple Mode use the same fresh-position capture pipeline", arguments: [false, true])
    func visibleCaptureRefreshesStalePositionsOnEveryPass(simpleMode: Bool) async throws {
        let nav = MenuBarItemImageCache.NavigationStateSnapshot(
            isThawBarPresented: false,
            isSearchPresented: false,
            isAppFrontmost: true,
            isSettingsPresented: true,
            settingsNavigationIdentifier: simpleMode ? .general : .menuBarLayout,
            isItemHotkeyListExpanded: false,
            isSimpleModeSettings: simpleMode
        )
        let sections = MenuBarItemImageCache.capturableSections(
            from: nav.liveCaptureScope.sections(thawBarSection: nil),
            usesVisibilityRestrictions: true,
            revealedSection: nil
        )
        try #require(sections == [.visible])
        let stale = makeItem(x: 1000)
        let neighbour = makeItem(title: "Neighbour", x: 1000, windowID: 102)
        let cache = MenuBarItemImageCache(screenIsLocked: { false })

        // The log repeated old rectangles after the bar shifted left by 48pt.
        // Keep the layout cache unchanged while the live position changes again.
        for liveX: CGFloat in [952, 904] {
            let current = makeItem(x: liveX)
            let reader = try CaptureFixture(
                hosting: nil,
                strip: makeCapture(opaque: true, glyphX: liveX + 8),
                geometry: .liveItems,
                items: [current, neighbour]
            )
            let result = await cache.captureImages(
                of: [stale], scale: 2, displayID: 42,
                screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                freshBounds: MenuBarItemImageCache.shouldUseFreshBounds(for: sections[0], revealedSection: nil),
                concealedIdentifiers: [], using: reader
            )

            let glyph = try #require(result.captured[stale.tag])
            #expect(!glyph.isEffectivelyBlank)
            #expect(result.unconditionallyInvalidatedTags.isEmpty)
            #expect(await reader.captures == [.strip])
            #expect(await reader.inventoryReadsAtCapture == [1])
        }
    }

    @Test("An item absent from the fresh inventory cannot fall back to its cached rectangle")
    func absentFreshItemSkipsScreenshot() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false),
            strip: makeCapture(opaque: true), items: []
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let result = await cache.captureImages(
            of: [item], scale: 2, displayID: 42, screenFrame: nil,
            freshBounds: MenuBarItemImageCache.shouldUseFreshBounds(for: .visible, revealedSection: nil),
            concealedIdentifiers: [], using: reader
        )

        #expect(result.captured.isEmpty)
        #expect(result.invalidatedTags.isEmpty)
        #expect(result.unreadable.isEmpty)
        #expect(await reader.captures.isEmpty)
    }

    @Test("Fresh pre-capture positions do not bypass post-capture movement or ownership checks", arguments: [
        CaptureFixture.Geometry.moved, .ambiguous,
    ])
    private func refreshedPositionsStillRequirePostCaptureValidation(geometry: CaptureFixture.Geometry) async throws {
        let stale = makeItem(x: 1000)
        let current = makeItem(x: 952)
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false, glyphX: 960),
            strip: makeCapture(opaque: true, glyphX: 960),
            geometry: geometry, items: [current]
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let result = await cache.captureImages(
            of: [stale], scale: 2, displayID: 42, screenFrame: nil,
            freshBounds: MenuBarItemImageCache.shouldUseFreshBounds(for: .visible, revealedSection: nil),
            concealedIdentifiers: [], using: reader
        )

        #expect(result.captured.isEmpty)
        #expect(await reader.captures == [.strip])
        #expect(await reader.inventoryReadsAtCapture == [1])
    }

    @Test("Locking during a capture discards pixels and failure verdicts", arguments: [CaptureFixture.Source.strip, .hosting, .barWindow], [false, true])
    private func lockDuringCaptureDiscardsThePass(source: CaptureFixture.Source, returnsPixels: Bool) async throws {
        let locked = OSAllocatedUnfairLock(initialState: false)
        let item = makeItem()
        let pixels = try makeCapture(opaque: source == .strip)
        let reader = CaptureFixture(
            hosting: source == .hosting && returnsPixels ? pixels : nil,
            barWindow: source == .barWindow && returnsPixels ? pixels : nil,
            strip: source == .strip && returnsPixels ? pixels : nil,
            onCapture: {
                if $0 == source {
                    locked.withLock { $0 = true }
                }
            }
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { locked.withLock { $0 } })
        let result = await cache.axBoundsCapture(
            [(item, item.bounds)], scale: 2, displayID: 42,
            validateFreshBounds: false, concealedIdentifiers: [], using: reader
        )
        #expect(result.captured.isEmpty)
        #expect(result.invalidatedTags.isEmpty)
        #expect(result.unconditionallyInvalidatedTags.isEmpty)
        #expect(result.unreadable.isEmpty)
        #expect(cache.wouldAttemptCapture(of: item))
        #expect(await reader.captures.last == source, "Do not start fallbacks after the lock")
    }

    @Test("An already locked session starts no screenshot reads")
    func lockedSessionDoesNotStartCapture() async {
        let item = makeItem()
        let reader = CaptureFixture(hosting: nil, strip: nil)
        let cache = MenuBarItemImageCache(screenIsLocked: { true })
        let result = await cache.axBoundsCapture(
            [(item, item.bounds)], scale: 2, displayID: 42,
            validateFreshBounds: false, concealedIdentifiers: [], using: reader
        )
        #expect(await reader.captures.isEmpty)
        #expect(result.unreadable.isEmpty)
        #expect(result.invalidatedTags.isEmpty)
    }

    @Test("A valid display-strip glyph avoids window capture", arguments: [false, true])
    func validStripAvoidsWindows(validateFreshBounds: Bool) async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: true, glyph: false),
            barWindow: makeCapture(opaque: true, glyph: false),
            strip: makeCapture(opaque: true)
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { false })

        let result = await cache.axBoundsCapture(
            [(item, item.bounds)],
            scale: 2,
            displayID: 42,
            validateFreshBounds: validateFreshBounds,
            concealedIdentifiers: [],
            using: reader
        )

        let glyph = try #require(result.captured[item.tag])
        #expect(!glyph.cgImage.isTransparent())
        #expect(!glyph.cgImage.hasOpaquePerimeter())
        #expect(await reader.captures == [.strip])
        #expect(await reader.sourcesAtValidation == [.strip])
        #expect(await reader.validatedTags == [item.tag])
    }

    @Test("A missing strip falls back to a valid hosting glyph")
    func missingStripUsesHosting() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(hosting: makeCapture(opaque: false), strip: nil)
        let result = await capture(item, using: reader)

        #expect(result.captured[item.tag] != nil)
        #expect(await reader.captures == [.strip, .hosting])
        #expect(await reader.validatedTags.isEmpty)
    }

    @Test("An owner-window glyph recovers failed strip and hosting captures", arguments: [false, true])
    func failedStripAndHostingUseOwnerWindow(missingHosting: Bool) async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: missingHosting ? nil : makeCapture(opaque: true, glyph: false),
            barWindow: makeCapture(opaque: true),
            strip: nil
        )
        let result = await capture(item, using: reader)

        let glyph = try #require(result.captured[item.tag])
        #expect(!glyph.cgImage.hasOpaquePerimeter())
        #expect(await reader.captures == [.strip, .hosting, .barWindow])
    }

    @Test("A strip cannot use missing, moved or ambiguous owner geometry", arguments: [
        CaptureFixture.Geometry.unavailable, .moved, .ambiguous,
    ])
    private func unsafeStripGeometryIsRejected(geometry: CaptureFixture.Geometry) async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false),
            barWindow: makeCapture(opaque: false),
            strip: makeCapture(opaque: true),
            geometry: geometry,
            items: [item]
        )
        let result = await capture(item, using: reader, validateFreshBounds: true)

        #expect(result.captured.isEmpty)
        #expect(await reader.captures == [.strip])
        #expect(await reader.validatedTags == [item.tag])
    }

    @Test("Failure of every source terminates without blacklisting the item")
    func allSourcesFail() async {
        let item = makeItem()
        let reader = CaptureFixture(hosting: nil, strip: nil)
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let result = await cache.axBoundsCapture(
            [(item, item.bounds)],
            scale: 2,
            displayID: 42,
            validateFreshBounds: false,
            concealedIdentifiers: [],
            using: reader
        )

        #expect(result.captured.isEmpty)
        #expect(result.unreadable.contains { $0.tag == item.tag })
        #expect(cache.wouldAttemptCapture(of: item))
        #expect(await reader.captures == [.strip, .hosting, .barWindow])
        #expect(await reader.validatedTags.isEmpty)
    }

    @Test("A successful crop reports recovery but leaves the failure ledger to the publisher")
    func successfulCropDefersTheLedger() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(hosting: nil, strip: makeCapture(opaque: true))
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        cache.recordCaptureFailure(for: item)
        let result = await cache.axBoundsCapture(
            [(item, item.bounds)], scale: 2, displayID: 42,
            validateFreshBounds: false, concealedIdentifiers: [], using: reader
        )

        #expect(result.captured[item.tag] != nil)
        #expect(result.recoveredItems.map(\.tag) == [item.tag])
        #expect(cache.failedCapturesLock.withLock { $0[item.tag] } != nil, "A pass that may be discarded cannot forgive strikes")
        cache.commitCaptureLedger(of: result)
        #expect(cache.failedCapturesLock.withLock { $0[item.tag] } == nil)
    }

    @Test("A mixed batch keeps the strip glyph and recovers only the unresolved item")
    func mixedBatchKeepsStripGlyph() async throws {
        let hosted = makeItem()
        let fallback = makeItem(title: "Second", x: 1200, windowID: 102)
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false),
            strip: makeCapture(opaque: true, glyphX: 1208)
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let result = await cache.axBoundsCapture(
            [(hosted, hosted.bounds), (fallback, fallback.bounds)],
            scale: 2,
            displayID: 42,
            validateFreshBounds: false,
            concealedIdentifiers: [],
            using: reader
        )

        #expect(Set(result.captured.keys) == [hosted.tag, fallback.tag])
        #expect(await reader.captures == [.strip, .hosting])
        #expect(await reader.validatedTags == [hosted.tag, fallback.tag])
    }

    @Test("Concealed items cannot acquire pixels from any source")
    func concealedItemCannotSupplyGlyph() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false),
            barWindow: makeCapture(opaque: false),
            strip: makeCapture(opaque: true)
        )
        let result = await capture(item, using: reader, concealedIdentifiers: [item.uniqueIdentifier])

        #expect(result.captured.isEmpty)
        #expect(result.unconditionallyInvalidatedTags.isEmpty)
    }

    @Test("Overflow appearing during strip capture remains rejected by window fallbacks")
    func stripOverflowIsRejected() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false),
            barWindow: makeCapture(opaque: false),
            strip: makeCapture(opaque: true),
            stripOverflowBounds: [item.bounds]
        )
        let result = await capture(item, using: reader)

        #expect(result.captured.isEmpty)
        #expect(result.invalidatedTags.contains(item.tag))
    }

    @Test("A strip with an inconsistent pixel scale cannot supply a glyph")
    func malformedStripIsRejected() async throws {
        let item = makeItem()
        let image = try makeCapture(opaque: true)
        let malformed = ScreenCapture.MenuBarHostingCapture(image: image.image, windowFrame: image.windowFrame, scale: 3)
        let reader = CaptureFixture(hosting: nil, strip: malformed)
        let result = await capture(item, using: reader)

        #expect(result.captured.isEmpty)
        #expect(await reader.validatedTags.isEmpty)
    }

    @Test("Unusable strip pixels fall back to a clean hosting glyph")
    func blankStripUsesHosting() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: makeCapture(opaque: false),
            strip: makeCapture(opaque: true, glyph: false)
        )
        let result = await capture(item, using: reader)

        let glyph = try #require(result.captured[item.tag])
        #expect(!glyph.cgImage.isTransparent())
        #expect(!glyph.cgImage.hasOpaquePerimeter())
        #expect(await reader.captures == [.strip, .hosting])
    }

    @Test("Busy wallpaper is rejected; only a clean window fallback can supply the glyph", arguments: [false, true])
    func busyWallpaperUsesWindowFallback(hasWindow: Bool) async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: hasWindow ? makeCapture(opaque: false) : nil,
            strip: makeCapture(opaque: true, busyBackground: true)
        )
        let result = await capture(item, using: reader)

        #expect((result.captured[item.tag] != nil) == hasWindow)
        #expect(await reader.captures == (hasWindow ? [.strip, .hosting] : [.strip, .hosting, .barWindow]))
        if let glyph = result.captured[item.tag] {
            #expect(!glyph.cgImage.hasOpaquePerimeter())
        }
    }

    @Test("An owner-window crop is rejected when icons move while that screenshot is acquired", arguments: [false, true])
    private func ownerWindowMovementDuringAcquisitionIsRejected(stripReadsBlank: Bool) async throws {
        let first = makeItem(title: "First", x: 1000, windowID: 101)
        let second = makeItem(title: "Second", x: 1024, windowID: 102)
        let gate = CaptureGate()
        let reader = try CaptureFixture(
            hosting: nil,
            barWindow: makeCapture(opaque: false, glyphX: 1008, extraGlyphXs: [1032]),
            strip: stripReadsBlank ? makeCapture(opaque: true, glyph: false) : nil,
            items: [first, second],
            gates: [.barWindow: gate]
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let pass = Task {
            await cache.axBoundsCapture(
                [(first, first.bounds), (second, second.bounds)],
                scale: 2, displayID: 42, validateFreshBounds: true,
                concealedIdentifiers: [], using: reader
            )
        }
        await gate.waitUntilArrived()
        // The two same-owner icons swap while the owner-window screenshot is in flight.
        await reader.setItems([
            makeItem(title: "First", x: 1024, windowID: 101),
            makeItem(title: "Second", x: 1000, windowID: 102),
        ])
        await gate.release()
        let result = await pass.value

        #expect(result.captured.isEmpty)
        #expect(result.unconditionallyInvalidatedTags.isEmpty)
        #expect(await reader.captures.last == .barWindow)
        #expect(await reader.sourcesAtInventoryRead.last == .barWindow, "The owner-window crop needs a read taken after it")
    }

    @Test("Overflow appearing during the owner-window screenshot rejects that source", arguments: [false, true])
    private func ownerWindowOverflowDuringAcquisitionIsRejected(validateFreshBounds: Bool) async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: nil,
            barWindow: makeCapture(opaque: false),
            strip: nil,
            items: [item],
            ownerWindowOverflowBounds: [item.bounds]
        )
        let result = await capture(item, using: reader, validateFreshBounds: validateFreshBounds)

        #expect(result.captured.isEmpty)
        #expect(result.invalidatedTags.contains(item.tag))
    }

    @Test("A stable owner-window fallback is still revalidated and published")
    func stableOwnerWindowFallbackStillCaptures() async throws {
        let item = makeItem()
        let reader = try CaptureFixture(
            hosting: nil,
            barWindow: makeCapture(opaque: false),
            strip: nil,
            items: [item]
        )
        let result = await capture(item, using: reader, validateFreshBounds: true)

        #expect(result.captured[item.tag] != nil)
        #expect(await reader.captures == [.strip, .hosting, .barWindow])
        #expect(await reader.sourcesAtInventoryRead == [.barWindow], "Only the owner window produced pixels, and its read follows it")
    }

    @Test("A later owner window recovers while the owner that moved keeps its prior image", arguments: [false, true])
    private func ownerWindowMovementOnlyCostsTheMovedOwner(movedOwnerFirst: Bool) async throws {
        let movedPID: pid_t = movedOwnerFirst ? 999_990 : 999_992
        let stablePID: pid_t = 999_991
        let moved = makeItem(title: "Moved", x: 1000, windowID: 101, ownerPID: movedPID)
        let stable = makeItem(title: "Stable", x: 1200, windowID: 102, ownerPID: stablePID)
        let reader = try CaptureFixture(
            hosting: nil,
            barWindow: makeCapture(opaque: false, glyphX: 1008, extraGlyphXs: [1208]),
            strip: nil,
            items: [moved, stable],
            itemsAfterOwnerWindow: [movedPID: [makeItem(title: "Moved", x: 1024, windowID: 101, ownerPID: movedPID), stable]]
        )
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        let result = await cache.axBoundsCapture(
            [(moved, moved.bounds), (stable, stable.bounds)],
            scale: 2, displayID: 42, validateFreshBounds: true,
            concealedIdentifiers: [], using: reader
        )

        #expect(Set(result.captured.keys) == [stable.tag])
    }

    private func capture(
        _ item: MenuBarItem,
        using reader: CaptureFixture,
        validateFreshBounds: Bool = false,
        concealedIdentifiers: Set<String> = []
    ) async -> MenuBarItemImageCache.CapturePass {
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        return await cache.axBoundsCapture(
            [(item, item.bounds)],
            scale: 2,
            displayID: 42,
            validateFreshBounds: validateFreshBounds,
            concealedIdentifiers: concealedIdentifiers,
            using: reader
        )
    }

    private func makeItem(
        title: String = "Status",
        x: CGFloat = 1000,
        windowID: CGWindowID = 101,
        ownerPID: pid_t = 999_991
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.status"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: ownerPID,
            bounds: CGRect(x: x, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private func makeCapture(
        opaque: Bool,
        glyph: Bool = true,
        glyphX: CGFloat = 1008,
        extraGlyphXs: [CGFloat] = [],
        busyBackground: Bool = false
    ) throws -> ScreenCapture.MenuBarHostingCapture {
        try CaptureFixture.barCapture(
            opaque: opaque,
            glyphXs: glyph ? [glyphX] + extraGlyphXs : [],
            busyBackground: busyBackground
        )
    }
}

/// Holds one fixture source mid-acquisition until the test releases it.
actor CaptureGate {
    private var arrived = false
    private var released = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arriveAndWait() async {
        arrived = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilArrived() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

actor CaptureFixture: MenuBarCaptureReading {
    enum Source: Equatable, Sendable {
        case hosting, barWindow, strip
    }

    enum Geometry: Sendable {
        case stable, unavailable, moved, ambiguous, liveItems
    }

    let hosting: ScreenCapture.MenuBarHostingCapture?
    let barWindow: ScreenCapture.MenuBarHostingCapture?
    let strip: ScreenCapture.MenuBarHostingCapture?
    let geometry: Geometry
    private(set) var items: [MenuBarItem]
    let stripOverflowBounds: [CGRect]
    let ownerWindowOverflowBounds: [CGRect]
    /// The inventory a geometry read reports once that owner's window was captured.
    let itemsAfterOwnerWindow: [pid_t: [MenuBarItem]]
    let gates: [Source: CaptureGate]
    let onCapture: @Sendable (Source) -> Void
    private(set) var captures: [Source] = []
    private(set) var sourcesAtValidation: [Source] = []
    private(set) var validatedTags: [MenuBarItemTag] = []
    private var inventoryReadCount = 0
    private(set) var sourcesAtInventoryRead: [Source?] = []
    private(set) var inventoryReadsAtCapture: [Int] = []

    init(
        hosting: ScreenCapture.MenuBarHostingCapture?,
        barWindow: ScreenCapture.MenuBarHostingCapture? = nil,
        strip: ScreenCapture.MenuBarHostingCapture?,
        geometry: Geometry = .stable,
        items: [MenuBarItem] = [],
        stripOverflowBounds: [CGRect] = [],
        ownerWindowOverflowBounds: [CGRect] = [],
        itemsAfterOwnerWindow: [pid_t: [MenuBarItem]] = [:],
        gates: [Source: CaptureGate] = [:],
        onCapture: @escaping @Sendable (Source) -> Void = { _ in }
    ) {
        self.hosting = hosting
        self.barWindow = barWindow
        self.strip = strip
        self.geometry = geometry
        self.items = items
        self.stripOverflowBounds = stripOverflowBounds
        self.ownerWindowOverflowBounds = ownerWindowOverflowBounds
        self.itemsAfterOwnerWindow = itemsAfterOwnerWindow
        self.gates = gates
        self.onCapture = onCapture
    }

    func setItems(_ items: [MenuBarItem]) {
        self.items = items
    }

    func captureBand(displayID _: CGDirectDisplayID) async -> (frame: CGRect, menuMaxX: CGFloat?) {
        (CGRect(x: 0, y: 0, width: 1470, height: 956), 300)
    }

    func overflowBounds(displayID _: CGDirectDisplayID) async -> [CGRect] {
        (captures.contains(.strip) ? stripOverflowBounds : [])
            + (captures.contains(.barWindow) ? ownerWindowOverflowBounds : [])
    }

    func hostingCapture(displayID _: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        captures.append(.hosting)
        onCapture(.hosting)
        return hosting
    }

    func barWindowCapture(ownerPID: pid_t, displayID _: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        captures.append(.barWindow)
        onCapture(.barWindow)
        await gates[.barWindow]?.arriveAndWait()
        if let moved = itemsAfterOwnerWindow[ownerPID] {
            items = moved
        }
        return barWindow
    }

    func displayStripCapture(displayID _: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        captures.append(.strip)
        inventoryReadsAtCapture.append(inventoryReadCount)
        onCapture(.strip)
        await gates[.strip]?.arriveAndWait()
        return strip
    }

    func menuBarItems(displayID _: CGDirectDisplayID) async -> [MenuBarItem] {
        inventoryReadCount += 1
        sourcesAtInventoryRead.append(captures.last)
        return items
    }

    func liveBounds(
        for candidates: [(item: MenuBarItem, bounds: CGRect)]
    ) async -> (bounds: [String: CGRect], ambiguous: Set<String>) {
        validatedTags = candidates.map(\.item.tag)
        sourcesAtValidation = captures
        switch geometry {
        case .stable:
            return (Dictionary(uniqueKeysWithValues: candidates.map { ($0.item.uniqueIdentifier, $0.bounds) }), [])
        case .unavailable:
            return ([:], [])
        case .moved:
            return (Dictionary(uniqueKeysWithValues: candidates.map {
                ($0.item.uniqueIdentifier, $0.bounds.offsetBy(dx: 24, dy: 0))
            }), [])
        case .ambiguous:
            return ([:], Set(candidates.map(\.item.uniqueIdentifier)))
        case .liveItems:
            let entries = items.enumerated().map { index, item in
                AXGeometryCatalog.Entry(
                    ownerPID: item.ownerPID, itemIndex: index,
                    identityTitle: item.tag.title, frame: item.bounds
                )
            }
            var bounds = [String: CGRect]()
            var ambiguous = Set<String>()
            for candidate in candidates {
                let item = candidate.item
                switch AXGeometryCatalog.match(
                    ownerPID: item.ownerPID, identityTitle: item.tag.title,
                    bounds: candidate.bounds, in: entries
                ) {
                case let .frame(frame): bounds[item.uniqueIdentifier] = frame
                case .ambiguous: ambiguous.insert(item.uniqueIdentifier)
                case .unavailable: break
                }
            }
            return (bounds, ambiguous)
        }
    }
}

extension CaptureFixture {
    /// A 1470×33pt bar at 2x with an 8×10pt glyph drawn at each of glyphXs.
    static func barCapture(
        opaque: Bool,
        glyphXs: [CGFloat] = [1008],
        busyBackground: Bool = false
    ) throws -> ScreenCapture.MenuBarHostingCapture {
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 33)
        let context = try #require(CGContext(
            data: nil,
            width: 2940,
            height: 66,
            bitsPerComponent: 8,
            bytesPerRow: 2940 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: 66)
        context.scaleBy(x: 2, y: -2)
        if opaque {
            context.setFillColor(CGColor(gray: 0.8, alpha: 1))
            context.fill(frame)
        }
        if busyBackground {
            var seed: UInt32 = 0x9E37_79B9
            func nextComponent() -> CGFloat {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return CGFloat((seed >> 16) & 0xFF) / 255
            }
            for y in 0 ..< 24 {
                for x in 0 ..< 24 {
                    context.setFillColor(CGColor(
                        red: nextComponent(), green: nextComponent(), blue: nextComponent(), alpha: 1
                    ))
                    context.fill(CGRect(x: 1000 + CGFloat(x), y: 4.5 + CGFloat(y), width: 1, height: 1))
                }
            }
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in glyphXs {
            context.fill(CGRect(x: x, y: 12, width: 8, height: 10))
        }
        return try ScreenCapture.MenuBarHostingCapture(image: #require(context.makeImage()), windowFrame: frame, scale: 2)
    }
}
