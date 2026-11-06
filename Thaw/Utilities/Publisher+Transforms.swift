//
//  Publisher+Transforms.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine

extension Publisher {
    /// Publishes the given element in place of each element received from
    /// upstream.
    ///
    /// - Parameter output: The element to publish downstream.
    func replace<T>(with output: T) -> Publishers.Map<Self, T> {
        map { _ in output }
    }

    /// Drops the nil elements and publishes the rest unwrapped.
    func removeNil<T>() -> Publishers.CompactMap<Self, T> where Output == T? {
        compactMap(\.self)
    }

    /// Drops elements that equal the element published before them, for
    /// outputs that are tuples of equatable values.
    func removeDuplicates<each T: Equatable>() -> Publishers.RemoveDuplicates<Self> where Output == (repeat each T) {
        removeDuplicates { lhs, rhs in
            for (left, right) in repeat (each lhs, each rhs) {
                // Pack iteration does not support where clauses.
                // swiftlint:disable:next for_where
                if left != right {
                    return false
                }
            }
            return true
        }
    }
}
