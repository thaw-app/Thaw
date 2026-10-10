//
//  MenuBarItemGroupPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Keeps groups contiguous and repairs section splits at layout writes, so planners need only identifiers.
/// Gathering preserves every identifier and is idempotent, preventing item loss and repeated writes.
public enum MenuBarItemGroupPolicy {
    // MARK: - GroupSet

    /// Live groups use ordered string identifiers so pure planners never need tags.
    public struct GroupSet: Equatable, Sendable {
        /// Groups with fewer than two members are dropped on construction.
        public let groups: [[String]]

        private let indexByIdentifier: [String: Int]

        public static let empty = GroupSet(groups: [])

        public init(groups: [[String]]) {
            var kept = [[String]]()
            var index = [String: Int]()
            for members in groups {
                // Each identifier belongs to one group; first wins, matching MenuBarItemGroupSet.normalized().
                let unclaimed = members.filter { index[$0] == nil }
                guard unclaimed.count >= 2 else { continue }
                for member in unclaimed {
                    index[member] = kept.count
                }
                kept.append(unclaimed)
            }
            self.groups = kept
            indexByIdentifier = index
        }

        public var isEmpty: Bool {
            groups.isEmpty
        }

        /// The index of the group owning identifier, if any.
        public func groupIndex(of identifier: String) -> Int? {
            indexByIdentifier[identifier]
        }

        public func members(ofGroup index: Int) -> [String] {
            groups.indices.contains(index) ? groups[index] : []
        }
    }

    // MARK: - Report

    /// Callers log the report to keep planners pure and nonisolated for tests.
    /// An empty report means no write occurred.
    public struct CanonicalizationReport: Equatable, Sendable {
        /// Identifiers whose position changed.
        public var movedIdentifiers: [String]
        /// Indices of groups that were scattered and have been gathered.
        public var gatheredGroups: [Int]
        /// Groups that were split across sections, and where they were repaired to.
        public var repairedGroups: [SectionRepair]

        public init(
            movedIdentifiers: [String] = [],
            gatheredGroups: [Int] = [],
            repairedGroups: [SectionRepair] = []
        ) {
            self.movedIdentifiers = movedIdentifiers
            self.gatheredGroups = gatheredGroups
            self.repairedGroups = repairedGroups
        }

        public var didChange: Bool {
            !movedIdentifiers.isEmpty || !repairedGroups.isEmpty
        }

        public static let noChange = CanonicalizationReport()
    }

    /// Records a split group's original sections and its consolidated destination.
    public struct SectionRepair: Equatable, Sendable {
        public let groupIndex: Int
        public let from: [MenuBarSectionName]
        public let to: MenuBarSectionName

        public init(groupIndex: Int, from: [MenuBarSectionName], to: MenuBarSectionName) {
            self.groupIndex = groupIndex
            self.from = from
            self.to = to
        }
    }

    // MARK: - Contiguity within one order

    /// Gathers each group at its leftmost member, preserving relative order within groups and among non-members.
    /// Ungrouped identifiers and absent group members are left alone.
    public static func gather(
        groups: GroupSet,
        in order: [String]
    ) -> (order: [String], report: CanonicalizationReport) {
        guard !groups.isEmpty, !order.isEmpty else {
            return (order, .noChange)
        }

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
                // Keep members' relative order at the leftmost member's slot.
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

    /// Returns scattered group indices; empty means canonical.
    /// Used by tests and the post-commit debug assertion.
    public static func scattered(groups: GroupSet, in order: [String]) -> [Int] {
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
    public static func split(
        groups: GroupSet,
        inSections sections: [MenuBarSectionName: [String]]
    ) -> [Int] {
        sectionsByGroup(groups: groups, inSections: sections)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
    }

    /// Consolidates split groups into the sole feasible occupied section, otherwise the one with most members.
    /// Ties favor visibility to avoid concealing items, especially when macOS 27's always-hidden reveal is disabled.
    /// - Parameter gatheringWithin: Sections whose internal order may be rewritten; membership is always repaired.
    ///   On macOS 27, visible order mirrors live AX geometry and must not be rewritten from persisted state.
    public static func gather(
        groups: GroupSet,
        inSections sections: [MenuBarSectionName: [String]],
        gatheringWithin: Set<MenuBarSectionName> = Set(MenuBarSectionName.allCases),
        isFeasible: (Int, MenuBarSectionName) -> Bool = { _, _ in true }
    ) -> (sections: [MenuBarSectionName: [String]], report: CanonicalizationReport) {
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

            for section in sectionCounts.keys where section != winner {
                result[section]?.removeAll { members.contains($0) }
                if result[section]?.isEmpty == true {
                    result.removeValue(forKey: section)
                }
            }
            var winnerOrder = result[winner] ?? []
            let present = Set(winnerOrder)
            let missing = groups.members(ofGroup: group).filter { !present.contains($0) }
            // Insert arrivals after the last member to preserve existing order without splitting the run.
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
        inSections sections: [MenuBarSectionName: [String]]
    ) -> [Int: [MenuBarSectionName: Int]] {
        var occupied = [Int: [MenuBarSectionName: Int]]()
        for (section, order) in sections {
            for identifier in order {
                guard let group = groups.groupIndex(of: identifier) else { continue }
                occupied[group, default: [:]][section, default: 0] += 1
            }
        }
        return occupied
    }

    /// Higher is more visible. Used only to break a tie.
    private static func visibilityRank(_ section: MenuBarSectionName) -> Int {
        switch section {
        case .visible: 2
        case .hidden: 1
        case .alwaysHidden: 0
        }
    }

    private static func winningSection(
        group: Int,
        sectionCounts: [MenuBarSectionName: Int],
        isFeasible: (Int, MenuBarSectionName) -> Bool
    ) -> MenuBarSectionName {
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
