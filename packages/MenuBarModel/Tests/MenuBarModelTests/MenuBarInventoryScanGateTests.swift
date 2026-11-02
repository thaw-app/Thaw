//
//  MenuBarInventoryScanGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MenuBarInventoryScanGateTests {
    @Test("Pre-request scans and scans missing a required owner cannot satisfy fresh geometry", arguments: [false, true], [MenuBarScanScope.knownOwners, .requestedOwners])
    func requestNeedsSuccessor(addsOwner: Bool, scope: MenuBarScanScope) async {
        let started = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let gate = MenuBarInventoryScanGate<String, UInt64> { previous, _, owners in
            var state = previous
            let pass = state.begin(owners: Array(owners), priorityOwners: owners)
            if pass.generation == 1 {
                started.continuation.yield(())
                started.continuation.finish()
                for await _ in release.stream {
                    break
                }
            }
            return (pass.generation, state)
        }
        let initial = Task { await gate.snapshot(freshOnly: false, scope: scope, priorityOwners: [1]) }
        for await _ in started.stream {
            break
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(1))
            release.continuation.finish()
        }
        defer { watchdog.cancel() }
        let move = await gate.snapshot(
            freshOnly: !addsOwner, scope: scope, priorityOwners: addsOwner ? [1, 2] : [1]
        )
        #expect(move == 2)
        #expect(await initial.value == 1)
    }

    @Test("A cancelled requester does not cancel shared discovery")
    func cancelledRequestDoesNotPreempt() async {
        let started = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let gate = MenuBarInventoryScanGate<String, Bool> { state, _, _ in
            started.continuation.yield(())
            started.continuation.finish()
            for await _ in release.stream {
                break
            }
            return (!Task.isCancelled, state)
        }
        let background = Task { await gate.snapshot(freshOnly: false) }
        for await _ in started.stream {
            break
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await gate.snapshot(freshOnly: true, scope: .knownOwners)
        }
        #expect(await cancelled.value == nil)
        release.continuation.finish()
        #expect(await background.value == true)
    }

    @Test("Foreground geometry stops background discovery instead of waiting for empty apps", arguments: [MenuBarScanScope.knownOwners, .requestedOwners])
    func foregroundPreemptsDiscovery(scope: MenuBarScanScope) async {
        let started = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let gate = MenuBarInventoryScanGate<String, String> { previous, scope, _ in
            guard scope == .discovery else { return (previous.observations.first ?? "missing", previous) }
            var state = previous
            let pass = state.begin(owners: [1], priorityOwners: [])
            state.didAttempt(owner: 1, generation: pass.generation)
            state.record(["known owner"], owner: 1, generation: pass.generation)
            started.continuation.yield(())
            started.continuation.finish()
            for await _ in release.stream {
                break
            }
            return (Task.isCancelled ? "cancelled" : "completed", state)
        }
        let background = Task { await gate.snapshot(freshOnly: false) }
        for await _ in started.stream {
            break
        }
        // A deadlock backstop, not a timing assertion: the old gate completes
        // normally here and fails the cancellation assertion below.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(1))
            release.continuation.finish()
        }
        defer { watchdog.cancel() }
        let foreground = await gate.snapshot(freshOnly: true, scope: scope)
        #expect(foreground == "known owner", "Preemption must retain discovery progress")
        #expect(await background.value == "cancelled", "Discovery should stop at its current owner")
    }

    @Test("A periodic reader waits for background discovery instead of cancelling it")
    func periodicReaderDoesNotPreemptDiscovery() async {
        let started = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let gate = MenuBarInventoryScanGate<String, String> { previous, scope, _ in
            guard scope == .discovery else { return (previous.observations.first ?? "missing", previous) }
            var state = previous
            let pass = state.begin(owners: [1], priorityOwners: [])
            state.didAttempt(owner: 1, generation: pass.generation)
            state.record(["known owner"], owner: 1, generation: pass.generation)
            started.continuation.yield(())
            started.continuation.finish()
            for await _ in release.stream {
                break
            }
            return (Task.isCancelled ? "cancelled" : "completed", state)
        }
        let background = Task { await gate.snapshot(freshOnly: false) }
        for await _ in started.stream {
            break
        }
        let periodic = Task {
            await gate.snapshot(freshOnly: true, scope: .requestedOwners, preemptsDiscovery: false)
        }
        // Long enough for the reader to reach the gate; a preempting gate
        // cancels discovery there and fails the assertion below.
        try? await Task.sleep(for: .milliseconds(100))
        release.continuation.finish()
        #expect(await background.value == "completed")
        #expect(await periodic.value == "known owner", "The reader still gets a walk of its own afterwards")
    }
}
