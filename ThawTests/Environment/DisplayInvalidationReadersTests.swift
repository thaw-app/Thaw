//
//  DisplayInvalidationReadersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

/// The readers that drop state at a display change follow DisplayEnvironment's invalidations.
/// Each environment here posts on its own notification center, so a posting it does not relay reaches no reader.
@MainActor
@Suite("Display invalidation readers", .serialized, .timeLimit(.minutes(1)))
struct DisplayInvalidationReadersTests {
    private static let single = DisplayArrangement(frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982)], mainDisplayID: 1)

    /// An environment whose settle ends at once, so only the invalidation is in play.
    private static func makeEnvironment() -> (environment: DisplayEnvironment, center: NotificationCenter) {
        let center = NotificationCenter()
        let environment = DisplayEnvironment(
            center: center,
            baseline: single,
            read: { single },
            sleep: { _ in throw CancellationError() }
        )
        return (environment, center)
    }

    private static func postScreenParametersChange(on center: NotificationCenter) {
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @Test("The saved-order mirror is held from the posting turn of an invalidation, and not before the environment relays one")
    func mirrorGateFollowsInvalidations() {
        let (environment, center) = Self.makeEnvironment()
        let gate = SavedOrderMirrorGate(observesSystem: false)
        gate.observe(displayInvalidations: environment.invalidations)
        let identifiers: Set = ["com.example.one"]

        Self.postScreenParametersChange(on: center)
        #expect(gate.allowsMirror(identifiers: identifiers, restrictionChange: nil))

        environment.start()
        defer { environment.stop() }
        Self.postScreenParametersChange(on: center)
        #expect(!gate.allowsMirror(identifiers: identifiers, restrictionChange: nil))
        #expect(gate.allowsMirror(identifiers: identifiers, restrictionChange: nil, now: .now + SavedOrderMirrorGate.quietPeriod))
    }

    @Test("A spent re-publish budget is restored in the posting turn of an invalidation, and not before the environment relays one")
    func controlItemResetFollowsInvalidations() {
        let (environment, center) = Self.makeEnvironment()
        let controlItem = ControlItem(identifier: .alwaysHidden)
        controlItem.observeDisplayInvalidations(environment.invalidations)
        ControlItem.republishCounts[.alwaysHidden] = ControlItem.maximumRepublishes
        defer { ControlItem.republishCounts[.alwaysHidden] = nil }

        Self.postScreenParametersChange(on: center)
        #expect(ControlItem.republishCounts[.alwaysHidden] == ControlItem.maximumRepublishes)

        environment.start()
        defer { environment.stop() }
        Self.postScreenParametersChange(on: center)
        #expect(ControlItem.republishCounts[.alwaysHidden] == nil)
    }

    @Test("A revealed descender retracts 0.2 s after an invalidation, and not before the environment relays one")
    func notchDescenderRetractsOnInvalidation() async {
        let (environment, center) = Self.makeEnvironment()
        let model = NotchPanelModel()
        let widget = NotchClockWidget()
        model.stage(NotchPresentation(id: widget.id, widget: widget, itemWindowID: 1, bodySize: widget.bodySize, bodyOffset: 0, panelFrame: .zero))
        model.setRevealed(true)
        let controller = NotchPanelController(model: model)
        controller.observeDisplayInvalidations(environment.invalidations)

        Self.postScreenParametersChange(on: center)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(model.isRevealed)

        environment.start()
        defer { environment.stop() }
        Self.postScreenParametersChange(on: center)
        #expect(model.isRevealed, "The retract keeps its 0.2 s debounce")
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isRevealed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isRevealed)
    }
}
