//
//  MenuBarItemAttentionDetectorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar item attention detector")
struct MenuBarItemAttentionDetectorTests {
    private let tag = MenuBarItemTag(namespace: .string("com.example.app"), title: "Status")
    private let other = MenuBarItemTag(namespace: .string("com.example.other"), title: "Status")

    /// Feeds a fingerprint sequence at a fixed cadence and returns the verdict
    /// at the moment the last sample landed.
    private func verdict(
        _ fingerprints: [Int],
        interval: TimeInterval = 0.5,
        configuration: MenuBarItemAttentionDetector.Configuration = .standard
    ) -> Bool {
        var detector = MenuBarItemAttentionDetector(configuration: configuration)
        var now: TimeInterval = 0
        for fingerprint in fingerprints {
            detector.record(fingerprint: fingerprint, for: tag, at: now)
            now += interval
        }
        return detector.isSeekingAttention(tag, at: now - interval)
    }

    // MARK: Attention-seeking

    @Test("A two-state blink is attention-seeking")
    func blinkIsDetected() {
        #expect(verdict([1, 0, 1, 0, 1, 0]))
    }

    @Test("A blink that holds each state for two samples is still detected")
    func slowBlinkIsDetected() {
        #expect(verdict([1, 1, 0, 0, 1, 1, 0, 0], interval: 0.25))
    }

    @Test("A three-state pulse is attention-seeking")
    func threeStatePulseIsDetected() {
        #expect(verdict([1, 2, 3, 1, 2, 3]))
    }

    // MARK: Not attention-seeking

    @Test("A clock is not attention-seeking, though it changes constantly")
    func clockIsIgnored() {
        // Every tick is a state it has never drawn before.
        #expect(!verdict([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    @Test("A draining battery is not attention-seeking")
    func monotonicCounterIsIgnored() {
        #expect(!verdict([100, 99, 98, 97, 96, 95]))
    }

    @Test("A steady icon is not attention-seeking")
    func steadyIconIsIgnored() {
        #expect(!verdict([7, 7, 7, 7, 7, 7, 7, 7]))
    }

    @Test("A single change is not attention-seeking")
    func singleChangeIsIgnored() {
        #expect(!verdict([1, 1, 1, 2, 2, 2]))
    }

    @Test("A toggle that flips once and settles is not attention-seeking")
    func oneRoundTripIsIgnored() {
        // Connected -> connecting -> connected, then stays. One revisit.
        #expect(!verdict([1, 2, 1, 1, 1, 1]))
    }

    @Test("An item with no history is not attention-seeking")
    func unknownItemIsIgnored() {
        let detector = MenuBarItemAttentionDetector()
        #expect(!detector.isSeekingAttention(tag, at: 0))
    }

    // MARK: Windowing

    @Test("A blink that has stopped stops being attention-seeking")
    func verdictExpiresWithItsEvidence() {
        var detector = MenuBarItemAttentionDetector()
        var now: TimeInterval = 0
        for fingerprint in [1, 0, 1, 0, 1, 0] {
            detector.record(fingerprint: fingerprint, for: tag, at: now)
            now += 0.5
        }
        #expect(detector.isSeekingAttention(tag, at: now - 0.5))

        // The evidence ages out even though nothing new was recorded, so a
        // verdict cannot outlive the blink that produced it.
        #expect(!detector.isSeekingAttention(tag, at: now + 60))
    }

    @Test("Samples outside the window do not accumulate into a verdict")
    func spacedOutChangesAreIgnored() {
        // Six changes, but minutes apart: an icon updating, not blinking.
        #expect(!verdict([1, 0, 1, 0, 1, 0], interval: 120))
    }

    // MARK: Bookkeeping

    @Test("Items are judged independently")
    func itemsDoNotBleedIntoEachOther() {
        var detector = MenuBarItemAttentionDetector()
        var now: TimeInterval = 0
        for fingerprint in [1, 0, 1, 0, 1, 0] {
            detector.record(fingerprint: fingerprint, for: tag, at: now)
            detector.record(fingerprint: fingerprint, for: other, at: now)
            now += 0.5
        }
        let at = now - 0.5
        #expect(detector.isSeekingAttention(tag, at: at))

        detector.reset(other)
        #expect(!detector.isSeekingAttention(other, at: at))
        #expect(detector.isSeekingAttention(tag, at: at))
    }

    @Test("Resetting an item clears the verdict that surfaced it")
    func resetClearsHistory() {
        var detector = MenuBarItemAttentionDetector()
        var now: TimeInterval = 0
        for fingerprint in [1, 0, 1, 0, 1, 0] {
            detector.record(fingerprint: fingerprint, for: tag, at: now)
            now += 0.5
        }
        detector.reset(tag)
        #expect(!detector.isSeekingAttention(tag, at: now - 0.5))
    }

    @Test("Retaining drops history for items that left the bar")
    func retainPrunesDepartedItems() {
        var detector = MenuBarItemAttentionDetector()
        var now: TimeInterval = 0
        for fingerprint in [1, 0, 1, 0, 1, 0] {
            detector.record(fingerprint: fingerprint, for: tag, at: now)
            detector.record(fingerprint: fingerprint, for: other, at: now)
            now += 0.5
        }
        detector.retain([tag])
        let at = now - 0.5
        #expect(detector.isSeekingAttention(tag, at: at))
        #expect(!detector.isSeekingAttention(other, at: at))
    }

    // MARK: Configuration

    @Test("A stricter distinct-state limit rejects a three-state pulse")
    func configurationTightensDetection() {
        var configuration = MenuBarItemAttentionDetector.Configuration.standard
        configuration.maximumDistinctStates = 2
        #expect(!verdict([1, 2, 3, 1, 2, 3], configuration: configuration))
        #expect(verdict([1, 0, 1, 0, 1, 0], configuration: configuration))
    }
}
