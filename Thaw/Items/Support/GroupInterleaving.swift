//
//  GroupInterleaving.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Whether the agent's sort weights put another app's item between the members of an app group.
///
/// A permutation of the visible order can leave such an item between a group's members. Respacing the
/// segment rewrites the weights, so the caller only does it when this says the weights are interleaved.
/// The caller reads the weights, so the decision is made from plain values.
nonisolated enum GroupInterleaving {
    /// - Parameters:
    ///   - groups: The identifiers of each group's members.
    ///   - inScope: The identifiers in the order being applied. A group with no member there is not this
    ///     pass's problem, and respacing the visible segment would not help it anyway.
    ///   - weightByIdentifier: The stored weight of each item that has one.
    static func isInterleaved(
        groups: [[String]],
        inScope: Set<String>,
        weightByIdentifier: [String: Int]
    ) -> Bool {
        for group in groups where group.contains(where: inScope.contains) {
            let memberWeights = group.compactMap { weightByIdentifier[$0] }
            // One weighted member has no span for another item to sit inside.
            guard memberWeights.count >= 2,
                  let low = memberWeights.min(),
                  let high = memberWeights.max()
            else {
                continue
            }
            let memberSet = Set(group)
            let interloper = weightByIdentifier.contains { identifier, weight in
                !memberSet.contains(identifier) && weight > low && weight < high
            }
            if interloper {
                return true
            }
        }
        return false
    }
}
