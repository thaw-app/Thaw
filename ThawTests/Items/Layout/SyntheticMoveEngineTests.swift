//
//  SyntheticMoveEngineTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Drives the engine with injected geometry and a recording drag, so no real input is posted.
@MainActor
@Suite("The synthetic move engine plans, posts and verifies one drag", .scratchDefaults)
struct SyntheticMoveEngineTests {
    /// Records what the engine asked the drag to do.
    final class DragRecorder {
        var drags: [(start: CGPoint, end: CGPoint, address: SyntheticMoveEngine.DragAddress)] = []
        var results: [(SyntheticMoveEngine.DragAddress, Bool)] = []
        var prepared: [Int] = []
        var validations = 0
        var enumerations = 0
    }

    /// The left end of the main display's bar, well clear of any notch.
    private static var barOrigin: CGPoint {
        let display = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: display.minX + 40, y: display.minY + 2)
    }

    private static func item(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.move"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 999_996,
            sourcePID: 999_996,
            bounds: CGRect(x: barOrigin.x + x, y: barOrigin.y, width: 24, height: 20),
            title: title,
            isOnScreen: true
        )
    }

    /// Mover sits right of the anchor; the move asks for it on the left.
    private let anchor = item("Anchor", x: 0, windowID: 501)
    private let mover = item("Mover", x: 30, windowID: 502)
    private var moverOnLeft: MenuBarItem {
        Self.item("Mover", x: -30, windowID: 502)
    }

    private func makeEngine(
        recorder: DragRecorder,
        afterDrag: [MenuBarItem]
    ) -> SyntheticMoveEngine {
        let before = [anchor, mover]
        var engine = SyntheticMoveEngine(
            eventSemaphore: SimpleSemaphore(value: 1),
            makeEventSource: {
                guard let source = CGEventSource(stateID: .privateState) else {
                    throw MenuBarItemManager.EventError.invalidEventSource
                }
                return source
            },
            enumerateItems: {
                recorder.enumerations += 1
                return recorder.drags.isEmpty ? before : afterDrag
            }
        )
        engine.postCommandDrag = { start, end, _, address, _ in
            recorder.drags.append((start, end, address))
        }
        engine.prepareForAttempt = { recorder.prepared.append($0) }
        engine.validateHIDInput = { recorder.validations += 1 }
        engine.onAttemptResult = { recorder.results.append(($0, $1)) }
        engine.resolveMenuBarAgentPID = { nil }
        return engine
    }

    @Test("A drag that lands is posted once through the HID tap and reported")
    func landedDrag() async throws {
        let recorder = DragRecorder()
        let engine = makeEngine(recorder: recorder, afterDrag: [moverOnLeft, anchor])

        try await engine.move(item: mover, to: .leftOfItem(anchor))

        try #require(recorder.drags.count == 1)
        let drag = recorder.drags[0]
        #expect(drag.address == .hidEventTap)
        #expect(drag.start == CGPoint(x: mover.bounds.midX, y: mover.bounds.midY))
        #expect(drag.end == CGPoint(x: anchor.bounds.minX - 2, y: anchor.bounds.midY))
        #expect(recorder.validations == 1)
        #expect(recorder.prepared == [1])
        #expect(recorder.results.count == 1)
        #expect(recorder.results.first?.1 == true)
    }

    @Test("A rightward move drops past the anchor's right edge")
    func rightwardDropPoint() async throws {
        let recorder = DragRecorder()
        let left = Self.item("Left", x: -30, windowID: 503)
        var engine = makeEngine(recorder: recorder, afterDrag: [anchor, Self.item("Left", x: 30, windowID: 503)])
        engine.initialItems = [left, anchor]

        try await engine.move(item: left, to: .rightOfItem(anchor))

        #expect(recorder.drags.first?.end == CGPoint(x: anchor.bounds.maxX + 2, y: anchor.bounds.midY))
        // The caller's enumeration stands in for the first geometry read.
        #expect(recorder.enumerations >= 1)
    }

    @Test("An order that already satisfies the destination posts nothing")
    func alreadySatisfied() async throws {
        let recorder = DragRecorder()
        var engine = makeEngine(recorder: recorder, afterDrag: [])
        engine.initialItems = [moverOnLeft, anchor]

        try await engine.move(item: moverOnLeft, to: .leftOfItem(anchor))

        #expect(recorder.drags.isEmpty)
        #expect(recorder.enumerations == 0)
    }

    @Test("A drag that never lands is retried, then reported as cannot complete")
    func exhaustedAttempts() async {
        let recorder = DragRecorder()
        let engine = makeEngine(recorder: recorder, afterDrag: [anchor, mover])

        await #expect(throws: MenuBarItemManager.EventError.self) {
            try await engine.move(item: mover, to: .leftOfItem(anchor), maxAttempts: 2)
        }

        #expect(recorder.drags.count == 2)
        #expect(recorder.prepared == [1, 2])
        #expect(recorder.results.map(\.1) == [false, false])
    }

    @Test("The first attempt addresses MenuBarAgent when enabled, and the retry uses the HID tap")
    func agentAddressThenHID() async {
        Defaults.set(false, forKey: .useHeldCommandDrag)
        Defaults.set(true, forKey: .addressMoveDragToMenuBarAgent)
        let recorder = DragRecorder()
        var engine = makeEngine(recorder: recorder, afterDrag: [anchor, mover])
        engine.resolveMenuBarAgentPID = { 4242 }

        await #expect(throws: MenuBarItemManager.EventError.self) {
            try await engine.move(item: mover, to: .leftOfItem(anchor))
        }

        #expect(recorder.drags.map(\.address) == [.process(4242), .hidEventTap])
        // Only the HID attempt checks the user's input.
        #expect(recorder.validations == 1)
    }

    @Test("A held drag always travels the HID tap")
    func heldDragUsesHID() async throws {
        Defaults.set(true, forKey: .useHeldCommandDrag)
        Defaults.set(true, forKey: .addressMoveDragToMenuBarAgent)
        let recorder = DragRecorder()
        var engine = makeEngine(recorder: recorder, afterDrag: [moverOnLeft, anchor])
        engine.resolveMenuBarAgentPID = { 4242 }

        try await engine.move(item: mover, to: .leftOfItem(anchor))

        #expect(recorder.drags.map(\.address) == [.hidEventTap])
    }

    @Test("A refused HID input check stops the move before posting")
    func refusedInputStops() async {
        let recorder = DragRecorder()
        var engine = makeEngine(recorder: recorder, afterDrag: [])
        engine.validateHIDInput = { throw MenuBarItemManager.EventError.cannotComplete }

        await #expect(throws: MenuBarItemManager.EventError.self) {
            try await engine.move(item: mover, to: .leftOfItem(anchor))
        }
        #expect(recorder.drags.isEmpty)
    }

    @Test("An anchored system item is refused as the drop target")
    func anchoredTargetRefused() async throws {
        let recorder = DragRecorder()
        let engine = makeEngine(recorder: recorder, afterDrag: [])
        let clock = MenuBarItem(
            tag: .clock,
            windowID: 700,
            ownerPID: 999_996,
            sourcePID: 999_996,
            bounds: anchor.bounds.offsetBy(dx: 90, dy: 0),
            title: nil,
            isOnScreen: true
        )

        do {
            try await engine.move(item: mover, to: .rightOfItem(clock))
            Issue.record("An anchored target must be refused")
        } catch let MenuBarItemManager.EventError.itemNotMovable(refused, _) {
            #expect(refused.windowID == clock.windowID)
        }
        #expect(recorder.drags.isEmpty)
        #expect(recorder.prepared.isEmpty)
    }

    @Test("A control item is refused as the dragged item")
    func controlItemRefused() async throws {
        let recorder = DragRecorder()
        let engine = makeEngine(recorder: recorder, afterDrag: [])
        let divider = MenuBarItem(
            tag: MenuBarItemTag(namespace: .thaw, title: ControlItemIdentifier.hidden.rawValue, instanceIndex: 0),
            windowID: 600,
            ownerPID: 999_996,
            sourcePID: 999_996,
            bounds: anchor.bounds.offsetBy(dx: 60, dy: 0),
            title: nil,
            isOnScreen: true
        )

        do {
            try await engine.move(item: divider, to: .leftOfItem(anchor))
            Issue.record("A divider must not be dragged")
        } catch let MenuBarItemManager.EventError.itemNotMovable(refused, refusal) {
            #expect(refused.windowID == divider.windowID)
            #expect(refusal == .hiddenControlItem)
        }
        #expect(recorder.drags.isEmpty)
    }

    @Test("An item missing from the live geometry fails with missing bounds")
    func missingBounds() async throws {
        let recorder = DragRecorder()
        var engine = makeEngine(recorder: recorder, afterDrag: [])
        engine.initialItems = [anchor]

        do {
            try await engine.move(item: mover, to: .leftOfItem(anchor), maxAttempts: 1)
            Issue.record("A move without the mover's bounds must fail")
        } catch let MenuBarItemManager.EventError.missingItemBounds(missing) {
            #expect(missing.windowID == mover.windowID)
        }
    }

    @Test("A drag that would start off every display is refused")
    func offScreenRefused() async throws {
        let recorder = DragRecorder()
        var engine = makeEngine(recorder: recorder, afterDrag: [])
        let farAway = MenuBarItem(
            tag: mover.tag,
            windowID: mover.windowID,
            ownerPID: mover.ownerPID,
            sourcePID: mover.sourcePID,
            bounds: mover.bounds.offsetBy(dx: 0, dy: -50000),
            title: mover.title,
            isOnScreen: true
        )
        engine.initialItems = [anchor, farAway]

        do {
            try await engine.move(item: mover, to: .leftOfItem(anchor), maxAttempts: 1)
            Issue.record("An off-screen drag must be refused")
        } catch MenuBarItemManager.EventError.itemNotMovable {
            #expect(recorder.drags.isEmpty)
        }
    }

    @Test(
        "Address selection targets MenuBarAgent only on an enabled first attempt with a known agent",
        arguments: [
            (1, true, pid_t?.some(7), SyntheticMoveEngine.DragAddress.process(7)),
            (2, true, 7, .hidEventTap),
            (1, false, 7, .hidEventTap),
            (1, true, nil, .hidEventTap),
        ]
    )
    func pureAddressSelection(attempt: Int, enabled: Bool, pid: pid_t?, expected: SyntheticMoveEngine.DragAddress) {
        #expect(SyntheticMoveEngine.dragAddress(forAttempt: attempt, isEnabled: enabled, menuBarAgentPID: pid) == expected)
    }

    @Test("Drag addresses describe themselves for the log")
    func addressDescriptions() {
        #expect(SyntheticMoveEngine.DragAddress.hidEventTap.description == "hidEventTap")
        #expect(SyntheticMoveEngine.DragAddress.process(12).description == "pid 12")
        #expect(
            SyntheticMoveEngine.DragAddress.eventRecord(pid: 3, window: 4, frame: .zero).description
                == "event record pid 3 window 4"
        )
    }
}
