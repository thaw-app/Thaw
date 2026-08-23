//
//  ControlItemRecoveryTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the bounded control-item recovery path for issue #754:
/// on macOS 26 with multiple displays, after long uptime `ControlItemPair`
/// lookup in `cacheItemsRegardless` can start failing permanently. These
/// tests cover the pure escalation decision that gates rebuilding the
/// control items' underlying status items.
///
/// The detector re-arming half of the fix (a failed lookup no longer commits
/// `itemWindowIDs` to `CacheActor`, so `cacheItemsIfNeeded` keeps seeing a
/// mismatch and keeps re-driving recache attempts) is not covered here:
/// `CacheActor` is a private nested type of `MenuBarItemManager` with no
/// reachable seam, and exercising it live would require a real
/// `MenuBarItemManager` wired to an `AppState`, live `NSStatusItem`s, and
/// screen-recording permission — not available in this unit test target.
/// That half is verified by code reading instead: see the ordering of
/// `cacheActor.updateCachedItemWindowIDs`/`updateCachedCloneWindowIDs` in
/// `cacheItemsRegardless`, which now runs only after the `ControlItemPair`
/// guard succeeds, never inside the failure branch.
@Suite("Control item recovery")
struct ControlItemRecoveryTests {
    @Test("Below the threshold, no rebuild is requested")
    func belowThresholdDoesNotRebuild() {
        for count in 0 ..< MenuBarItemManager.controlItemRebuildThreshold {
            #expect(
                !MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: count),
                "consecutiveFailures=\(count) should not yet trigger a rebuild"
            )
        }
    }

    @Test("Reaching the threshold triggers a rebuild")
    func thresholdTriggersRebuild() {
        #expect(
            MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: MenuBarItemManager.controlItemRebuildThreshold
            )
        )
    }

    @Test("Beyond the threshold a rebuild is still triggered")
    func beyondThresholdStillTriggersRebuild() {
        #expect(
            MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: MenuBarItemManager.controlItemRebuildThreshold + 5
            )
        )
    }

    @Test("A custom threshold is respected")
    func customThresholdIsRespected() {
        #expect(!MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: 1, threshold: 2))
        #expect(MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: 2, threshold: 2))
    }

    /// Models the manager's own episode latch: failures continue to be counted
    /// after rebuilding, but no second rebuild is allowed until a lookup works.
    @Test("A persistent failure episode rebuilds only once")
    func persistentFailureEpisodeRebuildsOnlyOnce() {
        var consecutiveFailures = 0
        var alreadyRebuilt = false
        var rebuildCount = 0

        func recordFailure() {
            consecutiveFailures += 1
            if MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: consecutiveFailures,
                alreadyRebuilt: alreadyRebuilt
            ) {
                rebuildCount += 1
                alreadyRebuilt = true
            }
        }

        for _ in 0 ..< (MenuBarItemManager.controlItemRebuildThreshold * 3) {
            recordFailure()
        }

        #expect(rebuildCount == 1)
    }

    @Test("A successful lookup re-arms recovery")
    func successfulLookupRearmsRecovery() {
        let threshold = MenuBarItemManager.controlItemRebuildThreshold

        #expect(MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: threshold))
        #expect(
            !MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: threshold * 2,
                alreadyRebuilt: true
            )
        )
        #expect(MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: threshold))
    }
}

@Suite("Collapsed hidden section recovery")
struct CollapsedHiddenSectionRecoveryTests {
    @Test("Transient collapse readings do not reset the divider")
    func transientCollapseDoesNotRecover() {
        for count in 0 ..< MenuBarItemManager.hiddenSectionCollapseRecoveryThreshold {
            #expect(!MenuBarItemManager.shouldRecoverCollapsedHiddenSection(
                consecutiveCollapsedReadings: count
            ))
        }
    }

    @Test("A persistent collapse resets the divider")
    func persistentCollapseRecovers() {
        #expect(MenuBarItemManager.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: MenuBarItemManager.hiddenSectionCollapseRecoveryThreshold
        ))
    }

    @Test("A collapse episode recovers only once")
    func collapseEpisodeRecoversOnce() {
        #expect(!MenuBarItemManager.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: MenuBarItemManager.hiddenSectionCollapseRecoveryThreshold + 10,
            alreadyRecovered: true
        ))
    }

    @Test("A custom collapse threshold is respected")
    func customThresholdIsRespected() {
        #expect(!MenuBarItemManager.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: 1,
            threshold: 2
        ))
        #expect(MenuBarItemManager.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: 2,
            threshold: 2
        ))
    }
}

