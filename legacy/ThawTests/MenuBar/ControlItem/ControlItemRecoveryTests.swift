//
//  ControlItemRecoveryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers the escalation decision that gates rebuilding the control items
/// (#754): on macOS 26 with multiple displays, `ControlItemPair` lookup in
/// `cacheItemsRegardless` can start failing permanently after long uptime.
///
/// The re-arming half (a failed lookup no longer commits `itemWindowIDs` to
/// `CacheActor`) has no reachable seam, since `CacheActor` is private. The
/// window-ID cache updates in `cacheItemsRegardless` must run only after the
/// `ControlItemPair` guard succeeds.
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

    /// Models the parked-divider episode latch: recovery fires once at the
    /// threshold and re-arms only after a mismatch=0 reading.
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

    /// A single transient mismatch must not recreate the divider.
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
/// A rebuild used to write the fresh-install seed unconditionally. On a
/// populated bar that drops the divider on one side of every managed item,
/// and the next cache pass reads the whole bar into one section.
@Suite("Rebuilt divider seed position")
struct RebuiltDividerSeedPositionTests {
    /// A healthy populated bar: visible rightmost, always-hidden leftmost,
    /// hidden between them. Larger preferred position means further left.
    private static let orderedPositions = MenuBarItemManager.StoredDividerPositions(
        visible: 1008,
        hidden: 1021,
        alwaysHidden: 1034
    )

    /// #978's plist. H_ctrl autosaved far left of AH_ctrl, which reads as a
    /// zero-width hidden section.
    private static let invertedPositions = MenuBarItemManager.StoredDividerPositions(
        visible: 1008,
        hidden: 6866,
        alwaysHidden: 1034
    )

    @Test("An empty bar still gets the fresh-install seed")
    func emptyBarKeepsTheSeed() {
        #expect(MenuBarItemManager.canSeedRebuiltDividerPosition(managedItemCount: 0))
        #expect(MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: 0,
            storedPositions: Self.orderedPositions
        ) == .freshInstall(1))
    }

    /// Nothing is stranded on an empty bar, so an inverted position there is
    /// just stale and the seed still applies.
    @Test("An empty bar takes the seed even from an inverted position")
    func emptyBarSeedsOverInversion() {
        #expect(MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: 0,
            storedPositions: Self.invertedPositions
        ) == .freshInstall(1))
    }

    @Test("A single managed item is enough to withhold the seed")
    func oneItemWithholdsTheSeed() {
        #expect(!MenuBarItemManager.canSeedRebuiltDividerPosition(managedItemCount: 1))
        #expect(MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: 1,
            storedPositions: Self.orderedPositions
        ) == .keepStored)
    }

    /// A populated bar with a sane stored position never reaches the stamp.
    @Test("The reported bar withholds the seed")
    func reportedBarWithholdsTheSeed() {
        for count in 1 ... 38 {
            #expect(
                MenuBarItemManager.seedForRebuiltDivider(
                    managedItemCount: count,
                    storedPositions: Self.orderedPositions
                ) == .keepStored,
                "managedItemCount=\(count) must not re-stamp the seed"
            )
        }
    }

    /// A negative count cannot occur, but seeding on one would put the
    /// destructive branch behind an arithmetic slip.
    @Test("A nonsensical count does not unlock the seed")
    func negativeCountDoesNotSeed() {
        #expect(!MenuBarItemManager.canSeedRebuiltDividerPosition(managedItemCount: -1))
        #expect(MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: -1,
            storedPositions: Self.orderedPositions
        ) == .keepStored)
    }

    /// The three branches must be distinguishable in a field log.
    @Test("The log fragment names which branch ran")
    func logFragmentNamesTheBranch() {
        let seeded = MenuBarItemManager.seedDescription(.freshInstall(1))
        let kept = MenuBarItemManager.seedDescription(.keepStored)
        let repaired = MenuBarItemManager.seedDescription(.repaired(1021))
        #expect(seeded.contains("seeded position"))
        #expect(kept.contains("stored position"))
        #expect(repaired.contains("repaired position"))
        #expect(Set([seeded, kept, repaired]).count == 3)
    }
}

