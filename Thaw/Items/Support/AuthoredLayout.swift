//
//  AuthoredLayout.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Authored layout inputs for keeping automatic overflow out of the
/// persisted order.
///
/// Automatic overflow files an authored-Visible item under Hidden in the
/// effective cache. Persisting that cache verbatim turns a cramped-display
/// moment into a permanent hide, so the persistence paths reinsert those
/// concealed items at their recorded Visible slots using the authored
/// assignment and order.
nonisolated struct AuthoredLayoutProjection: Sendable {
    /// Explicit authored assignments, keyed by canonical identifier.
    /// Absence means Visible, matching the runtime's default.
    var sectionAssignment: [String: MenuBarSectionName]
    /// Recorded authored order per section, including overflowed Visible
    /// slots that the effective cache has temporarily filed elsewhere.
    var sectionOrder: [MenuBarSectionName: [String]]

    func authoredSection(for identifier: String) -> MenuBarSectionName {
        sectionAssignment[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] ?? .visible
    }
}

/// Authored layout state the persistence projection reads from a section
/// controller. A plain value so tests run the exact production derivation
/// without a live runtime.
nonisolated struct AuthoredLayoutSource: Sendable {
    var sectionAssignment: [String: MenuBarSectionName]
    var sectionItemOrder: [MenuBarSectionName: [String]]
}

/// What to persist as each section's order while automatic overflow is hiding authored items.
///
/// The effective cache is the membership authority except for an authored-Visible item it
/// filed elsewhere. These rules decide when the authored projection is needed and where the
/// concealed items go back in.
nonisolated enum AuthoredLayout {
    /// Pure derivation and gate. The projection is only needed while the
    /// effective cache still conceals an authored-Visible item. That also
    /// covers the window after overflow is cleared but before the next
    /// inventory walk publishes the restored membership, so a profile capture
    /// in that window cannot record the item as Hidden. Once the cache catches
    /// up the projection is a no-op and the gate returns nil.
    static func authoredLayoutProjection(
        for cache: MenuBarItemCache,
        source: AuthoredLayoutSource
    ) -> AuthoredLayoutProjection? {
        let projection = AuthoredLayoutProjection(
            sectionAssignment: source.sectionAssignment,
            sectionOrder: source.sectionItemOrder
        )
        guard hasConcealedAuthoredVisibleItem(in: cache, projection: projection) else {
            return nil
        }
        return projection
    }

    /// Items eligible for savedSectionOrder: app items with a resolved
    /// sourcePID, plus the visible control item, so reconciliation after a
    /// restart can tell when macOS placed an app item on the wrong side of
    /// it. The hidden and always-hidden dividers stay out; they are always
    /// inserted into desiredFlat at the section boundary.
    static func isPersistable(_ item: MenuBarItem) -> Bool {
        if item.tag == .visibleControlItem {
            return true
        }
        return !item.isControlItem && item.sourcePID != nil
    }

    /// Whether any persistable, non-transient item the effective cache filed
    /// outside Visible is authored Visible. That is exactly automatic
    /// overflow, or a cache that has not yet caught up with its clearing.
    static func hasConcealedAuthoredVisibleItem(
        in cache: MenuBarItemCache,
        projection: AuthoredLayoutProjection
    ) -> Bool {
        for section in MenuBarSectionName.allCases where section != .visible {
            for item in cache[section]
                where isPersistable(item) && !item.isTransientControlCenterItem
            {
                if projection.authoredSection(for: item.uniqueIdentifier) == .visible {
                    return true
                }
            }
        }
        return false
    }

    /// The identifiers for `section`, in persistence order.
    ///
    /// The effective cache is the membership authority everywhere except the
    /// automatic-overflow case: an authored-Visible item the cache filed under
    /// Hidden is reinserted at its recorded Visible slot. Present items keep
    /// the effective cache order, so a within-section reorder is untouched,
    /// and no other section's membership is rewritten (always-hidden remains
    /// governed by the backend's allowsAlwaysHidden mapping). Pure over inputs.
    static func authoredCurrentIdentifiers(
        for section: MenuBarSectionName,
        effective: [MenuBarItem],
        persistableByIdentifier: [String: MenuBarItem],
        savedSectionOrder: [String: [String]],
        projection: AuthoredLayoutProjection
    ) -> [String] {
        // Drop authored-Visible items the effective cache filed outside
        // Visible: those are automatic overflow and are reinserted into
        // Visible below. Authored Hidden/Always Hidden membership is left as
        // the backend bucketed it, so the allowsAlwaysHidden mapping stands.
        let present = effective
            .filter { section == .visible || projection.authoredSection(for: $0.uniqueIdentifier) != .visible }
            .map(\.uniqueIdentifier)
        guard section == .visible else { return present }

        let presentSet = Set(present)
        let concealed = persistableByIdentifier.values
            .filter {
                projection.authoredSection(for: $0.uniqueIdentifier) == .visible
                    && !presentSet.contains($0.uniqueIdentifier)
            }
            .map(\.uniqueIdentifier)
        guard !concealed.isEmpty else { return present }

        let reference = projection.sectionOrder[.visible]
            ?? savedSectionOrder[MenuBarSectionName.visible.rawValue]
            ?? []
        let concealedSet = Set(concealed)
        // Recorded entries first so their relative order survives; identifiers
        // the record has never seen keep a deterministic order.
        let orderedConcealed = reference.filter { concealedSet.contains($0) }
            + concealed.filter { !reference.contains($0) }.sorted()
        return reinsertingConcealed(orderedConcealed, into: present, reference: reference)
    }

    /// Reinserts concealed identifiers into their recorded slots: each goes
    /// after the closest identifier that precedes it in `reference` and
    /// survives in `order`, or at the front when no predecessor survives.
    /// Pure over inputs.
    static func reinsertingConcealed(
        _ concealed: [String],
        into order: [String],
        reference: [String]
    ) -> [String] {
        var result = order
        for identifier in concealed {
            let insertAt: Int
            if let referenceIndex = reference.firstIndex(of: identifier) {
                let predecessor = reference[..<referenceIndex].last { result.contains($0) }
                insertAt = predecessor.flatMap { result.firstIndex(of: $0).map { $0 + 1 } } ?? 0
            } else {
                insertAt = result.count
            }
            result.insert(identifier, at: min(insertAt, result.count))
        }
        return result
    }
}
