//
//  RevealCaptureRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Reveal Capture Rules

    /// Resolves which requested sections currently have live menu-bar pixels
    /// available for capture. macOS 27 physically removes concealed items from
    /// MenuBarAgent, but temporarily revealed sections can and should be
    /// captured so their real glyphs remain cached after concealment resumes.
    static nonisolated func capturableSections(
        from requestedSections: [MenuBarSection.Name],
        usesVisibilityRestrictions: Bool,
        revealedSection: MenuBarSection.Name?
    ) -> [MenuBarSection.Name] {
        return MenuBarBackendProvider
            .backend(usesVisibilityRestrictions: usesVisibilityRestrictions)
            .capturableSections(
                from: requestedSections,
                revealedSection: revealedSection
            )
    }

    /// How many concealed items are revealed together on a display without a
    /// notch. See revealBatchSize(hasNotch:).
    ///
    /// Revealing one item at a time shows as icons blinking in and out one by
    /// one, and each item pays its own poll loop (an AX enumeration per
    /// attempt) and screenshot pair. A group shares one reveal, one poll loop
    /// and one screenshot pair. Not the whole section, because every revealed
    /// item takes real width: enough of them overflow the bar, pushing items
    /// off screen or into the native chevron, where refreshOverlayItemGlyphs
    /// refuses to capture. Six fits inside the space a concealed section
    /// vacated on any realistic bar.
    private static nonisolated let revealCaptureBatchSize = 6

    /// How many concealed items one reveal may put on the live bar at once.
    ///
    /// What draws the native chevron is width, not concealment. The notch's
    /// lane is small, so revealing six items at once overflows it on a notched
    /// Mac; MenuBarAgent then draws the chevron for exactly the instants the
    /// screenshot pair is taken, and the crops land on arrows. A single
    /// revealed item restores one item's width and always fits. A notchless
    /// lane is wide, so grouping stays there to avoid the reveal parade.
    static nonisolated func revealBatchSize(hasNotch: Bool) -> Int {
        hasNotch ? 1 : revealCaptureBatchSize
    }

    /// Pairs each requested reveal with the live item that answers it, in
    /// request order, resolving a whole batch against one enumeration so two
    /// requests can never claim the same live item.
    ///
    /// Strict identity first, then an owner-scoped fallback for the one shape
    /// strict identity cannot survive. macOS 27 names untitled status items
    /// positionally: the AX walk's per-app fallback counter advances only for
    /// the children it actually enumerates, so a sibling that stays concealed
    /// does not hold its slot. Reveal one of an app's two untitled items and it
    /// comes back as Item-0 when it was minted as Item-1, nothing matches,
    /// the batch resolves empty, no glyph is cached, and the prewarm gate asks
    /// for the same reveal again on every Thaw Bar open.
    ///
    /// The fallback fires only where it cannot mis-pair: both titles carry the
    /// positional Item-N shape (a real title is never renumbered, so a
    /// mismatch there is a different item, not a renamed one), exactly one
    /// request for that app is unmatched, and exactly one of its live items is
    /// unclaimed. Two same-app items revealed together still match strictly,
    /// because revealing both restores the numbering their tags were minted
    /// under. Anything ambiguous stays unresolved rather than guessing, which
    /// costs a reveal and never caches a neighbour's glyph.
    static nonisolated func revealMatches(
        requests: [MenuBarItem],
        live: [MenuBarItem]
    ) -> [MenuBarItem?] {
        var claimed = Set<Int>()
        var matches = [MenuBarItem?](repeating: nil, count: requests.count)

        for (index, request) in requests.enumerated() {
            guard let liveIndex = live.indices.first(where: { candidate in
                !claimed.contains(candidate) && (
                    live[candidate].hasSameIdentity(as: request) ||
                        live[candidate].uniqueIdentifier == request.uniqueIdentifier
                )
            }) else {
                continue
            }
            claimed.insert(liveIndex)
            matches[index] = live[liveIndex]
        }

        let unmatched = requests.indices.filter {
            matches[$0] == nil &&
                MenuBarItemTag.isGenericItemTitle(requests[$0].tag.title)
        }
        for (_, group) in Dictionary(grouping: unmatched, by: { requests[$0].tag.namespace })
            where group.count == 1
        {
            let index = group[0]
            let candidates = live.indices.filter { candidate in
                !claimed.contains(candidate) &&
                    live[candidate].hasSameOwner(as: requests[index]) &&
                    MenuBarItemTag.isGenericItemTitle(live[candidate].tag.title)
            }
            guard candidates.count == 1 else { continue }
            claimed.insert(candidates[0])
            matches[index] = live[candidates[0]]
        }

        return matches
    }

    /// One poll step of waitForRevealedItems: advances the settle state
    /// given the prior settled and previous (last-sighting) maps and the
    /// current current (identifier → live item) matched in this poll.
    ///
    /// An identifier becomes settled when it already has a previous
    /// sighting and its bounds are stable against the current sighting; once
    /// settled it keeps its claim and is not re-measured. An identifier that is
    /// present this poll but not yet settled (or was settled earlier but is
    /// missing this poll) records the current sighting as its new previous,
    /// except a settled identifier that goes missing, which keeps its settled
    /// entry rather than being un-settled by a transient AX drop. An
    /// identifier absent from current and absent from settled clears its
    /// previous entry so a later, differently-positioned sighting is not
    /// measured against a stale one.
    ///
    /// Pure so the settle decision can be tested without a live AX
    /// enumeration. Polling for stable bounds matters because a fixed delay
    /// after a reveal can land while a large section is still recompositing,
    /// when every item's live bounds fail the status-item band check.
    static nonisolated func advanceRevealSettle(
        settled: [String: MenuBarItem],
        previous: [String: MenuBarItem],
        current: [String: MenuBarItem],
        hasStable: (CGRect, CGRect) -> Bool
    ) -> (settled: [String: MenuBarItem], previous: [String: MenuBarItem]) {
        var nextSettled = settled
        var nextPrevious = previous

        for (identifier, liveItem) in current {
            // A settled member keeps its claim; it is not re-measured against
            // a later sighting even if that sighting moved.
            if nextSettled[identifier] != nil {
                continue
            }
            if let prior = nextPrevious[identifier],
               hasStable(prior.bounds, liveItem.bounds)
            {
                nextSettled[identifier] = liveItem
            } else {
                nextPrevious[identifier] = liveItem
            }
        }

        // A non-settled identifier that did not appear in this poll has
        // nothing to measure stability against; drop its prior sighting so a
        // later sighting at a different position is not mis-matched against it.
        // Settled identifiers are left intact: a transient AX drop must not
        // un-settle a member that already proved stable.
        for identifier in previous.keys {
            if current[identifier] == nil, nextSettled[identifier] == nil {
                nextPrevious[identifier] = nil
            }
        }

        return (nextSettled, nextPrevious)
    }

    /// What a grouped reveal does with a cache entry it could not refresh.
    ///
    /// The layout prewarm wants a blank or chevron-width entry gone once the
    /// reveal proves nothing better is available, so the thumbnail falls back
    /// to the app icon instead of a stale crop. The overlay keeps whatever it
    /// holds: its strip is on screen, and swapping a glyph for a fallback icon
    /// mid-pass is a visible regression.
    enum RevealMissPolicy {
        case keepExisting
        case dropUntrustedEntries
    }

    /// Restoration action after temporarily revealing a section for prewarm capture.
    nonisolated enum PrewarmRevealRestorationAction: Equatable {
        case hide
        case noOp
        case show(MenuBarSection.Name)

        /// Whether the cleanup may hide the section this prewarm revealed:
        /// only if the user revealed nothing since the capture path's last hide.
        static func cleanupMayHide(
            userRevealDate: Date?,
            lastCaptureHideDate: Date?
        ) -> Bool {
            guard let userRevealDate else { return true }
            guard let lastCaptureHideDate else { return false }
            return userRevealDate < lastCaptureHideDate
        }

        static func resolve(
            previous: MenuBarSection.Name?,
            currentAfterShow: MenuBarSection.Name?
        ) -> PrewarmRevealRestorationAction {
            if previous == nil {
                return .hide
            }
            if previous == currentAfterShow {
                return .noOp
            }
            if let previous {
                return .show(previous)
            }
            return .noOp
        }
    }
}
