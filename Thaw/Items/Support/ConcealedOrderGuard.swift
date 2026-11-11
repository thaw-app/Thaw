//
//  ConcealedOrderGuard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

/// Keeps a Hidden or Always Hidden order write from moving items of other sections.
///
/// Under Native hiding a section's stored weights interleave with Visible ones, so a re-space of the
/// section can renumber Visible neighbours past a divider. Nothing moves until the next launch, which
/// then reads them as Always Hidden.
nonisolated enum ConcealedOrderGuard {
    /// The table with the write undone, or nil when it changed only the section's own keys.
    static func rollback(
        changed: [String],
        memberKeys: Set<String>,
        before: [String: Int],
        current: [String: Int]
    ) -> [String: Int]? {
        guard changed.contains(where: { !memberKeys.contains($0) }) else { return nil }
        var restored = current
        for key in changed {
            restored[key] = before[key]
        }
        return restored
    }
}
