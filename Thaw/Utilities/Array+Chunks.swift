//
//  Array+Chunks.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

nonisolated extension Array {
    /// The elements in runs of size, in order; the last run is shorter when
    /// they don't divide evenly.
    func chunks(ofCount size: Int) -> [[Element]] {
        precondition(size > 0, "a chunk holds at least one element")
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
