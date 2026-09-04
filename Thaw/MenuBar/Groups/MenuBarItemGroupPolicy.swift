//
//  MenuBarItemGroupPolicy.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Canonicalizes identifier orders so a group's members stay contiguous, and
/// repairs orders where a group has been split across sections.
///
/// This is the invariant half of grouping. ``MenuBarItemGroupResolver`` answers
/// *what* the groups are; this type answers *what a valid order looks like* and
/// is applied at the few chokepoints that write layout state, so the planners
/// downstream can stay identifier-only and group-unaware.
///
/// Two properties make it safe to run on every write, and both are covered by
/// tests rather than by comment:
///
/// - **Permutation.** `gather` never drops or invents an identifier. That is
///   what makes it impossible for canonicalization to silently lose an item.
/// - **Idempotence.** Gathering an already-canonical order changes nothing, so
///   re-running each cycle produces no write and cannot start a write storm.
nonisolated enum MenuBarItemGroupPolicy {
    // MARK: - GroupSet

    /// Groups resolved against a live item set, as ordered member identifier
    /// lists. Deliberately plain strings so the pure planners never need tags.
    struct GroupSet: Equatable, Sendable {
        /// Member identifiers per group. A group with fewer than two members is
        /// not a group and is dropped on construction.
        let groups: [[String]]

        private let indexByIdentifier: [String: Int]

        static let empty = GroupSet(groups: [])

        init(groups: [[String]]) {
            var kept = [[String]]()
            var index = [String: Int]()
            for members in groups {
                // An identifier can only belong to one group; first wins, the
                // same tie-break `MenuBarItemGroupSet.normalized()` uses. A
                // repeat within one group is claimed once as well, or `gather`
                // would emit it twice and stop being a permutation.
                var seen = Set<String>()
                let unclaimed = members.filter { index[$0] == nil && seen.insert($0).inserted }
                guard unclaimed.count >= 2 else { continue }
                for member in unclaimed {
                    index[member] = kept.count
                }
                kept.append(unclaimed)
            }
            self.groups = kept
            indexByIdentifier = index
        }

        var isEmpty: Bool {
            groups.isEmpty
        }

        /// The index of the group owning `identifier`, if any.
        func groupIndex(of identifier: String) -> Int? {
            indexByIdentifier[identifier]
        }

        func members(ofGroup index: Int) -> [String] {
            groups.indices.contains(index) ? groups[index] : []
        }
    }

    // MARK: - Report

    /// What a canonicalization pass actually did.
    ///
    /// Returned rather than logged: the planners this feeds are pure and
    /// `nonisolated`, and their purity is load-bearing for their tests. Callers
    /// log it. A pass that reports nothing performed no write.
    struct CanonicalizationReport: Equatable, Sendable {
        /// Identifiers whose position changed.
        var movedIdentifiers: [String]
        /// Indices of groups that were scattered and have been gathered.
        var gatheredGroups: [Int]
        /// Groups that were split across sections, and where they were repaired to.
        var repairedGroups: [SectionRepair]

        init(
            movedIdentifiers: [String] = [],
            gatheredGroups: [Int] = [],
            repairedGroups: [SectionRepair] = []
        ) {
            self.movedIdentifiers = movedIdentifiers
            self.gatheredGroups = gatheredGroups
            self.repairedGroups = repairedGroups
        }

        var didChange: Bool {
            !movedIdentifiers.isEmpty || !repairedGroups.isEmpty
        }

        static let noChange = CanonicalizationReport()
    }

    /// A group that was found spanning more than one section, and the section
    /// every member was consolidated into.
    struct SectionRepair: Equatable, Sendable {
        let groupIndex: Int
        let from: [MenuBarSection.Name]
        let to: MenuBarSection.Name

        init(groupIndex: Int, from: [MenuBarSection.Name], to: MenuBarSection.Name) {
            self.groupIndex = groupIndex
            self.from = from
            self.to = to
        }
    }

    // MARK: - Contiguity within one order

    /// Reorders `order` so every group's members sit in one contiguous run,
    /// anchored at the position of the group's leftmost member.
    ///
    /// Members keep their **current** relative order — gathering never silently
    /// reorders within a group — and non-members keep theirs. Identifiers that
    /// belong to no group, and group members absent from `order`, are left
    /// entirely alone.
    static func gather(
        groups: GroupSet,
        in order: [String]
    ) -> (order: [String], report: CanonicalizationReport) {
        guard !groups.isEmpty, !order.isEmpty else {
            return (order, .noChange)
        }

        // Current positions of each group's members, in order of appearance.
        var memberPositions = [Int: [Int]](minimumCapacity: groups.groups.count)
        for (position, identifier) in order.enumerated() {
            guard let group = groups.groupIndex(of: identifier) else { continue }
            memberPositions[group, default: []].append(position)
        }

        var gathered = [Int]()
        var anchors = [Int: Int]()
        for (group, positions) in memberPositions {
            guard let anchor = positions.first, positions.count >= 2 else { continue }
            anchors[anchor] = group
            // Contiguous already when the span equals the member count.
            if let last = positions.last, last - anchor + 1 != positions.count {
                gathered.append(group)
            }
        }
        guard !gathered.isEmpty else {
            return (order, .noChange)
        }

        var result = [String]()
        result.reserveCapacity(order.count)
        for (position, identifier) in order.enumerated() {
            if let group = anchors[position] {
                // Emit the whole group at its leftmost member's slot, in the
                // members' existing relative order.
                for memberPosition in memberPositions[group] ?? [] {
                    result.append(order[memberPosition])
                }
                continue
            }
            // A member that is not its group's anchor was already emitted.
            if let group = groups.groupIndex(of: identifier),
               memberPositions[group]?.count ?? 0 >= 2
            {
                continue
            }
            result.append(identifier)
        }

        var moved = [String]()
        for (position, identifier) in result.enumerated() where order.indices.contains(position) {
            if order[position] != identifier {
                moved.append(identifier)
            }
        }

        return (
            result,
            CanonicalizationReport(movedIdentifiers: moved, gatheredGroups: gathered.sorted())
        )
    }

    /// Indices of groups whose members are present but not contiguous in
    /// `order`. Empty means the order is canonical. Used by tests and by a
    /// debug-build assertion after a commit.
    static func scattered(groups: GroupSet, in order: [String]) -> [Int] {
        var positions = [Int: [Int]]()
        for (position, identifier) in order.enumerated() {
            guard let group = groups.groupIndex(of: identifier) else { continue }
            positions[group, default: []].append(position)
        }
        return positions
            .filter { _, value in
                guard let first = value.first, let last = value.last, value.count >= 2 else {
                    return false
                }
                return last - first + 1 != value.count
            }
            .keys
            .sorted()
    }

    // MARK: - Section membership

    /// Indices of groups whose members are spread across more than one section.
    /// Empty means the sections are healthy.
    static func split(
        groups: GroupSet,
        inSections sections: [MenuBarSection.Name: [String]]
    ) -> [Int] {
        sectionsByGroup(groups: groups, inSections: sections)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
    }

    /// Consolidates every split group into a single section, then gathers each
    /// section's order.
    ///
    /// Winner selection is deterministic:
    /// 1. if the group is feasible in only one of the sections it occupies, that one;
    /// 2. otherwise the section holding the most members;
    /// 3. ties break toward the **most visible** section.
    ///
    /// Rule 3 matters: repairing toward visibility can never make an item
    /// unreachable, whereas repairing toward always-hidden could conceal
    /// something the user never asked to conceal — and on macOS 27 the
    /// always-hidden reveal gesture may not even be enabled.
    /// - Parameter gatheringWithin: sections whose *internal* order may be
    ///   rewritten to make groups contiguous. Membership is repaired for every
    ///   section regardless; this only controls the reordering step, because on
    ///   macOS 27 the visible order mirrors live AX geometry and must not be
    ///   rewritten from persisted state.
    static func gather(
        groups: GroupSet,
        inSections sections: [MenuBarSection.Name: [String]],
        gatheringWithin: Set<MenuBarSection.Name> = Set(MenuBarSection.Name.allCases),
        isFeasible: (Int, MenuBarSection.Name) -> Bool = { _, _ in true }
    ) -> (sections: [MenuBarSection.Name: [String]], report: CanonicalizationReport) {
        var result = sections
        var report = CanonicalizationReport()

        let occupied = sectionsByGroup(groups: groups, inSections: sections)
        for (group, sectionCounts) in occupied.sorted(by: { $0.key < $1.key }) where sectionCounts.count > 1 {
            let winner = winningSection(
                group: group,
                sectionCounts: sectionCounts,
                isFeasible: isFeasible
            )
            let members = Set(groups.members(ofGroup: group))

            // Pull every member out of the losing sections, then splice the
            // whole group into the winner at its first member's position.
            for section in sectionCounts.keys where section != winner {
                result[section]?.removeAll { members.contains($0) }
                if result[section]?.isEmpty == true {
                    result.removeValue(forKey: section)
                }
            }
            var winnerOrder = result[winner] ?? []
            let present = Set(winnerOrder)
            let missing = groups.members(ofGroup: group).filter { !present.contains($0) }
            // Splice the newcomers in after the last member already here, so the
            // members that stayed keep their relative order and the arrivals
            // land together behind them. Inserting after the *first* member
            // would drop them into the middle of the run instead.
            if let tail = winnerOrder.lastIndex(where: { members.contains($0) }) {
                winnerOrder.insert(contentsOf: missing, at: tail + 1)
            } else {
                winnerOrder.append(contentsOf: missing)
            }
            result[winner] = winnerOrder

            report.movedIdentifiers.append(contentsOf: missing)
            report.repairedGroups.append(
                SectionRepair(
                    groupIndex: group,
                    from: sectionCounts.keys.sorted { $0.rawValue < $1.rawValue },
                    to: winner
                )
            )
        }

        // Then make every eligible section's order contiguous.
        for (section, order) in result where gatheringWithin.contains(section) {
            let gathered = gather(groups: groups, in: order)
            guard gathered.report.didChange else { continue }
            result[section] = gathered.order
            report.movedIdentifiers.append(contentsOf: gathered.report.movedIdentifiers)
            report.gatheredGroups.append(contentsOf: gathered.report.gatheredGroups)
        }
        report.gatheredGroups = Array(Set(report.gatheredGroups)).sorted()

        return (result, report)
    }

    // MARK: - Helpers

    /// Member counts per section, per group, for groups present at all.
    private static func sectionsByGroup(
        groups: GroupSet,
        inSections sections: [MenuBarSection.Name: [String]]
    ) -> [Int: [MenuBarSection.Name: Int]] {
        var occupied = [Int: [MenuBarSection.Name: Int]]()
        for (section, order) in sections {
            for identifier in order {
                guard let group = groups.groupIndex(of: identifier) else { continue }
                occupied[group, default: [:]][section, default: 0] += 1
            }
        }
        return occupied
    }

    /// Higher is more visible. Used only to break a tie.
    private static func visibilityRank(_ section: MenuBarSection.Name) -> Int {
        switch section {
        case .visible: 2
        case .hidden: 1
        case .alwaysHidden: 0
        }
    }

    private static func winningSection(
        group: Int,
        sectionCounts: [MenuBarSection.Name: Int],
        isFeasible: (Int, MenuBarSection.Name) -> Bool
    ) -> MenuBarSection.Name {
        let feasible = sectionCounts.keys.filter { isFeasible(group, $0) }
        let candidates = feasible.count == 1 ? feasible : Array(sectionCounts.keys)
        return candidates.max { lhs, rhs in
            let lhsCount = sectionCounts[lhs] ?? 0
            let rhsCount = sectionCounts[rhs] ?? 0
            if lhsCount != rhsCount {
                return lhsCount < rhsCount
            }
            return visibilityRank(lhs) < visibilityRank(rhs)
        } ?? .visible
    }
}
