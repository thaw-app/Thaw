//
//  ControlItemOcclusion.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ControlItemOcclusion

/// Decides when a control item's window counts as occluded.
///
/// `NSWindow.occlusionState` is the only permission-free way to learn that the
/// menu bar accepted a status item but is not rendering it — the state a
/// control item lands in when macOS parks it in the notch dead zone. Nothing
/// here touches Screen Recording, so it keeps reporting when that grant is
/// refused and the image cache has nothing to say.
///
/// The raw signal cannot be trusted sample for sample. The window server
/// publishes occlusion asynchronously, so a reading taken just after the menu
/// bar reorders still describes the previous layout, and a lid open/close or
/// display reconfiguration briefly reports everything occluded. ``Evaluator``
/// therefore requires consecutive agreeing samples and discards whatever
/// arrives while a display change is still settling.
///
/// Note that `occlusionState` is only unreliable in one direction. AppKit
/// counts a window as visible whenever its bounding box lands in a visible
/// region — even fully transparent ones — so a false *visible* is expected by
/// design. A false *occluded* is the anomaly, which is the reading this type
/// exists to confirm.
nonisolated enum ControlItemOcclusion {
    /// The number of consecutive agreeing samples required before a change of
    /// verdict is reported.
    static let requiredConfirmations = 2

    /// How long after a display change samples are discarded.
    static let displayChangeGrace: TimeInterval = 1.5

    /// A single reading of a control item's occlusion state.
    struct Sample {
        /// Whether the window server currently declines to report the window
        /// as visible.
        let isOccluded: Bool

        /// Whether the status item is in the menu bar at all. A control item
        /// the user switched off is absent, which is not the same as occluded.
        let isInMenuBar: Bool

        /// Seconds elapsed since the last display reconfiguration.
        let secondsSinceDisplayChange: TimeInterval
    }

    /// Folds a stream of ``Sample``s into a debounced verdict.
    struct Evaluator {
        /// The verdict currently being reported.
        private(set) var isOccluded = false

        /// The verdict awaiting confirmation.
        private var candidate: Bool?

        /// How many consecutive samples have agreed with ``candidate``.
        private var agreementCount = 0

        /// Feeds one sample in.
        ///
        /// - Returns: The new verdict when it changes, or `nil` while the
        ///   current verdict stands or the sample was discarded.
        mutating func evaluate(_ sample: Sample) -> Bool? {
            guard sample.isInMenuBar else {
                // Absent items hold no verdict. Clearing the candidate makes
                // a returning item earn its confirmations from scratch.
                reset()
                guard isOccluded else {
                    return nil
                }
                isOccluded = false
                return false
            }

            guard sample.secondsSinceDisplayChange >= ControlItemOcclusion.displayChangeGrace else {
                // Readings taken mid-reconfiguration are noise, so they must
                // not count toward a verdict either.
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
