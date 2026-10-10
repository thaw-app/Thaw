//
//  NotificationCenterActivationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
struct NotificationCenterActivationTests {
    @Test("Clock and keyboard requests share one ordered activation queue")
    func serialDelivery() async {
        let gate = Gate()
        var delivered: [NotificationCenterActivation.Request] = []
        let clock = NotificationCenterActivation.Request.clock(CGPoint(x: -50, y: 15))
        let key = NotificationCenterActivation.Request.shortcut(.systemDefault)
        let bridge = NotificationCenterActivation { request in
            delivered.append(request)
            if delivered.count == 1 {
                await gate.wait()
            }
        }
        bridge.enqueue(clock)
        await gate.waitUntilEntered()
        bridge.enqueue(key)
        bridge.enqueue(clock)
        #expect(delivered == [clock])
        #expect(bridge.isBusy)
        gate.open()
        await bridge.waitUntilIdle()
        #expect(delivered == [clock, key, clock])
        #expect(!bridge.isBusy)
    }

    @Test("Cancellation drops pending requests, then new requests wait for cleanup")
    func queueCancellation() async {
        let gate = Gate()
        var delivered: [NotificationCenterActivation.Request] = []
        let clock = NotificationCenterActivation.Request.clock(.zero)
        let key = NotificationCenterActivation.Request.shortcut(.systemDefault)
        let bridge = NotificationCenterActivation { request in
            delivered.append(request)
            if delivered.count == 1 {
                await gate.wait()
            }
        }
        bridge.enqueue(clock)
        await gate.waitUntilEntered()
        bridge.enqueue(key)
        bridge.cancel()
        bridge.enqueue(clock)
        #expect(delivered == [clock])
        gate.open()
        await bridge.waitUntilIdle()
        #expect(delivered == [clock, clock])
    }

