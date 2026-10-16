//
//  MenuBarItemAttentionDetector.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Decides which menu bar items are asking for attention, from nothing but
/// the sequence of images they have drawn.
///
/// macOS has no attention status, so apps blink their icons instead. Clocks,
/// battery levels, and CPU graphs change constantly too, so the signal is
/// revisiting: an item counts only when it changed often, across few distinct
/// states, and returned to a state it had left.
///
/// Pure, so it is testable without a menu bar.
nonisolated struct MenuBarItemAttentionDetector {
    /// The thresholds a sequence has to clear to count as attention-seeking.
    struct Configuration: Equatable {
        /// How far back the detector looks.
        var window: TimeInterval

        /// The minimum number of image changes within ``window``.
        ///
        /// Three is the first count that can't be one round trip. Higher
        /// would miss a slow blink; ``maximumDistinctStates`` rejects clocks.
        var minimumChanges: Int

        /// The maximum number of distinct images within ``window``.
        ///
        /// Rules out clocks and counters, which show a new state on every
        /// change.
        var maximumDistinctStates: Int

        /// The minimum number of times the item must return to a state it
        /// had already shown.
        var minimumRevisits: Int

        /// Tuned for a roughly 1 Hz blink: two on/off cycles in six seconds.
        static let standard = Configuration(
            window: 6,
            minimumChanges: 3,
            maximumDistinctStates: 3,
            minimumRevisits: 2
        )
    }

    private struct Sample {
        let fingerprint: Int
        let timestamp: TimeInterval
    }

    private var configuration: Configuration
    private var samples: [MenuBarItemTag: [Sample]] = [:]

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    /// Records the image an item is currently drawing.
    ///
    /// Identical fingerprints are kept, since the gap between changes
    /// separates a slow blink from a fast one.
    ///
    /// - Parameters:
    ///   - fingerprint: A value that differs when the image differs.
    ///   - tag: The item that drew it.
    ///   - timestamp: When it was observed.
    mutating func record(fingerprint: Int, for tag: MenuBarItemTag, at timestamp: TimeInterval) {
        var itemSamples = samples[tag] ?? []
        itemSamples.append(Sample(fingerprint: fingerprint, timestamp: timestamp))
        itemSamples.removeAll { timestamp - $0.timestamp > configuration.window }
        samples[tag] = itemSamples
    }

    /// Returns whether the item is currently asking for attention.
    ///
    /// - Parameters:
    ///   - tag: The item to judge.
    ///   - timestamp: The current time, used to age out stale samples.
    func isSeekingAttention(_ tag: MenuBarItemTag, at timestamp: TimeInterval) -> Bool {
        guard let itemSamples = samples[tag] else { return false }
        let fresh = itemSamples.filter { timestamp - $0.timestamp <= configuration.window }
        guard fresh.count >= 2 else { return false }

        var changes = 0
        var revisits = 0
        var seen: Set<Int> = []
        var previous: Int?

        for sample in fresh {
            if let previous, previous != sample.fingerprint {
                changes += 1
                // A return to a known state is a blink; novel states are a
                // clock.
                if seen.contains(sample.fingerprint) {
                    revisits += 1
                }
            }
            if let previous {
                seen.insert(previous)
            }
            previous = sample.fingerprint
        }

        let distinct = Set(fresh.map(\.fingerprint)).count
        return changes >= configuration.minimumChanges
            && distinct <= configuration.maximumDistinctStates
            && revisits >= configuration.minimumRevisits
    }

    /// Drops everything recorded for an item, so a surfaced item does not
    /// immediately re-trigger on the history that surfaced it.
    mutating func reset(_ tag: MenuBarItemTag) {
        samples[tag] = nil
    }

    /// Drops history for items that are no longer on the bar.
    mutating func retain(_ tags: Set<MenuBarItemTag>) {
        samples = samples.filter { tags.contains($0.key) }
    }
}
