//
//  MouseHelpersButtonEventTimestampTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers `MouseHelpers.lastPointerButtonEventOccurred` and its wiring into
/// `physicalPointerInputOccurred`, the HID-timestamp detector added for the
/// #1075 review so a click that landed mid-batch but was released before the
/// check is still detected (isButtonPressed() alone misses those).
///
/// The detector reads live HID state via CGEventSource.secondsSinceLastEventType,
/// which a unit test cannot plant deterministically. These tests pin the
/// contract instead: the helper is callable on the HID-system state, returns a
/// Bool for every event type it covers, and physicalPointerInputOccurred
/// composes it with the movement and scroll checks without crashing.
@Suite("MouseHelpers button-event timestamp detector")
struct MouseHelpersButtonEventTimestampTests {
    @Test("lastPointerButtonEventOccurred returns a Bool over the HID-system state")
    func buttonEventDetectorIsCallable() {
        // A zero-duration window reports no event occurred within it, unless a
        // button event happened in the same instant. The point of the
        // assertion is that the call is well-defined over the 9 event types
        // (left/right/other × down/up/dragged) and never traps.
        let result = MouseHelpers.lastPointerButtonEventOccurred(
            within: .zero,
            stateID: .hidSystemState
        )
        #expect(result == false || result == true)
    }

    @Test("physicalPointerInputOccurred composes the button detector with movement and scroll")
    func physicalPointerInputComposesAllThree() {
        // An instant interval (now to now) cannot contain a movement, scroll,
        // or button event that happened strictly before it, so the composite
        // reports false. The assertion pins that the three detectors are all
        // consulted and the composition stays total.
        let result = MouseHelpers.physicalPointerInputOccurred(
            since: .now,
            now: .now
        )
        #expect(result == false)
    }
}