    @Test("A toggle is sent once; restoration follows the panel, not a fixed delay")
    func singleDelivery() async {
        var calls: [String] = []
        var delays: [Duration] = []
        var isPresenting = false
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { isPresenting })
        await bridge.replay(
            begin: { calls.append("begin"); return .acquired },
            restore: { calls.append("restore") },
            send: {
                calls.append("send")
                isPresenting = true
            },
            pause: { delays.append($0) }
        )
        #expect(calls == ["begin", "send"])
        #expect(bridge.isBusy)
        await bridge.waitUntilIdle()
        #expect(calls == ["begin", "send", "restore"])
        #expect(delays == [.milliseconds(60), NotificationCenterActivation.escapeGrace])
        #expect(!bridge.isBusy)
    }

    @Test("Restoration polls for the panel, then graces the slide-out")
    func restorationWaitsForPanel() async {
        var calls: [String] = []
        var delays: [Duration] = []
        var polls = 0
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: {
            polls += 1
            return polls > 3 // call 1: gesture snapshot (closed); calls 2-3: polls
        })
        await bridge.replay(
            begin: { return .acquired },
            restore: { calls.append("restore") },
            send: { calls.append("send") },
            pause: { delays.append($0) }
        )
        await bridge.waitUntilIdle()
        #expect(calls == ["send", "restore"])
        #expect(polls == 4)
        #expect(delays == [
            .milliseconds(60),
            NotificationCenterActivation.pollInterval,
            NotificationCenterActivation.pollInterval,
            NotificationCenterActivation.escapeGrace,
        ])
    }

    @Test("A close gesture restores as soon as the panel dismisses")
    func closeGestureRestoresOnDismissal() async {
        var calls: [String] = []
        var delays: [Duration] = []
        var polls = 0
        // The panel is up when the close click arrives (call 1), still up on
        // the first poll (call 2), gone on the second (call 3).
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: {
            polls += 1
            return polls < 3
        })
        await bridge.replay(
            begin: { return .acquired },
            restore: { calls.append("restore") },
            send: { calls.append("send") },
            pause: { delays.append($0) }
        )
        await bridge.waitUntilIdle()
        #expect(calls == ["send", "restore"])
        #expect(delays == [
            .milliseconds(60),
            NotificationCenterActivation.pollInterval,
            NotificationCenterActivation.dismissGrace,
        ])
    }

    @Test("A panel that never settles still bounds the release")
    func neverPresentingTimesOut() async {
        var calls: [String] = []
        var delays: [Duration] = []
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { false })
        await bridge.replay(
            begin: { return .acquired },
            restore: { calls.append("restore") },
            send: { calls.append("send") },
            pause: { delays.append($0) }
        )
        await bridge.waitUntilIdle()
        #expect(calls == ["send", "restore"])
        let polls = delays.filter { $0 == NotificationCenterActivation.pollInterval }.count
        #expect(polls == Int(NotificationCenterActivation.presentationTimeout / NotificationCenterActivation.pollInterval))
        #expect(!delays.contains(NotificationCenterActivation.escapeGrace))
    }

    @Test("Another activation reuses the lease and replaces its restore deadline")
    func repeatedActivationExtendsLease() async {
        let firstWait = Gate()
        let secondWait = Gate()
        var begins = 0
        var sends = 0
        var restores = 0
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { sends == 1 }, now: { now })
        await bridge.replay(
            begin: { begins += 1; return .acquired },
            restore: { restores += 1 },
            send: { sends += 1 },
            pause: {
                if $0 == NotificationCenterActivation.escapeGrace {
                    await firstWait.wait()
                } else {
                    #expect($0 == .milliseconds(60))
                    now = now.addingTimeInterval(NotificationCenterActivation.minimumReleaseAge)
                }
            }
        )
        await firstWait.waitUntilEntered()
        await bridge.replay(
            begin: { begins += 1; return .acquired },
            restore: { restores += 1 },
            send: { sends += 1 },
            pause: {
                #expect($0 == NotificationCenterActivation.dismissGrace)
                await secondWait.wait()
            }
        )
        await secondWait.waitUntilEntered()
        #expect(begins == 1)
        #expect(sends == 2)
        #expect(restores == 0)
        firstWait.open()
        await Task.yield()
        #expect(restores == 0)
        #expect(bridge.isBusy)
        secondWait.open()
        await bridge.waitUntilIdle()
        #expect(restores == 1)
        #expect(!bridge.isBusy)
    }

    @Test("Cancellation restores immediately and invalidates the delayed restore")
    func cancellationDuringGracePeriod() async {
        let gate = Gate()
        var restores = 0
        var isPresenting = false
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { isPresenting })
        await bridge.replay(
            begin: { .acquired },
            restore: { restores += 1 },
            send: { isPresenting = true },
            pause: {
                if $0 == NotificationCenterActivation.escapeGrace {
                    await gate.wait()
                }
            }
        )
        await gate.waitUntilEntered()
        bridge.cancel()
        #expect(restores == 1)
        #expect(!bridge.isBusy)
        gate.open()
        await Task.yield()
        #expect(restores == 1)
    }
}

extension NotificationCenterActivationTests {
    @Test("A restriction already released does not drop the user's activation")
    func noLeaseStillDelivers() async {
        var calls: [String] = []
        let bridge = NotificationCenterActivation { _ in }
        await bridge.replay(
            begin: { .notRequired },
            restore: { calls.append("restore") },
            send: { calls.append("send") },
            pause: { _ in calls.append("wait") }
        )
        #expect(calls == ["send"])
    }

    @Test("Failure to release concealment is not permission to replay")
    func failedLeaseDoesNotReplay() async {
        var calls = 0
        let bridge = NotificationCenterActivation { _ in }
        await bridge.replay(
            begin: { .unavailable },
            restore: { calls += 1 },
            send: { calls += 1 },
            pause: { _ in calls += 1 }
        )
        #expect(calls == 0)
    }

