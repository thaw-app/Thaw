//
//  MenuBarItemImageCache+FailedCaptures.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Darwin.malloc
import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Failed Capture Management

    /// Whether a capture of item would currently be attempted, rather than
    /// skipped because it's blacklisted after repeated failures. The Thaw Bar
    /// uses this to avoid revealing (and flashing) the menu bar for an item that
    /// can't be captured anyway.
    nonisolated func wouldAttemptCapture(of item: MenuBarItem) -> Bool {
        !shouldSkipCapture(for: item)
    }

    nonisolated func shouldSkipCapture(for item: MenuBarItem) -> Bool {
        failedCapturesLock.withLock { dict in
            guard let failed = dict[item.tag] else {
                return false
            }

            if failed.failureCount >= Self.maxFailuresBeforeBlacklist {
                let timeSinceFailure = Date().timeIntervalSince(
                    failed.lastFailureTime
                )
                if timeSinceFailure < Self.blacklistCooldownSeconds {
                    return true
                } else {
                    dict.removeValue(forKey: item.tag)
                    return false
                }
            }

            return false
        }
    }

    /// Forgets recorded failures for the given tags so the next attempt is made
    /// fresh, used by the paths where a user is waiting on the image.
    nonisolated func clearCaptureFailures(tags: Set<MenuBarItemTag>) {
        guard !tags.isEmpty else { return }
        failedCapturesLock.withLock { dict in
            for tag in tags {
                dict.removeValue(forKey: tag)
            }
        }
    }

    nonisolated func recordCaptureFailure(for item: MenuBarItem) {
        guard !screenIsLocked() else { return }
        let now = Date()
        failedCapturesLock.withLock { dict in
            let existing = dict[item.tag]

            if let existing {
                let sinceLastFailure = now.timeIntervalSince(existing.lastFailureTime)
                if sinceLastFailure < Self.minimumFailureSpacingSeconds {
                    // Same reflow blip as the last recorded failure, refresh
                    // the timestamp so the blacklist cutoff still tracks the
                    // most recent glitch, but don't count it as a new strike.
                    dict[item.tag] = FailedCapture(
                        tag: item.tag,
                        failureCount: existing.failureCount,
                        lastFailureTime: now
                    )
                } else {
                    let newCount = existing.failureCount + 1
                    dict[item.tag] = FailedCapture(
                        tag: item.tag,
                        failureCount: newCount,
                        lastFailureTime: now
                    )

                    if newCount == Self.maxFailuresBeforeBlacklist {
                        MenuBarItemImageCache.diagLog.info(
                            "Item blacklisted after \(newCount) failures: \(item.logString) (will retry after \(Self.blacklistCooldownSeconds)s cooldown)"
                        )
                    }
                }
            } else {
                dict[item.tag] = FailedCapture(
                    tag: item.tag,
                    failureCount: 1,
                    lastFailureTime: now
                )
            }

            let cutoff = now.addingTimeInterval(-Self.blacklistCooldownSeconds)
            dict = dict.filter { _, failed in
                failed.lastFailureTime > cutoff
            }
        }
    }

    /// Records a successful capture for an item (resets failure count).
    nonisolated func recordCaptureSuccess(for item: MenuBarItem) {
        let recovered = failedCapturesLock.withLock { dict in
            dict.removeValue(forKey: item.tag)
        }
        if let existing = recovered, existing.failureCount >= 2 {
            MenuBarItemImageCache.diagLog.info(
                "Item recovered after \(existing.failureCount) previous failures: \(item.logString)"
            )
        }
    }

    /// Applies the strikes and recoveries a pass observed. Call only once the
    /// pass is cleared to publish, so a discarded capture neither strikes nor
    /// forgives an item.
    nonisolated func commitCaptureLedger(of pass: CapturePass) {
        // Ahead of the strikes: a forgiven item that failed again keeps the
        // one strike this pass gave it.
        clearCaptureFailures(tags: pass.forgivenTags)
        for item in pass.failedCaptureItems {
            recordCaptureFailure(for: item)
        }
        for item in pass.recoveredItems {
            recordCaptureSuccess(for: item)
        }
    }

    func handleMemoryPressure() {
        if !capturesByTag.isEmpty {
            let targetSize = capturesByTag.count / 2
            let removeCount = capturesByTag.count - targetSize
            let tagsToRemove = leastRecentlyUsedTags(count: removeCount)

            for tag in tagsToRemove {
                removeCapture(for: tag)
                accessTimestamps.removeValue(forKey: tag)
            }
            MenuBarItemImageCache.diagLog.info(
                "Memory pressure: Cleared \(tagsToRemove.count) items from cache"
            )
        }
    }

    /// Schedules the cache flush and full purge after a period with no visible image consumer.
    func scheduleIdleTrim() {
        idleTrimTask?.cancel()
        idleTrimTask = Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemImageCache.idleTrimDelay)
            guard !Task.isCancelled, let self else { return }
            await self.trimForIdle()
        }
    }

    /// Whether a settings pane that draws glyphs is still on screen while another app is
    /// frontmost. The live refresh rests then, but the pane keeps drawing the cache, so a
    /// trim would turn every visible item into its app icon until Thaw is focused again.
    @MainActor
    func hasUnfocusedCaptureConsumer() -> Bool {
        hasUnfocusedCaptureConsumer(nav: makeNavigationStateSnapshot())
    }

    func hasUnfocusedCaptureConsumer(nav: NavigationStateSnapshot) -> Bool {
        hasActiveImageConsumer(nav: nav)
    }

    /// Flushes dirty captures to disk, purges every in-memory cached CGImage (including
    /// concealed items), and returns freed pages to the system allocator.
    @MainActor
    func trimForIdle() async {
        guard !hasActiveImageConsumer else { return }

        let snapshot = Self.diskPersistableCaptures(
            capturesByTag: capturesByTag,
            accessTimestamps: accessTimestamps
        )
        let concealed = appState.map(concealedIdentifiers(in:)) ?? []
        if !snapshot.isEmpty {
            diskStore.enqueueSave(snapshot, concealedIdentifiers: concealed)
            await diskStore.flush()
        }

        guard !Task.isCancelled, !hasActiveImageConsumer else { return }
        purgeAllCapturesForIdle()
    }

    @MainActor
    func purgeAllCapturesForIdle() {
        let droppedImages = capturesByTag.count
        removeAllCaptures()
        accessTimestamps.removeAll()
        let droppedFailures = failedCapturesLock.withLock { dict in
            let count = dict.count
            dict.removeAll()
            return count
        }
        pruneDeadGlyphSlots()
        OverflowFallbackIcon.clearCache()
        MenuBarItemDisplayName.clear()
        hasLoadedFromDisk = false
        invalidateDiskLoad()
        malloc_zone_pressure_relief(nil, 0)
        MenuBarItemImageCache.diagLog.info(
            "Idle trim: flushed to disk and purged all \(droppedImages) cached images and \(droppedFailures) failure records"
        )
    }

    /// Returns the count least recently used tags, sorted by access time (oldest first).
    func leastRecentlyUsedTags(
        count: Int,
        excluding excludedTags: Set<MenuBarItemTag> = []
    ) -> [MenuBarItemTag] {
        let candidates: [(tag: MenuBarItemTag, timestamp: UInt64)] = if excludedTags.isEmpty {
            capturesByTag.keys.map { ($0, accessTimestamps[$0] ?? 0) }
        } else {
            capturesByTag.keys
                .filter { !excludedTags.contains($0) }
                .map { ($0, accessTimestamps[$0] ?? 0) }
        }
        return candidates
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(count)
            .map(\.tag)
    }
}
