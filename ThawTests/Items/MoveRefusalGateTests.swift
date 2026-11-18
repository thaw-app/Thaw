//
//  MoveRefusalGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The eleven refusal checks in evaluation order: the first refusing check wins,
/// and a user's own move is exempt from the circuit breaker.
struct MoveRefusalGateTests {
    /// Counts how often each lazy input was asked.
    private final class Asked {
        var screenLock = 0
        var breaker = 0
        var owner = 0
    }

    private func makeRequest(
        asked: Asked = Asked(),
        arrangementForbidsMoves: Bool = false,
        isScreenLocked: Bool = false,
        isCircuitBreakerOpen: Bool = false,
        isUserInitiated: Bool = false,
        isSystemClone: Bool = false,
        involvesNativeOverflowControl: Bool = false,
        isPositionStoreRecovery: Bool = false,
        hasAppState: Bool = true,
        isPhysicallyOrderable: Bool = true,
        isUserDraggingItem: Bool = false,
        isOwnerUnresponsive: Bool = false,
        allowsSectionBoundaryTarget: Bool = false,
        targetsLegacyDivider: Bool = false
    ) -> MoveRefusalGate.Request {
        .init(
            arrangementForbidsMoves: arrangementForbidsMoves,
            isScreenLocked: {
                asked.screenLock += 1
                return isScreenLocked
            },
            isCircuitBreakerOpen: {
                asked.breaker += 1
                return isCircuitBreakerOpen
            },
            isUserInitiated: isUserInitiated,
            isSystemClone: isSystemClone,
            involvesNativeOverflowControl: involvesNativeOverflowControl,
            isPositionStoreRecovery: isPositionStoreRecovery,
            hasAppState: hasAppState,
            isPhysicallyOrderable: isPhysicallyOrderable,
            isUserDraggingItem: isUserDraggingItem,
            isOwnerUnresponsive: {
                asked.owner += 1
                return isOwnerUnresponsive
            },
            allowsSectionBoundaryTarget: allowsSectionBoundaryTarget,
            targetsLegacyDivider: targetsLegacyDivider
        )
    }

    @Test("A clear move goes ahead")
    func proceeds() {
        #expect(MoveRefusalGate.firstRejection(makeRequest()) == nil)
    }

    @Test("Each check refuses on its own")
    func eachCheckRefuses() {
        #expect(MoveRefusalGate.firstRejection(makeRequest(arrangementForbidsMoves: true)) == .manualArrangement)
        #expect(MoveRefusalGate.firstRejection(makeRequest(isScreenLocked: true)) == .screenLocked)
        #expect(MoveRefusalGate.firstRejection(makeRequest(isCircuitBreakerOpen: true)) == .circuitBreakerOpen)
        #expect(MoveRefusalGate.firstRejection(makeRequest(isSystemClone: true)) == .systemClone)
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(involvesNativeOverflowControl: true)) == .nativeOverflowControl
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isPositionStoreRecovery: true)) == .positionStoreRecovery
        )
        #expect(MoveRefusalGate.firstRejection(makeRequest(hasAppState: false)) == .appStateUnavailable)
        #expect(MoveRefusalGate.firstRejection(makeRequest(isPhysicallyOrderable: false)) == .itemNotMovable)
        #expect(MoveRefusalGate.firstRejection(makeRequest(isUserDraggingItem: true)) == .userDragInProgress)
        #expect(MoveRefusalGate.firstRejection(makeRequest(isOwnerUnresponsive: true)) == .ownerUnresponsive)
        #expect(MoveRefusalGate.firstRejection(makeRequest(targetsLegacyDivider: true)) == .legacyDividerTarget)
    }

    @Test("A move that trips two checks is refused for the earlier one")
    func earlierCheckWins() {
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(arrangementForbidsMoves: true, isScreenLocked: true))
                == .manualArrangement
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isScreenLocked: true, isCircuitBreakerOpen: true))
                == .screenLocked
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isCircuitBreakerOpen: true, isSystemClone: true))
                == .circuitBreakerOpen
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isSystemClone: true, involvesNativeOverflowControl: true))
                == .systemClone
        )
        #expect(
            MoveRefusalGate.firstRejection(
                makeRequest(involvesNativeOverflowControl: true, isPositionStoreRecovery: true)
            ) == .nativeOverflowControl
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isPositionStoreRecovery: true, hasAppState: false))
                == .positionStoreRecovery
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(hasAppState: false, isPhysicallyOrderable: false))
                == .appStateUnavailable
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isPhysicallyOrderable: false, isUserDraggingItem: true))
                == .itemNotMovable
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isUserDraggingItem: true, isOwnerUnresponsive: true))
                == .userDragInProgress
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isOwnerUnresponsive: true, targetsLegacyDivider: true))
                == .ownerUnresponsive
        )
    }

    @Test("A user's own move goes through an open breaker, an automatic one does not")
    func userMoveIsExemptFromTheBreaker() {
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isCircuitBreakerOpen: true, isUserInitiated: true)) == nil
        )
        #expect(
            MoveRefusalGate.firstRejection(makeRequest(isCircuitBreakerOpen: true, isUserInitiated: false))
                == .circuitBreakerOpen
        )
    }

    @Test("The breaker exemption does not excuse a later check")
    func userMoveIsStillRefusedByLaterChecks() {
        #expect(
            MoveRefusalGate.firstRejection(
                makeRequest(isCircuitBreakerOpen: true, isUserInitiated: true, isSystemClone: true)
            ) == .systemClone
        )
    }

    @Test("A section transition may target a divider, any other move may not")
    func sectionBoundaryTarget() {
        #expect(
            MoveRefusalGate.firstRejection(
                makeRequest(allowsSectionBoundaryTarget: true, targetsLegacyDivider: true)
            ) == nil
        )
        #expect(
            MoveRefusalGate.firstRejection(
                makeRequest(allowsSectionBoundaryTarget: false, targetsLegacyDivider: true)
            ) == .legacyDividerTarget
        )
    }

    @Test("The lock check, the breaker and the owner check are asked only when no earlier check refused")
    func lazyInputsAreAskedInOrder() {
        let manual = Asked()
        _ = MoveRefusalGate.firstRejection(makeRequest(asked: manual, arrangementForbidsMoves: true))
        #expect(manual.screenLock == 0 && manual.breaker == 0 && manual.owner == 0)

        let locked = Asked()
        _ = MoveRefusalGate.firstRejection(makeRequest(asked: locked, isScreenLocked: true))
        #expect(locked.screenLock == 1 && locked.breaker == 0 && locked.owner == 0)

        let clone = Asked()
        _ = MoveRefusalGate.firstRejection(makeRequest(asked: clone, isSystemClone: true))
        #expect(clone.screenLock == 1 && clone.breaker == 1 && clone.owner == 0)

        let dragging = Asked()
        _ = MoveRefusalGate.firstRejection(makeRequest(asked: dragging, isUserDraggingItem: true))
        #expect(dragging.owner == 0)

        let clear = Asked()
        _ = MoveRefusalGate.firstRejection(makeRequest(asked: clear))
        #expect(clear.screenLock == 1 && clear.breaker == 1 && clear.owner == 1)
    }
}