@Suite("Parked hidden divider recovery")
struct ParkedHiddenDividerRecoveryTests {
    @Test("The first parked mismatch is left alone")
    func firstMismatchDoesNotRecover() {
        #expect(!MenuBarItemManager.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: 1
        ))
    }

    @Test("A repeated parked mismatch resets the divider")
    func repeatedMismatchRecovers() {
        #expect(MenuBarItemManager.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: MenuBarItemManager.parkedHiddenDividerRecoveryThreshold
        ))
    }

    @Test("A parked mismatch episode resets the divider only once")
    func mismatchEpisodeRecoversOnce() {
        #expect(!MenuBarItemManager.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: MenuBarItemManager.parkedHiddenDividerRecoveryThreshold + 10,
            alreadyRecovered: true
        ))
    }

    /// Models the manager's own episode latch for the parked-divider
    /// recovery: mismatches accumulate, recovery fires once at the
    /// threshold, and no second recovery is allowed until a mismatch=0
    /// reading re-arms the streak.
    @Test("A persistent parked-mismatch episode recovers only once, then re-arms on zero")
    func mismatchEpisodeRearmsOnZero() {
        var consecutiveMismatches = 0
        var alreadyRecovered = false
        var recoverCount = 0

        func recordMismatch() {
            consecutiveMismatches += 1
            if MenuBarItemManager.shouldRecoverParkedHiddenDivider(
                consecutiveMismatchReadings: consecutiveMismatches,
                alreadyRecovered: alreadyRecovered
            ) {
                recoverCount += 1
                alreadyRecovered = true
            }
        }

        func recordZero() {
            consecutiveMismatches = 0
            alreadyRecovered = false
        }

        // Accumulate well past the threshold: only one recovery.
        for _ in 0 ..< (MenuBarItemManager.parkedHiddenDividerRecoveryThreshold * 3) {
            recordMismatch()
        }
        #expect(recoverCount == 1)

        // A mismatch=0 reading re-arms the episode.
        recordZero()
        #expect(!alreadyRecovered)
        #expect(consecutiveMismatches == 0)

        // The next episode can recover again.
        for _ in 0 ..< MenuBarItemManager.parkedHiddenDividerRecoveryThreshold {
            recordMismatch()
        }
        #expect(recoverCount == 2)
    }

    /// Below the threshold the streak accumulates without triggering
    /// recovery, so a single transient mismatch does not recreate the
    /// divider.
    @Test("Below the threshold, mismatches accumulate without recovery")
    func belowThresholdMismatchesAccumulate() {
        for count in 1 ..< (MenuBarItemManager.parkedHiddenDividerRecoveryThreshold) {
            #expect(
                !MenuBarItemManager.shouldRecoverParkedHiddenDivider(
                    consecutiveMismatchReadings: count
                ),
                "consecutiveMismatchReadings=\(count) should not yet trigger recovery"
            )
        }
    }

    /// A custom threshold is respected, so the recovery can be tuned
    /// independently of the collapsed-section threshold.
    @Test("A custom parked-mismatch threshold is respected")
    func customThresholdIsRespected() {
        #expect(!MenuBarItemManager.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: 2,
            threshold: 3
        ))
        #expect(MenuBarItemManager.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: 3,
            threshold: 3
        ))
    }
}

