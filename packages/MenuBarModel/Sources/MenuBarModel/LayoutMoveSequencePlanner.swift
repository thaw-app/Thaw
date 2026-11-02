//
//  LayoutMoveSequencePlanner.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Diffs a live item order against a desired one and emits only the moves
/// that change something, so a reapply drags the minimal set. Pure over
/// MenuBarItem.uniqueIdentifier sequences (dividers removed) and persisted
/// section keys.
public enum LayoutMoveSequencePlanner {
    /// Anchors by UID, since the orchestrator re-fetches live items between
    /// moves and resolves the UID then.
    public enum LCSPlannedDestination: Equatable, Sendable {
        case leftOfUID(String)
        case rightOfUID(String)
        case sectionBoundary(MenuBarSectionName)
    }

    public struct LCSPlannedMove: Equatable, Sendable {
        public let uid: String
        public let destination: LCSPlannedDestination

        public init(uid: String, destination: LCSPlannedDestination) {
            self.uid = uid
            self.destination = destination
        }
    }

    /// Each item outside the LCS is anchored to a stable item in its section,
    /// scanning forward, then backward, then falling back to the section
    /// boundary. Items planned earlier in the sequence count as stable.
    ///
    /// - Parameters:
    ///   - currentNoControls: The live order, left to right, without dividers.
    ///   - desiredNoControls: The wanted order. Items not in currentNoControls
    ///     are ignored.
    ///   - sectionMap: Persisted section key per UID. Unknown UIDs count as
    ///     visible.
    ///   - unanchorableUIDs: UIDs that stay in the sequence but are never
    ///     anchors: Thaw's own control items.
    ///   - preferredMoveUIDs: Preferred movers when subsequences tie: newly
    ///     arrived items, so an established item is not displaced.
    public static nonisolated func planLCSMoveSequence(
        currentNoControls: [String],
        desiredNoControls: [String],
        sectionMap: [String: String],
        unanchorableUIDs: Set<String> = [],
        preferredMoveUIDs: Set<String> = []
    ) -> [LCSPlannedMove] {
        let currentSetNow = Set(currentNoControls)
        let desiredSetNow = Set(desiredNoControls)
        let lcsCurrent = currentNoControls.filter { desiredSetNow.contains($0) }
        let lcsDesired = desiredNoControls.filter { currentSetNow.contains($0) }

        let lcsItems = longestCommonSubsequence(
            lcsCurrent,
            lcsDesired,
            preferredMoveUIDs: preferredMoveUIDs
        )
        let itemsToMove = lcsDesired.filter { !lcsItems.contains($0) }

        if itemsToMove.isEmpty {
            return []
        }

        var movedItems = Set<String>()
        var result = [LCSPlannedMove]()

        for uid in itemsToMove {
            guard let desiredIdx = lcsDesired.firstIndex(of: uid) else {
                continue
            }
            let targetKey = sectionMap[uid] ?? "visible"

            var destination: LCSPlannedDestination?

            // Never anchor on a divider: a failed move anchored on one shoves
            // it left, eventually leaving a zero-width hidden section.
            for scanIdx in (desiredIdx + 1) ..< lcsDesired.count {
                let candidateUID = lcsDesired[scanIdx]
                let candidateKey = sectionMap[candidateUID] ?? "visible"
                guard candidateKey == targetKey else { break }
                if unanchorableUIDs.contains(candidateUID) {
                    continue
                }
                if lcsItems.contains(candidateUID) || movedItems.contains(candidateUID) {
                    destination = .leftOfUID(candidateUID)
                    break
                }
            }

            if destination == nil, desiredIdx > 0 {
                for scanIdx in stride(from: desiredIdx - 1, through: 0, by: -1) {
                    let candidateUID = lcsDesired[scanIdx]
                    let candidateKey = sectionMap[candidateUID] ?? "visible"
                    guard candidateKey == targetKey else { break }
                    if unanchorableUIDs.contains(candidateUID) {
                        continue
                    }
                    if lcsItems.contains(candidateUID) || movedItems.contains(candidateUID) {
                        destination = .rightOfUID(candidateUID)
                        break
                    }
                }
            }

            if destination == nil {
                let targetSection: MenuBarSectionName = switch targetKey {
                case "hidden": .hidden
                case "alwaysHidden": .alwaysHidden
                default: .visible
                }
                destination = .sectionBoundary(targetSection)
            }

            if let destination {
                result.append(LCSPlannedMove(uid: uid, destination: destination))
                movedItems.insert(uid)
            }
        }
        return result
    }

    /// The items that keep their relative order in both arrays and need no move.
    public static nonisolated func longestCommonSubsequence(
        _ a: [String],
        _ b: [String],
        preferredMoveUIDs: Set<String> = []
    ) -> Set<String> {
        let m = a.count
        let n = b.count
        guard m > 0, n > 0 else { return [] }

        struct Score: Comparable {
            let establishedCount: Int
            let totalCount: Int

            static func < (lhs: Self, rhs: Self) -> Bool {
                if lhs.totalCount != rhs.totalCount {
                    return lhs.totalCount < rhs.totalCount
                }
                return lhs.establishedCount < rhs.establishedCount
            }

            func adding(isEstablished: Bool) -> Self {
                Score(
                    establishedCount: establishedCount + (isEstablished ? 1 : 0),
                    totalCount: totalCount + 1
                )
            }
        }

        // Longest first, then most established items, so a tie makes the
        // new arrival the mover.
        let zero = Score(establishedCount: 0, totalCount: 0)
        var dp = Array(repeating: Array(repeating: zero, count: n + 1), count: m + 1)
        for i in 1 ... m {
            for j in 1 ... n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1].adding(
                        isEstablished: !preferredMoveUIDs.contains(a[i - 1])
                    )
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find the LCS items.
        var result = Set<String>()
        var i = m
        var j = n
        while i > 0, j > 0 {
            if a[i - 1] == b[j - 1] {
                result.insert(a[i - 1])
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result
    }
}
