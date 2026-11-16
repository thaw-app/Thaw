//
//  GlyphRetakeLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Hidden items whose picture the Thaw Bar retakes although it isn't missing. RevealCapturePrewarm asks it.
///
/// A hidden item is only photographed while revealed, and a picture that looks good is
/// kept, so one taken while the item's app drew it at another width, as before a spacing
/// change, would stay for good. A picture whose width no longer matches its item is retaken
/// at the next Thaw Bar open. A parked item can report a width that is off, and every
/// retake reveals the item, so each item gets one width retake a session and each pass
/// makes a few at most.
@MainActor
final class GlyphRetakeLedger {
    /// A hidden item with a picture, as a pass sees it.
    nonisolated struct Candidate: Equatable {
        /// The item's tag identifier, which outlives a rebuilt menu bar.
        let identifier: String
        /// The width of its picture, in points.
        let pictureWidth: CGFloat
        /// The width the item reports now, in points.
        let itemWidth: CGFloat
    }

    /// The ledger the Thaw Bar's passes share for the session.
    static let shared = GlyphRetakeLedger()

    /// How far apart, in points, a picture and its item may be before the picture counts as stale.
    static nonisolated let widthTolerance: CGFloat = 2

    /// The most width retakes one pass makes, so items reporting odd widths can't keep
    /// the Thaw Bar revealing them one after another.
    static nonisolated let widthRetakesPerPass = 3

    /// Items whose width was retaken this session, by tag identifier.
    private(set) var widthRetaken: Set<String> = []

    /// Whether a picture of pictureWidth no longer fits an item of itemWidth. An item
    /// narrower than a trusted glyph reports no usable width.
    static nonisolated func widthIsStale(pictureWidth: CGFloat, itemWidth: CGFloat) -> Bool {
        itemWidth >= MenuBarItemImageCache.minimumTrustedGlyphWidth
            && abs(pictureWidth - itemWidth) > widthTolerance
    }

    /// The candidates to retake: those whose picture's width is stale and wasn't retaken this
    /// session, the first limit of them in order. A pass over several sections passes what it has
    /// left of widthRetakesPerPass.
    func retakes(among candidates: [Candidate], limit: Int = widthRetakesPerPass) -> Set<String> {
        let stale = candidates.filter { candidate in
            !widthRetaken.contains(candidate.identifier)
                && Self.widthIsStale(pictureWidth: candidate.pictureWidth, itemWidth: candidate.itemWidth)
        }
        return Set(stale.prefix(max(0, limit)).map(\.identifier))
    }

    /// Records a pass's retakes, whether or not they got new pictures, so they aren't made
    /// again this session. A pass cancelled before its end, as when the Thaw Bar closes,
    /// may not have reached them, so it records nothing and the next open tries again.
    func noteRetaken(_ identifiers: Set<String>) {
        guard !Task.isCancelled else { return }
        widthRetaken.formUnion(identifiers)
    }
}
