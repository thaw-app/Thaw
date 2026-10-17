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
        func moves(for candidates: [Candidate]) -> [(section: MenuBarSectionName, items: [MenuBarItem])] {
            guard case let .ordered(dividers) = self else { return [] }
            return ObservedMembership.moves(for: candidates, dividers: dividers)
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
        let authored: MenuBarSectionName?
    }

    /// The items to move, grouped by the section they sit in on the bar, in reading order.
    static func moves(
        for candidates: [Candidate],
        dividers: Dividers
    ) -> [(section: MenuBarSectionName, items: [MenuBarItem])] {
        let moving = candidates.compactMap { candidate -> (section: MenuBarSectionName, item: MenuBarItem)? in
            let observed = dividers.section(for: candidate.weight)
            return observed == candidate.authored ? nil : (observed, candidate.item)
        }
        return Dictionary(grouping: moving, by: \.section)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value.map(\.item)) }
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