/// Covers the seed-position half of both divider rebuilds (#958).
///
/// A rebuild used to write `preflightSetup`'s fresh-install seed
/// unconditionally, through the same guard-bypassing route that reopened
/// #895/#890. On a populated bar that drops the rebuilt divider on one side of
/// every managed item and the following cache pass reads the whole bar into one
/// section. nk-tedo-001's log has the shape exactly: one rebuild in five hours,
/// visible section 12 items before it and 1 item three seconds after, and three
/// earlier off-screen parkings that never rebuilt and never collapsed.
@Suite("Rebuilt divider seed position")
struct RebuiltDividerSeedPositionTests {
    @Test("An empty bar still gets the fresh-install seed")
    func emptyBarKeepsTheSeed() {
        #expect(MenuBarItemManager.canSeedRebuiltDividerPosition(managedItemCount: 0))
        #expect(MenuBarItemManager.seedPositionForRebuiltDivider(managedItemCount: 0) == 1)
    }

    @Test("A single managed item is enough to withhold the seed")
    func oneItemWithholdsTheSeed() {
        #expect(!MenuBarItemManager.canSeedRebuiltDividerPosition(managedItemCount: 1))
        #expect(MenuBarItemManager.seedPositionForRebuiltDivider(managedItemCount: 1) == nil)
    }

    /// The reported bar. Nothing about the count itself is special; the point
    /// is that the populated case never reaches the stamp.
    @Test("The reported bar withholds the seed")
    func reportedBarWithholdsTheSeed() {
        for count in 1 ... 38 {
            #expect(
                MenuBarItemManager.seedPositionForRebuiltDivider(managedItemCount: count) == nil,
                "managedItemCount=\(count) must not re-stamp the seed"
            )
        }
    }

    /// The gate is about what a rebuild would strand, so it reads the count
    /// and nothing else. A negative count cannot occur, but answering "seed
    /// it" for one would put the destructive branch behind an arithmetic slip.
    @Test("A nonsensical count does not unlock the seed")
    func negativeCountDoesNotSeed() {
        #expect(!MenuBarItemManager.canSeedRebuiltDividerPosition(managedItemCount: -1))
        #expect(MenuBarItemManager.seedPositionForRebuiltDivider(managedItemCount: -1) == nil)
    }

    /// The two branches have to be distinguishable in a field log, because
    /// telling them apart is what separated cause from symptom in #958.
    @Test("The log fragment names which branch ran")
    func logFragmentNamesTheBranch() {
        let seeded = MenuBarItemManager.seedDescription(1)
        let kept = MenuBarItemManager.seedDescription(nil)
        #expect(seeded.contains("seeded position"))
        #expect(kept.contains("stored position"))
        #expect(seeded != kept)
    }
}

/// Covers the retry backoff #933 asked for: a permanently failing lookup
/// left the window-ID snapshot uncommitted, so the change detector re-ran
/// a full recache on every 3-second poll for 27 hours straight. The
/// backoff keeps startup transients fast, then decays the retry cadence
/// toward a bounded ceiling so recovery stays automatic without the churn.
@Suite("Control item lookup retry backoff")
struct ControlItemLookupRetryBackoffTests {
    @Test("Below the rebuild threshold there is no backoff")
    func belowThresholdHasNoBackoff() {
        for count in 0 ..< MenuBarItemManager.controlItemRebuildThreshold {
            #expect(
                MenuBarItemManager.controlItemLookupRetryBackoff(consecutiveFailures: count) == nil,
                "consecutiveFailures=\(count) should not yet delay retries"
            )
        }
    }

    @Test("Past the threshold the backoff doubles per failure")
    func backoffDoublesPerFailure() {
        let threshold = MenuBarItemManager.controlItemRebuildThreshold
        #expect(MenuBarItemManager.controlItemLookupRetryBackoff(
            consecutiveFailures: threshold
        ) == .seconds(6))
        #expect(MenuBarItemManager.controlItemLookupRetryBackoff(
            consecutiveFailures: threshold + 1
        ) == .seconds(12))
        #expect(MenuBarItemManager.controlItemLookupRetryBackoff(
            consecutiveFailures: threshold + 2
        ) == .seconds(24))
        #expect(MenuBarItemManager.controlItemLookupRetryBackoff(
            consecutiveFailures: threshold + 3
        ) == .seconds(48))
    }

    /// The ceiling is what turns a permanent failure into one bounded
    /// retry per minute instead of an ever-rarer one: the bar can still
    /// heal itself (display reattached, WindowServer settled) without the
    /// user relaunching.
    @Test("The backoff is capped so retries never stop")
    func backoffIsCapped() {
        let threshold = MenuBarItemManager.controlItemRebuildThreshold
        for extra in [4, 5, 10, 1000] {
            #expect(
                MenuBarItemManager.controlItemLookupRetryBackoff(
                    consecutiveFailures: threshold + extra
                ) == .seconds(60),
                "consecutiveFailures=threshold+\(extra) should sit at the cap"
            )
        }
    }

    @Test("Custom delays are respected")
    func customDelaysAreRespected() {
        #expect(MenuBarItemManager.controlItemLookupRetryBackoff(
            consecutiveFailures: 5,
            threshold: 5,
            baseDelay: .seconds(1),
            maxDelay: .seconds(3)
        ) == .seconds(1))
        #expect(MenuBarItemManager.controlItemLookupRetryBackoff(
            consecutiveFailures: 7,
            threshold: 5,
            baseDelay: .seconds(1),
            maxDelay: .seconds(3)
        ) == .seconds(3))
    }
}