    @Test("Cancellation during either wait restores the lease", arguments: [1, 2])
    func cancellationRestoresConcealment(at wait: Int) async {
        var pauses = 0
        var sends = 0
        var restores = 0
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { true })
        await bridge.replay(
            begin: { .acquired },
            restore: { restores += 1 },
            send: { sends += 1 },
            pause: { _ in
                pauses += 1
                if pauses == wait {
                    throw CancellationError()
                }
            }
        )
        await bridge.waitUntilIdle()
        #expect(restores == 1)
        #expect(sends == (wait == 1 ? 0 : 1))
    }

    @Test("A prepared lease waits only for its remaining settle time", arguments: [0, 30, 60, 100])
    func preparedLeaseSkipsSettle(ageMilliseconds: Int) async {
        var begins = 0
        var calls: [String] = []
        var delays: [Duration] = []
        var isPresenting = false
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let bridge = NotificationCenterActivation(
            activate: { _ in },
            panelPresenting: { isPresenting },
            now: { now }
        )
        bridge.prepareLease(
            begin: { begins += 1; return .acquired },
            restore: { calls.append("restore-prepare") }
        )
        #expect(bridge.isBusy)
        now = now.addingTimeInterval(Double(ageMilliseconds) / 1000)
        await bridge.replay(
            begin: { begins += 1; return .acquired },
            restore: { calls.append("restore-replay") },
            send: {
                calls.append("send")
                isPresenting = true
            },
            pause: { delays.append($0) }
        )
        #expect(begins == 1)
        #expect(calls == ["send"])
        #expect(bridge.isBusy)
        await bridge.waitUntilIdle()
        #expect(calls == ["send", "restore-prepare"])
        let settle: [Duration] = ageMilliseconds < 60 ? [.milliseconds(60 - ageMilliseconds)] : []
        #expect(delays == settle + [NotificationCenterActivation.escapeGrace])
        #expect(!bridge.isBusy)
    }

    @Test("A prepared lease with no activation restores at the bound")
    func abandonedPrepareRestores() async {
        var restores = 0
        let bridge = NotificationCenterActivation(activate: { _ in }, panelPresenting: { false })
        bridge.prepareLease(
            begin: { return .acquired },
            restore: { restores += 1 }
        )
        #expect(bridge.isBusy)
        await bridge.waitUntilIdle()
        #expect(restores == 1)
        #expect(!bridge.isBusy)
    }

    @Test("A cancelled activation acquires no lease and sends no event")
    func cancelledBeforeStart() async {
        var calls = 0
        let bridge = NotificationCenterActivation { _ in }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await bridge.replay(
                begin: { calls += 1; return .acquired },
                restore: { calls += 1 },
                send: { calls += 1 },
                pause: { _ in calls += 1 }
            )
        }
        await task.value
        #expect(calls == 0)
    }

    @Test("Clock replay preserves secondary-display coordinates and a balanced click")
    func mouseReplay() throws {
        let point = CGPoint(x: -50, y: -185)
        let events = NotificationCenterEventReplay.clockClick(at: point)
        #expect(events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        for event in events {
            #expect(event.location == point)
            #expect(event.flags.isEmpty)
            #expect(event.getIntegerValueField(.mouseEventClickState) == 1)
            #expect(NotificationCenterEventReplay.isReplay(event))
        }
        let physical = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
        #expect(!NotificationCenterEventReplay.isReplay(physical))
    }

    @Test("Shortcut replay preserves modifiers and stamps both halves of the key pair", arguments: [
        SystemNotificationCenterHotkey.systemDefault,
        SystemNotificationCenterHotkey(keyCode: 15, flags: [.maskControl, .maskAlternate]),
    ])
    func keyboardReplay(_ hotkey: SystemNotificationCenterHotkey) {
        let events = NotificationCenterEventReplay.shortcut(hotkey)
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        for event in events {
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == Int64(hotkey.keyCode))
            #expect(event.flags == hotkey.flags)
            #expect(NotificationCenterEventReplay.isReplay(event))
        }
    }
}

@MainActor
private final class Gate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            release = continuation
            entered = true
            entry?.resume()
            entry = nil
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entry = $0 }
    }

    func open() {
        release?.resume()
        release = nil
    }
}
