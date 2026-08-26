//
//  MenuBarItemAttentionDetector.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Decides which menu bar items are asking for attention, from nothing but
/// the sequence of images they have drawn.
///
/// On Linux a tray item can advertise `Status: NeedsAttention`. macOS has no
/// equivalent, so an app that wants to be noticed blinks its icon instead.
/// The problem is that plenty of icons change constantly without wanting
/// anything: a clock, a battery percentage, a download counter, a CPU graph.
///
/// The discriminator is *revisiting*. A blinking icon alternates between a
/// small number of states and keeps returning to ones it has already shown.
/// A clock never shows the same minute twice, a battery percentage walks in
/// one direction, and a CPU graph is novel every frame. So an item counts as
/// seeking attention only when it has changed often, across few distinct
/// states, and has come back to a state it previously left.
///
/// This type is pure: it takes fingerprints and timestamps and returns a
/// verdict. It never captures, moves, or reveals anything, which is what
/// makes it testable without a menu bar.
nonisolated struct MenuBarItemAttentionDetector {
    /// The thresholds a sequence has to clear to count as attention-seeking.
    struct Configuration: Equatable {
        /// How far back the detector looks. Samples older than this are
        /// discarded, so an item that blinked once an hour ago is not still
        /// considered urgent.
        var window: TimeInterval

        /// The minimum number of image changes within ``window``.
        ///
        /// Two changes is a single round trip — a VPN going connecting and
        /// back, a toggle flipping. Three is the first count that cannot be
        /// one there-and-back, which is why the floor sits here rather than
        /// higher: a blink held for two samples each way only clears three
        /// transitions in a six-second window, and it is
        /// ``maximumDistinctStates`` that does the work of rejecting clocks.
        var minimumChanges: Int

        /// The maximum number of distinct images within ``window``.
        ///
        /// This is what rules out clocks and counters: they produce a new
        /// distinct state on every change, so their distinct count tracks
        /// their change count instead of staying flat.
        var maximumDistinctStates: Int

        /// The minimum number of times the item must return to a state it
        /// had already shown.
        var minimumRevisits: Int

        /// Defaults chosen against the common case of a roughly 1 Hz blink
        /// sampled at the cache's refresh rate: two full on/off cycles
        /// inside six seconds.
        static let `default` = Configuration(
            window: 6,
            minimumChanges: 3,
            maximumDistinctStates: 3,
            minimumRevisits: 2
        )
    }

    /// One observation of an item's image.
    private struct Sample {
        let fingerprint: Int
        let timestamp: TimeInterval
    }

    private var configuration: Configuration
    private var samples: [MenuBarItemTag: [Sample]] = [:]

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Records the image an item is currently drawing.
    ///
    /// Repeated identical fingerprints are kept rather than collapsed: the
    /// gap between changes is what separates a slow blink from a fast one,
    /// and dropping duplicates would erase it.
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
    ///   - timestamp: The current time, used to age out stale samples so a
    ///     verdict cannot outlive its evidence.
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
                // A state the item had already shown before this transition
                // is a return, not progress. Novel states are what a clock
                // produces; returns are what a blink produces.
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