@Suite("Missing always-hidden divider recovery")
struct MissingAlwaysHiddenDividerRecoveryTests {
    @Test("The first missing reading is left alone")
    func firstMissingReadingDoesNotRecover() {
        #expect(!MenuBarItemManager.shouldRecoverMissingAlwaysHiddenDivider(
            consecutiveMissingReadings: 1
        ))
    }

    @Test("Repeated missing readings recreate the divider")
    func repeatedMissingReadingsRecover() {
        #expect(MenuBarItemManager.shouldRecoverMissingAlwaysHiddenDivider(
            consecutiveMissingReadings: MenuBarItemManager.missingAlwaysHiddenDividerRecoveryThreshold
        ))
    }

    @Test("A missing-divider episode recreates only once")
    func missingEpisodeRecoversOnce() {
        #expect(!MenuBarItemManager.shouldRecoverMissingAlwaysHiddenDivider(
            consecutiveMissingReadings: MenuBarItemManager.missingAlwaysHiddenDividerRecoveryThreshold + 10,
            alreadyRecovered: true
        ))
    }

    /// Models the manager's own episode latch: missing readings accumulate,
    /// recovery fires once at the threshold, and no second recovery is
    /// allowed until a resolved reading re-arms the streak.
    @Test("A persistent missing episode recovers only once, then re-arms on resolution")
    func missingEpisodeRearmsOnResolution() {
        var consecutiveMissing = 0
        var alreadyRecovered = false
        var recoverCount = 0

        func recordMissing() {
            consecutiveMissing += 1
            if MenuBarItemManager.shouldRecoverMissingAlwaysHiddenDivider(
                consecutiveMissingReadings: consecutiveMissing,
                alreadyRecovered: alreadyRecovered
            ) {
                recoverCount += 1
                alreadyRecovered = true
            }
        }

        func recordResolved() {
            consecutiveMissing = 0
            alreadyRecovered = false
        }

        // The #863 field log: alwaysHidden=nil on every cycle for 12+ hours.
        for _ in 0 ..< (MenuBarItemManager.missingAlwaysHiddenDividerRecoveryThreshold * 4) {
            recordMissing()
        }
        #expect(recoverCount == 1)

        // The divider comes back (replug, rebuild): the episode re-arms.
        recordResolved()
        for _ in 0 ..< MenuBarItemManager.missingAlwaysHiddenDividerRecoveryThreshold {
            recordMissing()
        }
        #expect(recoverCount == 2)
    }

    /// A disabled always-hidden section has no divider by choice. The
    /// orchestrator resets the streak in that state; this pins the decision
    /// function's contract that only enabled-section readings reach it.
    @Test("A custom threshold is respected")
    func customThresholdIsRespected() {
        #expect(!MenuBarItemManager.shouldRecoverMissingAlwaysHiddenDivider(
            consecutiveMissingReadings: 1,
            threshold: 2
        ))
        #expect(MenuBarItemManager.shouldRecoverMissingAlwaysHiddenDivider(
            consecutiveMissingReadings: 2,
            threshold: 2
        ))
    }
}
