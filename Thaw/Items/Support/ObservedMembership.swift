//
//  ObservedMembership.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Which items a reading of the position table says sit in another section than Thaw has them in.
nonisolated enum ObservedMembership {
    /// The three weights sections are read against, accepted only in their real order.
    struct Dividers: Equatable {
        let hidden: Int
        let alwaysHidden: Int?
        let visibleControl: Int

        /// Nil when the dividers are out of order, since every item past a misplaced divider would read as its section.
        init?(hidden: Int, alwaysHidden: Int?, visibleControl: Int) {
            guard StoredWeights.dividersAreOrdered(
                hiddenDivider: hidden,
                alwaysHiddenDivider: alwaysHidden,
                visibleControl: visibleControl
            ) else { return nil }
            self.hidden = hidden
            self.alwaysHidden = alwaysHidden
            self.visibleControl = visibleControl
        }

        func section(for weight: Int) -> MenuBarSectionName {
            StoredWeights.observedSection(
                weight: weight,
                hiddenDivider: hidden,
                alwaysHiddenDivider: alwaysHidden,
                visibleControl: visibleControl
            )
        }
    }

    enum DividerReading: Equatable {
        case unavailable
        case outOfOrder
        case ordered(Dividers)

        /// Nothing moves on a reading that can't be trusted.
        func moves(
            for candidates: [Candidate],
            keepingAuthored: Bool = false,
            since baseline: DragBaseline? = nil,
            alwaysHiddenShownAtDrop: Bool? = nil
        ) -> [(section: MenuBarSectionName, items: [MenuBarItem])] {
            guard case let .ordered(dividers) = self else { return [] }
            return ObservedMembership.moves(
                for: candidates,
                dividers: dividers,
                keepingAuthored: keepingAuthored,
                since: baseline,
                alwaysHiddenShownAtDrop: alwaysHiddenShownAtDrop
            )
        }
    }

    /// Reads the divider weights, ignoring the Always Hidden one while that section is off.
    static func readDividers(
        visibleControl: Int?,
        hidden: Int?,
        alwaysHidden: Int?,
        alwaysHiddenEnabled: Bool
    ) -> DividerReading {
        guard let visibleControl, let hidden else { return .unavailable }
        guard let dividers = Dividers(
            hidden: hidden,
            alwaysHidden: alwaysHiddenEnabled ? alwaysHidden : nil,
            visibleControl: visibleControl
        ) else { return .outOfOrder }
        return .ordered(dividers)
    }

    /// The divider weights as the table holds them, before any order check.
    struct DividerWeights {
        let visibleControl: Int?
        let hidden: Int?
        let alwaysHidden: Int?

        /// The cache keeps the Visible control but drops both dividers, so those come from the pair.
        @MainActor
        init(among items: [MenuBarItem], dividers: ControlItemPair?, weight: (MenuBarItem) -> Int?) {
            visibleControl = items.first { $0.tag.matchesVisibleControlItem }.flatMap(weight)
            hidden = (dividers?.hidden).flatMap(weight)
            alwaysHidden = (dividers?.alwaysHidden).flatMap(weight)
        }

        func reading(alwaysHiddenEnabled: Bool) -> DividerReading {
            readDividers(
                visibleControl: visibleControl,
                hidden: hidden,
                alwaysHidden: alwaysHidden,
                alwaysHiddenEnabled: alwaysHiddenEnabled
            )
        }

        var logString: String {
            "visible \(visibleControl ?? 0), hidden \(hidden ?? 0), always hidden \(alwaysHidden.map(String.init) ?? "none")"
        }
    }

    struct Candidate {
        let item: MenuBarItem
        let weight: Int
        /// The section the user put the item in, or nil when they never placed it, which shows it in Visible.
        let authored: MenuBarSectionName?
    }

    /// The items a reading may move, each with the section the user explicitly put it in.
    ///
    /// - Parameters:
    ///   - weight: The item's stored weight, or nil when it has none or is parked.
    ///   - assignment: The explicit assignments, keyed by canonical identifier. An item
    ///     missing from it has no section yet, even though it shows in Visible.
    ///   - isEligible: Whether the item may move at all.
    static func candidates(
        among items: [MenuBarItem],
        weight: (MenuBarItem) -> Int?,
        assignment: [String: MenuBarSectionName],
        isEligible: (MenuBarItem) -> Bool
    ) -> [Candidate] {
        items.compactMap { item in
            guard isEligible(item), let itemWeight = weight(item) else { return nil }
            let authored = assignment[MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)]
            return Candidate(item: item, weight: itemWeight, authored: authored)
        }
    }

    /// Each item's stored weight, and the section it read as, when a ⌘-drag started.
    ///
    /// Items that are concealed keep weights that can be long out of date, and
    /// MenuBarAgent saves every row on the bar again when a drag ends, which can
    /// move the dividers' weights past those stale ones. An item the drag moved
    /// has a new weight that reads as another section than before: the dragged
    /// item, or an item on the bar that a dragged divider passed.
    struct DragBaseline {
        private let readings: [String: (weight: Int, section: MenuBarSectionName)]

        init(candidates: [Candidate], dividers: Dividers) {
            var readings = [String: (weight: Int, section: MenuBarSectionName)]()
            for candidate in candidates {
                readings[Self.key(for: candidate.item)] = (candidate.weight, dividers.section(for: candidate.weight))
            }
            self.readings = readings
        }

        /// Whether the drag gave candidate a new weight that reads as another
        /// section. An item the baseline never saw did not take part in the drag.
        func crossedDivider(_ candidate: Candidate, dividers: Dividers) -> Bool {
            guard let before = readings[Self.key(for: candidate.item)] else { return false }
            return before.weight != candidate.weight && before.section != dividers.section(for: candidate.weight)
        }

        private static func key(for item: MenuBarItem) -> String {
            MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
        }
    }

    /// The items to move, grouped by the section they sit in on the bar, in reading order.
    /// keepingAuthored leaves every item that already has a section alone, and only
    /// places the ones that have none: in Manual the stored weights go stale, and
    /// Layout's sections win over them. A baseline limits the moves to the items
    /// a ⌘-drag carried across a divider. If Always Hidden was concealed at the
    /// drop, a weight past its divider counts as Hidden. Nil leaves non-drag
    /// readings unchanged.
    static func moves(
        for candidates: [Candidate],
        dividers: Dividers,
        keepingAuthored: Bool = false,
        since baseline: DragBaseline? = nil,
        alwaysHiddenShownAtDrop: Bool? = nil
    ) -> [(section: MenuBarSectionName, items: [MenuBarItem])] {
        let moving = candidates.compactMap { candidate -> (section: MenuBarSectionName, item: MenuBarItem)? in
            if keepingAuthored, candidate.authored != nil {
                return nil
            }
            if let baseline, !baseline.crossedDivider(candidate, dividers: dividers) {
                return nil
            }
            // An Always Hidden icon was not on screen, so the drag cannot have carried it.
            if alwaysHiddenShownAtDrop == false, candidate.authored == .alwaysHidden {
                return nil
            }
            let observed = observedSection(
                for: candidate, dividers: dividers, alwaysHiddenShownAtDrop: alwaysHiddenShownAtDrop
            )
            return observed == (candidate.authored ?? .visible) ? nil : (observed, candidate.item)
        }
        return Dictionary(grouping: moving, by: \.section)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value.map(\.item)) }
    }

    /// A weight past the Always Hidden divider reads as Hidden while that section was concealed at the drop.
    private static func observedSection(
        for candidate: Candidate,
        dividers: Dividers,
        alwaysHiddenShownAtDrop: Bool?
    ) -> MenuBarSectionName {
        let observed = dividers.section(for: candidate.weight)
        guard alwaysHiddenShownAtDrop == false, observed == .alwaysHidden else { return observed }
        return .hidden
    }
}

extension ObservedMembership {
    /// The live items' stored weights and the dividers they read as, taking the dividers from the pair when the cache dropped them.
    /// Nil when the table can't be read, or the dividers are missing or out of order.
    @MainActor
    static func storedReading(
        liveItems: [MenuBarItem],
        dividers: ControlItemPair?,
        table: StoredWeights.Table = .read()
    ) -> (dividers: Dividers, weights: StoredWeights, items: [MenuBarItem])? {
        guard let (pair, items) = ControlOrderRules.withDividers(liveItems, dividers) else { return nil }
        let weights = StoredWeights(among: items, table: table)
        guard weights.isAvailable else { return nil }
        let reading = DividerWeights(among: items, dividers: pair, weight: weights.weight(of:))
            .reading(alwaysHiddenEnabled: pair.alwaysHidden != nil)
        guard case let .ordered(ordered) = reading else { return nil }
        return (ordered, weights, items)
    }
}