/// Covers the inverted-position half of the parked-divider rebuild (#978).
///
/// Keeping the stored position on a populated bar is only right while it
/// still orders the dividers. macOS can autosave `Hidden = 6866` against
/// `AlwaysHidden = 1034`, and restoring that strands the divider on relaunch.
@Suite("Stored divider position ordering (#978)")
struct StoredDividerPositionOrderingTests {
    private static func positions(
        visible: CGFloat? = nil,
        hidden: CGFloat? = nil,
        alwaysHidden: CGFloat? = nil
    ) -> MenuBarItemManager.StoredDividerPositions {
        MenuBarItemManager.StoredDividerPositions(
            visible: visible,
            hidden: hidden,
            alwaysHidden: alwaysHidden
        )
    }

    @Test("A healthy bar's stored positions read as ordered")
    func healthyPositionsAreOrdered() {
        #expect(MenuBarItemManager.storedHiddenPositionIsOrdered(
            Self.positions(visible: 1008, hidden: 1021, alwaysHidden: 1034)
        ))
    }

    @Test("#978's plist reads as inverted")
    func reportedPlistIsInverted() {
        #expect(!MenuBarItemManager.storedHiddenPositionIsOrdered(
            Self.positions(visible: 1008, hidden: 6866, alwaysHidden: 1034)
        ))
    }

    /// The always-hidden section is optional, so its position is often
    /// absent. H_ctrl must still sit left of the visible item.
    @Test("Without an always-hidden divider, only the visible bound applies")
    func visibleBoundAloneStillApplies() {
        #expect(MenuBarItemManager.storedHiddenPositionIsOrdered(
            Self.positions(visible: 0, hidden: 1)
        ))
        #expect(!MenuBarItemManager.storedHiddenPositionIsOrdered(
            Self.positions(visible: 1008, hidden: 1008)
        ))
    }

    /// Reporting an unknown position as inverted would hand the rebuild a
    /// repair it has no evidence for.
    @Test("Unknown positions do not read as inverted")
    func unknownPositionsAreOrdered() {
        #expect(MenuBarItemManager.storedHiddenPositionIsOrdered(Self.positions()))
        #expect(MenuBarItemManager.storedHiddenPositionIsOrdered(Self.positions(hidden: 6866)))
        #expect(MenuBarItemManager.storedHiddenPositionIsOrdered(
            Self.positions(visible: 1008, hidden: 6866)
        ))
    }

    /// The repair restores ordering, nothing else. Walking the divider to the
    /// saved boundary is the follow-up apply's job.
    @Test("The repair lands between the two chevrons")
    func repairLandsBetweenTheChevrons() {
        let repaired = MenuBarItemManager.repairedHiddenDividerPosition(
            Self.positions(visible: 1008, hidden: 6866, alwaysHidden: 1034)
        )
        #expect(repaired == 1021)
        #expect(repaired.map { $0 > 1008 && $0 < 1034 } == true)
    }

    @Test("Without an always-hidden divider the repair clears the visible item")
    func repairClearsTheVisibleItem() {
        #expect(MenuBarItemManager.repairedHiddenDividerPosition(
            Self.positions(visible: 1008, hidden: 12)
        ) == 1009)
    }

    /// With both neighbours corrupt there is nothing to interpolate between,
    /// so the rebuild keeps the stored position.
    @Test("Corrupt neighbours withhold the repair")
    func corruptNeighboursWithholdTheRepair() {
        #expect(MenuBarItemManager.repairedHiddenDividerPosition(
            Self.positions(visible: 2000, hidden: 6866, alwaysHidden: 1034)
        ) == nil)
        #expect(MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: 38,
            storedPositions: Self.positions(visible: 2000, hidden: 6866, alwaysHidden: 1034)
        ) == .keepStored)
    }

    /// A populated bar with an inverted stored position gets it replaced, not restored.
    @Test("A populated bar with an inverted position gets a repaired seed")
    func populatedBarRepairsTheInversion() {
        #expect(MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: 38,
            storedPositions: Self.positions(visible: 1008, hidden: 6866, alwaysHidden: 1034)
        ) == .repaired(1021))
    }
}

