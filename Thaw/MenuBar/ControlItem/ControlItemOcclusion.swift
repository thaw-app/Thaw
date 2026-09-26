//
//  ControlItemOcclusion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ControlItemOcclusion

/// Decides when a control item's window counts as occluded.
///
/// `NSWindow.occlusionState` is the only permission-free way to learn the menu
/// bar accepted a status item but isn't rendering it, as when macOS parks it
/// in the notch dead zone.
///
/// The window server publishes occlusion asynchronously, so a reading right
/// after a reorder describes the old layout, and a lid or display change
/// briefly reports everything occluded. ``Evaluator`` requires consecutive
/// agreeing samples and discards readings while a display change settles.
///
/// A false visible is expected (transparent regions count as visible); a
/// false occluded is the anomaly this type confirms.
nonisolated enum ControlItemOcclusion {
    /// Consecutive agreeing samples required to change the verdict.
    static let requiredConfirmations = 2

    /// How long after a display change samples are discarded.
    static let displayChangeGrace: TimeInterval = 1.5

    /// A single reading of a control item's occlusion state.
    struct Sample {
        /// Whether the window server currently declines to report the window
        /// as visible.
        let isOccluded: Bool

        /// A control item the user switched off is absent, not occluded.
        let isInMenuBar: Bool

        /// Seconds elapsed since the last display reconfiguration.
        let secondsSinceDisplayChange: TimeInterval
    }

    /// Folds a stream of ``Sample``s into a debounced verdict.
    struct Evaluator {
        private(set) var isOccluded = false

        /// The verdict awaiting confirmation.
        private var candidate: Bool?

        /// How many consecutive samples have agreed with ``candidate``.
        private var agreementCount = 0

        /// - Returns: The new verdict when it changes, or `nil` while the
        ///   current verdict stands or the sample was discarded.
        mutating func evaluate(_ sample: Sample) -> Bool? {
            guard sample.isInMenuBar else {
                // A returning item earns its confirmations from scratch.
                reset()
                guard isOccluded else {
                    return nil
                }
                isOccluded = false
                return false
            }

            guard sample.secondsSinceDisplayChange >= ControlItemOcclusion.displayChangeGrace else {
                // Readings mid-reconfiguration are noise.
                reset()
                return nil
            }

            if candidate == sample.isOccluded {
                agreementCount += 1
            } else {
                candidate = sample.isOccluded
                agreementCount = 1
            }

            guard
                agreementCount >= ControlItemOcclusion.requiredConfirmations,
                sample.isOccluded != isOccluded
            else {
                return nil
            }

            isOccluded = sample.isOccluded
            return isOccluded
        }

        /// Discards any pending candidate, leaving the current verdict intact.
        mutating func reset() {
            candidate = nil
            agreementCount = 0
        }
    }
}
