//
//  MenuBarItemImageCache+FailedCaptures.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
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

    /// Schedules the cache drop that follows a period with nothing on
    /// screen to read it.
    ///
    /// Captured images are only ever displayed by the Thaw Bar, the search
    /// panel and two settings panes. While none of those is up the cache is
    /// pure resident memory, and on a Mac left alone that is most of the
    /// time. Reopening a panel inside the delay finds the cache intact;
    /// after it, the panel refills visible-section glyphs through the same
    /// loading path it already shows on a cold launch. Concealed-section
    /// glyphs are kept across the trim (see trimForIdle()).
    func scheduleIdleTrim() {
        idleTrimTask?.cancel()
        idleTrimTask = Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemImageCache.idleTrimDelay)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard !self.hasVisibleCaptureConsumer() else { return }
                self.trimForIdle()
            }
        }
    }

    /// Drops the cache, except for glyphs only a reveal can refill, and hands
    /// the freed pages back to the system.
    ///
    /// Visible-section images are cheap to recapture: the live refresh loop
    /// screenshots the bar it can already see. An image for an item in a
    /// concealed section (Hidden / Always Hidden on macOS 27) is not: the only
    /// way to get it is to reveal the item on the real menu bar, and a trim
    /// that dropped those made every Thaw Bar open after 30 s idle replay the
    /// whole reveal parade. Those entries stay; they are a few dozen small
    /// crops at most.
    ///
    /// The one-time disk load is also re-armed so the next consumer open
    /// fills any remaining gap from disk (subject to the per-item TTL) before
    /// resorting to a reveal.
    ///
    /// Releasing the images returns their pages to the allocator, which
    /// holds on to the address space by default; the pressure-relief call
    /// is what actually shrinks the process's footprint rather than just
    /// its live set.
    private func trimForIdle() {
        let survivors = Self.idleTrimSurvivors(
            cachedTags: capturesByTag.keys,
            concealedTags: concealedItemTags()
        )
        let droppedImages = capturesByTag.count - survivors.count
        if survivors.isEmpty {
            removeAllCaptures()
            accessTimestamps.removeAll()
        } else {
            keepCaptures { tag, _ in survivors.contains(tag) }
            accessTimestamps = accessTimestamps.filter { survivors.contains($0.key) }
        }
        let droppedFailures = failedCapturesLock.withLock { dict in
            let count = dict.count
            dict.removeAll()
            return count
        }
        hasLoadedFromDisk = false
        invalidateDiskLoad()
        malloc_zone_pressure_relief(nil, 0)
        MenuBarItemImageCache.diagLog.info(
            "Idle trim: dropped \(droppedImages) cached images and \(droppedFailures) failure records; kept \(survivors.count) images for concealed items (refilling those needs a reveal on the live bar)"
        )
    }

    /// Tags of every item currently in a concealed section, or nothing when no
    /// section engine is running (pre-macOS 27, where hidden items are still
    /// on the bar and cheap to recapture).
    private func concealedItemTags() -> [MenuBarItemTag] {
        guard let appState, appState.menuBarManager.sectionController.isOperational else {
            return []
        }
        let itemCache = appState.itemManager.itemCache
        return [MenuBarSection.Name.hidden, .alwaysHidden].flatMap { itemCache[$0].map(\.tag) }
    }

    /// The cached tags an idle trim keeps: those naming an item in
    /// concealedTags.
    ///
    /// Matching ignores the window ID because the two sides are keyed
    /// differently: the item cache carries live window IDs while disk-loaded
    /// captures (and system items) carry none.
    static nonisolated func idleTrimSurvivors(
        cachedTags: some Sequence<MenuBarItemTag>,
        concealedTags: [MenuBarItemTag]
    ) -> Set<MenuBarItemTag> {
        guard !concealedTags.isEmpty else { return [] }
        return Set(cachedTags.filter { cached in
            concealedTags.contains { $0.matchesIgnoringWindowID(cached) }
        })
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