/// Covers the retry backoff (#933). A permanently failing lookup made the
/// change detector re-run a full recache on every 3-second poll. The backoff
/// keeps startup retries fast, then decays toward a bounded ceiling.
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

    /// The ceiling keeps a permanent failure at one retry per minute, so the
    /// bar can still heal itself (display reattached, WindowServer settled).
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

    /// Models the episode latch: recovery fires once at the threshold and
    /// re-arms only after a resolved reading.
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

        // alwaysHidden=nil on every cycle for hours (#863).
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

    /// A disabled always-hidden section has no divider by choice; the
    /// orchestrator resets the streak then, so only enabled-section readings
    /// reach this function.
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

@Suite("Control Center relaunch grace")
struct ControlCenterRelaunchGraceTests {
    private func generation(pid: pid_t, launchedAt seconds: TimeInterval) -> ProcessGeneration {
        ProcessGeneration(
            pid: pid,
            launchDate: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("Re-hosting failures do not advance divider recovery")
    func failuresInsideGraceAreIgnored() {
        #expect(!MenuBarItemManager.shouldCountControlItemLookupFailure(hostUptime: .zero))
        #expect(!MenuBarItemManager.shouldCountControlItemLookupFailure(
            hostUptime: MenuBarItemManager.controlCenterRelaunchGrace - .milliseconds(1)
        ))
    }

    @Test("Failures after the grace period still recover missing dividers")
    func failuresAfterGraceAreCounted() {
        #expect(MenuBarItemManager.shouldCountControlItemLookupFailure(
            hostUptime: MenuBarItemManager.controlCenterRelaunchGrace
        ))
        #expect(MenuBarItemManager.shouldCountControlItemLookupFailure(hostUptime: nil))
    }

    @Test("Layout-editor refreshes never advance missing-control recovery")
    func layoutEditorRefreshDoesNotCount() {
        #expect(!MenuBarItemManager.shouldCountControlItemLookupFailure(
            hostUptime: nil,
            suppressAutomaticMoves: true
        ))
        #expect(!MenuBarItemManager.shouldCountControlItemLookupFailure(
            hostUptime: .seconds(3600),
            suppressAutomaticMoves: true
        ))
    }

    @Test("A custom grace period is respected")
    func customGraceIsRespected() {
        #expect(!MenuBarItemManager.shouldCountControlItemLookupFailure(
            hostUptime: .seconds(4),
            grace: .seconds(5)
        ))
        #expect(MenuBarItemManager.shouldCountControlItemLookupFailure(
            hostUptime: .seconds(5),
            grace: .seconds(5)
        ))
    }

    @Test("The newest host generation wins regardless of application ordering")
    func newestHostGenerationWins() {
        let retiring = generation(pid: 100, launchedAt: 1000)
        let current = generation(pid: 200, launchedAt: 2000)

        #expect(SourcePIDSeedStore.newestGeneration(
            in: [current, retiring]
        ) == current)
        #expect(SourcePIDSeedStore.newestGeneration(
            in: [retiring, current]
        ) == current)
    }

    @Test("A new host generation re-arms a spent recovery episode")
    func newHostRearmsSpentEpisode() {
        let previous = generation(pid: 100, launchedAt: 1000)
        let current = generation(pid: 200, launchedAt: 2000)
        var failureStreak = MenuBarItemManager.controlItemRebuildThreshold + 4
        var alreadyRebuilt = true

        #expect(MenuBarItemManager.resetControlItemLookupEpisodeIfHostChanged(
            previous: previous,
            current: current,
            failureStreak: &failureStreak,
            alreadyRebuilt: &alreadyRebuilt
        ))
        #expect(failureStreak == 0)
        #expect(!alreadyRebuilt)

        failureStreak = 2
        #expect(!MenuBarItemManager.resetControlItemLookupEpisodeIfHostChanged(
            previous: current,
            current: current,
            failureStreak: &failureStreak,
            alreadyRebuilt: &alreadyRebuilt
        ))
        #expect(failureStreak == 2)
    }
}
