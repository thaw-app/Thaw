//
//  GlyphRetakeLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins which hidden items the Thaw Bar retakes although their picture isn't missing.
@MainActor
@Suite("Glyph retake ledger")
struct GlyphRetakeLedgerTests {
    private static func candidate(_ identifier: String, picture: CGFloat, item: CGFloat) -> GlyphRetakeLedger.Candidate {
        GlyphRetakeLedger.Candidate(identifier: identifier, pictureWidth: picture, itemWidth: item)
    }

    // MARK: widthIsStale

    @Test("A picture left wide by a spacing change is stale")
    func widePictureIsStale() {
        // Rocket's picture from spacing 16 against its item at spacing 2.
        #expect(GlyphRetakeLedger.widthIsStale(pictureWidth: 36, itemWidth: 22))
        #expect(GlyphRetakeLedger.widthIsStale(pictureWidth: 22, itemWidth: 36))
    }

    @Test("A picture within two points of its item fits")
    func closePictureFits() {
        #expect(!GlyphRetakeLedger.widthIsStale(pictureWidth: 22, itemWidth: 22))
        #expect(!GlyphRetakeLedger.widthIsStale(pictureWidth: 24, itemWidth: 22))
        #expect(GlyphRetakeLedger.widthIsStale(pictureWidth: 24.5, itemWidth: 22))
    }

    @Test("An item narrower than a trusted glyph reports no usable width")
    func narrowItemWidthIsUnusable() {
        #expect(!GlyphRetakeLedger.widthIsStale(pictureWidth: 36, itemWidth: 0))
        #expect(!GlyphRetakeLedger.widthIsStale(pictureWidth: 36, itemWidth: 14))
        #expect(GlyphRetakeLedger.widthIsStale(pictureWidth: 36, itemWidth: 15))
    }

    // MARK: retakes

    @Test("A pass retakes only the stale pictures")
    func retakesOnlyStale() {
        let retakes = GlyphRetakeLedger().retakes(among: [
            Self.candidate("rocket", picture: 36, item: 22),
            Self.candidate("yoink", picture: 24, item: 24),
            Self.candidate("clop", picture: 40, item: 26),
        ])

        #expect(retakes == ["rocket", "clop"])
    }

    @Test("A pass retakes at most a few pictures, the first in order")
    func retakesAreCapped() {
        let candidates = (0 ..< 5).map { Self.candidate("item\($0)", picture: 36, item: 22) }

        #expect(GlyphRetakeLedger().retakes(among: candidates) == ["item0", "item1", "item2"])
    }

    @Test("A pass with fewer retakes left takes only that many")
    func limitIsWhatThePassHasLeft() {
        let candidates = (0 ..< 5).map { Self.candidate("item\($0)", picture: 36, item: 22) }

        #expect(GlyphRetakeLedger().retakes(among: candidates, limit: 1) == ["item0"])
        #expect(GlyphRetakeLedger().retakes(among: candidates, limit: 0).isEmpty)
    }

    @Test("A picture retaken for its width this session isn't retaken again")
    func retakenOncePerSession() {
        let ledger = GlyphRetakeLedger()
        let candidates = (0 ..< 5).map { Self.candidate("item\($0)", picture: 36, item: 22) }

        ledger.noteRetaken(ledger.retakes(among: candidates))

        #expect(ledger.retakes(among: candidates) == ["item3", "item4"])
        ledger.noteRetaken(["item3", "item4"])
        #expect(ledger.retakes(among: candidates).isEmpty)
    }

    @Test("A pass cancelled before its end records nothing, so the next open tries again")
    func cancelledPassRecordsNothing() async {
        let ledger = GlyphRetakeLedger()
        let candidates = [Self.candidate("rocket", picture: 36, item: 22)]
        let retakes = ledger.retakes(among: candidates)

        let pass = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            ledger.noteRetaken(retakes)
        }
        await pass.value

        #expect(ledger.retakes(among: candidates) == ["rocket"])
    }
}
