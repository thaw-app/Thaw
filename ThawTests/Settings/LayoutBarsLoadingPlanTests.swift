//
//  LayoutBarsLoadingPlanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Keeps the Layout pane and Simple Mode off a spinner that never resolves.
///
/// The overlay shows "Loading menu bar items…" until a deadline flips it to a
/// state that explains itself. The deadline is armed by the preload's timeout,
/// so a path that returns before the preload starts has to arm it on the way
/// out. The denied-Screen-Recording path is one: the capture cannot run
/// without the grant, so without the deadline the overlay waits forever.
///
/// The modifier's own @State and @Environment put its flag out of reach,
/// so the branch that decides the flag is what is pinned here.
@MainActor
@Suite("Layout bars loading plan")
struct LayoutBarsLoadingPlanTests {
    typealias Plan = LayoutBarsLoading.PreloadPlan

    static nonisolated let flags = [false, true]

    /// Every combination of the two inputs the plan is derived from.
    static nonisolated let allInputs: [(Bool, Bool)] = flags.flatMap { items in
        flags.map { grant in (items, grant) }
    }

    @Test("Screen Recording denied resolves the overlay instead of loading")
    func deniedGrantResolvesImmediately() {
        let plan = LayoutBarsLoading.preloadPlan(hasItems: false, hasScreenRecordingPermission: false)

        #expect(plan == .resolveWithoutLoading)
        #expect(plan.armsDeadlineImmediately, "There is no load to time out, so the spinner has to go now")
    }

    @Test("Granted but empty still runs the preload, and leaves the deadline to it")
    func grantedAndEmptyPreloads() {
        let plan = LayoutBarsLoading.preloadPlan(hasItems: false, hasScreenRecordingPermission: true)

        #expect(plan == .preload)
        #expect(
            !plan.armsDeadlineImmediately,
            "Arming here would show the failure state over a load that is still running"
        )
    }

    @Test("A cache that already has items loads nothing", arguments: flags)
    func cachedItemsSkipTheLoad(hasScreenRecordingPermission: Bool) {
        let plan = LayoutBarsLoading.preloadPlan(
            hasItems: true,
            hasScreenRecordingPermission: hasScreenRecordingPermission
        )

        // The bars are live either way: a missing grant is worth naming only
        // when it is the reason there is nothing to drag.
        #expect(plan == .nothingToLoad)
        #expect(!plan.armsDeadlineImmediately)
    }

    @Test("No input leaves the overlay spinning with nothing running", arguments: allInputs)
    func everyPathEitherLoadsOrResolves(input: (Bool, Bool)) {
        let plan = LayoutBarsLoading.preloadPlan(hasItems: input.0, hasScreenRecordingPermission: input.1)

        // The spinner is only allowed to stay up while a load it can time
        // out is actually in flight.
        let spins = !input.0 && !plan.armsDeadlineImmediately
        #expect(!spins || plan == .preload)
    }
}
