//
//  MenuBarItemImageCache+Recapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawCapture

extension MenuBarItemImageCache {
    // MARK: Recapture Entry Points

    /// Resolves which requested sections currently have live menu-bar pixels
    /// available for capture. macOS 27 physically removes concealed items from
    /// MenuBarAgent, but temporarily revealed sections can and should be
    /// captured so their real glyphs remain cached after concealment resumes.
    static nonisolated func capturableSections(
        from requestedSections: [MenuBarSection.Name],
        usesVisibilityRestrictions: Bool,
        revealedSection: MenuBarSection.Name?
    ) -> [MenuBarSection.Name] {
        return MenuBarBackendProvider
            .backend(usesVisibilityRestrictions: usesVisibilityRestrictions)
            .capturableSections(
                from: requestedSections,
                revealedSection: revealedSection
            )
    }

    /// Captures sections now, skipping the visibility and recent-activity
    /// tests that recaptureIfWarranted(sections:skipRecentMoveCheck:allowBackgroundCapture:nav:)
    /// applies. This is the unconditional door, for callers that already know a
    /// capture is wanted; the in-flight guards below still apply, so a pass that
    /// finishes after the bar moved is thrown away rather than published.
    ///
    /// ignoreRecentMove lets a deliberate post-reorder refresh keep its result:
    /// the reorder stamps the move timestamp on verification, so without the
    /// bypass the corrective capture is always discarded and the garbled
    /// pre-reorder images stay on screen. Only pass true after the bar settled.
    ///
    /// Returns whether the pass changed anything a consumer could see, which the
    /// live refresh loop uses to back its tick rate off while the bar is static.
    /// Guard exits report false so a skipped capture never drives the ladder.
    /// One pass runs at a time; a request arriving mid-pass shares it or waits for one follow-up. See RecaptureDemand.
    @MainActor
    @discardableResult
    func recaptureNow(
        sections: [MenuBarSection.Name],
        ignoreRecentMove: Bool = false
    ) async -> Bool {
        await recaptureCoalescer.run(
            RecaptureDemand(sections: sections, ignoreRecentMove: ignoreRecentMove),
            capturable: { [weak self] in self?.currentlyCapturableSections(from: $0) ?? $0 },
            pass: { [weak self] demand in
                await self?.runRecapturePass(
                    sections: demand.sections,
                    ignoreRecentMove: demand.ignoreRecentMove
                ) ?? false
            }
        )
    }

    /// The requested sections with live pixels right now; all of them before activation.
    @MainActor
    private func currentlyCapturableSections(
        from sections: [MenuBarSection.Name]
    ) -> [MenuBarSection.Name] {
        guard let appState else { return sections }
        return MenuBarBackendProvider.current.capturableSections(
            from: sections,
            revealedSection: appState.menuBarManager.sectionController.revealedSection
        )
    }

    /// Why a capture admitted earlier may no longer publish, or nil if it still may.
    ///
    /// recapture passes also honour the reset flag and the move cooldown; the
    /// grouped prewarm reveals items itself and answers only to layout and display.
    @MainActor
    private func publicationRejection(
        of admission: CapturePublicationAdmission,
        appState: AppState,
        ignoreRecentMove: Bool,
        isRecapturePass: Bool = true
    ) -> CapturePublicationPolicy.Rejection? {
        CapturePublicationPolicy.rejection(
            of: admission,
            layout: appState.itemManager.layoutPublication,
            displayID: appState.itemManager.itemDisplayID,
            isResettingLayout: isRecapturePass && appState.itemManager.isResettingLayout,
            moveWithinCooldown: isRecapturePass && moveActivity?.occurred(within: .seconds(2)) == true,
            ignoreRecentMove: ignoreRecentMove
        )
    }

    /// One uncoalesced pass; reach it through recaptureNow(sections:ignoreRecentMove:).
    @MainActor
    private func runRecapturePass(
        sections: [MenuBarSection.Name],
        ignoreRecentMove: Bool
    ) async -> Bool {
        // False backs the live loop off toward its 1 Hz floor while locked; the
        // first tick after the unlock captures again.
        guard !skipCaptureWhileScreenLocked("recaptureNow") else {
            return false
        }
        guard let appState else {
            MenuBarItemImageCache.diagLog.warning("recaptureNow: appState is nil, aborting")
            return false
        }

        let hasScreenRecording = appState.isPermissionGranted(.screenRecording)
        guard hasScreenRecording else {
            MenuBarItemImageCache.diagLog.debug("recaptureNow: no screen recording permission, aborting")
            return false
        }

        guard let displayID = appState.itemManager.itemDisplayID else {
            // Debug, not warning: at startup the live refresh loop ticks
            // before the first cache pass has assigned the item cache a
            // display, so this fires a handful of times and then never again
            // once the cache settles. Aborting here is the correct action;
            // the next tick succeeds.
            MenuBarItemImageCache.diagLog.debug("recaptureNow: itemCache.displayID is nil, aborting")
            return false
        }

        guard let screen = NSScreen.screens.first(where: {
            $0.displayID == displayID
        }) else {
            MenuBarItemImageCache.diagLog.warning("recaptureNow: no screen found for displayID \(displayID)")
            return false
        }

        guard Self.isMenuBarOnScreen(displayID: displayID) else {
            MenuBarItemImageCache.diagLog.debug(
                "recaptureNow: menu bar on display \(displayID) is off screen; keeping prior images"
            )
            requestInventoryRefresh(reason: "menu bar on display \(displayID) is off screen")
            return false
        }

        let scale = screen.backingScaleFactor

        // Concealed macOS 27 sections have only stale snapshot bounds, so crop
        // them only while RuntimeSectionController has actually revealed their live AX
        // elements. Incomplete / off-window crops clear the prior entry so the
        // app-icon fallback can take over until a complete capture succeeds.
        let sectionsToCapture = currentlyCapturableSections(from: sections)

        // Debug, not notice: the live refresh loop lands here at up to 30 Hz
        // (≥1 Hz even backed off) for as long as any capture consumer is open,
        // and os_log persists .default/notice unconditionally, a persistent
        // system-log write per tick even with the diagnostic file disabled.
        MenuBarItemImageCache.diagLog.debug("recaptureNow: displayID=\(screen.displayID) backingScaleFactor=\(Double(scale)) hasNotch=\(screen.hasNotch) menuBarHeight=\(Double(screen.getMenuBarHeightEstimate())) sections=\(sectionsToCapture.map(\.logString))")

        // Nothing is awaited between the guards above and the admission this
        // call opens with.
        return await runRecapturePass(
            capturing: sectionsToCapture,
            displayID: displayID,
            ignoreRecentMove: ignoreRecentMove,
            appState: appState
        ) { section in
            await captureImages(for: section, scale: scale, appState: appState)
        }
    }

    /// The pass once its screen is known: admits it, captures each section and
    /// hands the lot to commitRecapturePass(_:admission:ignoreRecentMove:appState:).
    ///
    /// captureSection is the pass's only pixel source, which lets a test drive
    /// the admission and the commit with a scripted reader instead of a screen.
    @MainActor
    func runRecapturePass(
        capturing sectionsToCapture: [MenuBarSection.Name],
        displayID: CGDirectDisplayID,
        ignoreRecentMove: Bool,
        appState: AppState,
        captureSection: @MainActor (MenuBarSection.Name) async -> CapturePass
    ) async -> Bool {
        // Before the first await: what this pass publishes must still describe
        // the layout it started from. See publicationRejection(of:).
        let admission = CapturePublicationPolicy.admit(
            layout: appState.itemManager.layoutPublication,
            displayID: displayID
        )
        // Every section's crops, invalidations, strikes and recoveries; none of
        // it touches the cache before the commit.
        var pass = CapturePass()

        for section in sectionsToCapture {
            guard !Task.isCancelled else {
                MenuBarItemImageCache.diagLog.debug("recaptureNow: cancelled before capturing \(section.logString)")
                return false
            }

            guard !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }

            let sectionResult = await captureSection(section)

            guard !skipCaptureWhileScreenLocked("completed recapture") else { return false }

            // Discard when a move landed (or is still running) while this
            // capture was in flight: the crops were taken from a bar that
            // is not where it will settle. The cooldown test must be != true: != false
            // would discard every capture taken on a quiet bar and keep the
            // ones taken mid-move. ignoreRecentMove waives only the cooldown
            // of a move that finished before admission, never a newer one.
            // Checked here as well as in the commit so a stale pass stops
            // before it screenshots the next section.
            if let rejection = publicationRejection(
                of: admission, appState: appState, ignoreRecentMove: ignoreRecentMove
            ) {
                MenuBarItemImageCache.diagLog.debug(
                    "recaptureNow: discarding in-flight capture (\(String(describing: rejection)))"
                )
                return false
            }

            if sectionResult.captured.isEmpty {
                if section == .visible {
                    requestInventoryRefresh(reason: "visible pass captured nothing")
                }
                // Expected for off-screen sections (e.g. hidden): live refresh
                // (refreshImages) handles those items. Only a real concern for
                // the visible section, check the capture logs for details.
                MenuBarItemImageCache.diagLog.debug(
                    "captureImages: no images captured for \(section.logString) (off-screen or transient failure)"
                )
            }
            pass.absorb(sectionResult)
        }

        return commitRecapturePass(
            pass, admission: admission, ignoreRecentMove: ignoreRecentMove, appState: appState
        )
    }

    /// Publishes a finished pass, or leaves the cache exactly as it was.
    ///
    /// Synchronous on purpose. The validity check, the failure ledger, the
    /// invalidations and the images land with nothing awaited between them, so
    /// no move can start after the check and before the write. A rejected pass
    /// changes neither pixels nor bookkeeping.
    @MainActor
    func commitRecapturePass(
        _ pass: CapturePass,
        admission: CapturePublicationAdmission,
        ignoreRecentMove: Bool,
        appState: AppState
    ) -> Bool {
        guard !skipCaptureWhileScreenLocked("publishing recapture") else { return false }
        // Images, invalidations and strikes alike go stale with the layout.
        if let rejection = publicationRejection(
            of: admission, appState: appState, ignoreRecentMove: ignoreRecentMove
        ) {
            MenuBarItemImageCache.diagLog.debug(
                "recaptureNow: discarding completed capture (\(String(describing: rejection)))"
            )
            return false
        }
        // Ahead of the guard below: a pass with only strikes or recoveries to
        // report still reports them.
        commitCaptureLedger(of: pass)

        let newImages = pass.captured
        let invalidatedTags = pass.invalidatedTags
        let unconditionallyInvalidatedTags = pass.unconditionallyInvalidatedTags

        // Do NOT check Task.isCancelled here: if any captures succeeded (e.g.
        // the prewarm completed its hidden-section AX crop), we must apply them
        // even when the parent task was cancelled mid-settle (user re-clicked the
        // ThawBar before the settle delay expired). The per-section guard above
        // already prevents starting new captures when cancelled.
        // Also apply when we only have invalidations (incomplete native-hidden
        // crops) so stale priors are cleared for the app-icon fallback.
        guard !newImages.isEmpty || !invalidatedTags.isEmpty else { return false }

        // Get the set of valid item tags from all sections to clean up stale entries
        let allValidTags = Set(
            appState.itemManager.managedItems.map(\.tag)
        )

        // Plus the tags of items the section controller has assigned (their snapshots). A
        // concealed item can briefly fall out of managedItems between conceal
        // and the snapshot re-add; without this it would lose its last-good icon
        // here and show a blank Hidden slot after a visible→hidden move.
        let assignedSnapshotTags = appState.menuBarManager.sectionController.assignedSnapshotTags

        let beforeCount = capturesByTag.count
        var didChange = false
        // Pre-apply snapshot for the changeless-pass report below.
        let preApplyImages = capturesByTag

        // Drop priors that this pass proved unusable (incomplete crop /
        // off-window), but keep a settled non-blank glyph when the new
        // pass has no replacement. Clearing those priors causes "double
        // arrow" and app-icon churn on macOS 27 when Layout opens.
        // Ordinary concealment-proven tags skip the retention heuristic.
        // Governable system extras can retain the last settled visible glyph.
        var retainedPriorCount = 0
        for tag in invalidatedTags {
            if !unconditionallyInvalidatedTags.contains(tag),
               newImages[tag] == nil,
               let existing = capturesByTag[tag],
               !existing.isEffectivelyBlank,
               existing.pointSize.width >= Self.minimumTrustedGlyphWidth
            {
                retainedPriorCount += 1
                continue
            }
            // Only touch the published dictionary when the tag is actually
            // in it: removing an absent key still counts as a mutation to
            // the observation registrar, and invalidations routinely name
            // tags the cache never held.
            if capturesByTag[tag] != nil {
                removeCapture(for: tag)
                didChange = true
            }
            accessTimestamps.removeValue(forKey: tag)
        }
        if !invalidatedTags.isEmpty {
            let clearedCount = invalidatedTags.count - retainedPriorCount
            if clearedCount > 0 {
                MenuBarItemImageCache.diagLog.debug(
                    "recaptureNow: cleared \(clearedCount) prior image(s) for app-icon fallback"
                )
            }
            if retainedPriorCount > 0 {
                MenuBarItemImageCache.diagLog.debug(
                    "recaptureNow: retained \(retainedPriorCount) settled prior image(s)"
                )
            }
        }

        // Tags with recent capture failures should keep their cached images
        // even if the item temporarily left the item cache (e.g. a transient
        // menu bar item whose window briefly disappeared). This prevents
        // the ThawBar and search from showing empty icons while the item's
        // app is still running.
        let recentlyFailedTags = failedCapturesLock.withLock { Set($0.keys) }

        // Remove images for items that no longer exist in the item cache,
        // but preserve images for items that have recent capture failures
        // (they may reappear shortly with a new window ID) and for
        // section-controller-assigned items (concealed items mid-re-add).
        // Use matchesIgnoringWindowID for non-system items so disk-loaded
        // entries are not incorrectly evicted when their windowID is nil.
        //
        // Assigned back only when the filter dropped something: a
        // same-contents reassignment still invalidates every observer.
        let survivingImages = capturesByTag.filter { key, _ in
            if key.isSystemItem {
                return allValidTags.contains(key)
                    || recentlyFailedTags.contains(key)
                    || assignedSnapshotTags.contains(key)
            }
            return containsTagMatchingIgnoringWindowID(allValidTags, target: key) ||
                containsTagMatchingIgnoringWindowID(recentlyFailedTags, target: key) ||
                containsTagMatchingIgnoringWindowID(assignedSnapshotTags, target: key)
        }
        if survivingImages.count != capturesByTag.count {
            replaceCaptures(with: survivingImages)
        }

        // Additional cleanup must preserve the same transiently valid sets
        // as the filter above. Otherwise an assigned snapshot can survive
        // that filter and then be evicted immediately here while its live
        // item is between concealment and cache re-addition.
        _ = validateAndCleanupInvalidEntries(
            preserving: recentlyFailedTags.union(assignedSnapshotTags)
        )

        // Mark all newly captured images as most recently used
        for tag in newImages.keys {
            accessCounter += 1
            accessTimestamps[tag] = accessCounter
        }

        // Remove old entries whose (namespace, title, instanceIndex) matches a
        // new entry but with a different windowID. After a monitor reconnect,
        // items may get new windowIDs, causing duplicate cache entries for the
        // same logical item. Keep only the latest capture (newImages wins).
        let newKeysSet = Set(newImages.keys)
        let staleKeys = capturesByTag.keys.filter { oldKey in
            guard !oldKey.isSystemItem, !newKeysSet.contains(oldKey) else {
                return false
            }
            return containsTagMatchingIgnoringWindowID(newKeysSet, target: oldKey)
        }
        for tag in staleKeys {
            if removeCapture(for: tag) != nil {
                didChange = true
            }
            accessTimestamps.removeValue(forKey: tag)
        }

        // Record volatility before merging. This is the macOS 27 hook:
        // refreshImages (the other observation point) is unreachable on
        // 27 because the live refresh loop routes here instead. Items
        // absent from capturesByTag are a first sighting, not a change, so they
        // must not count against stability.
        //
        // Stand down entirely inside the restriction settle window: an
        // assertion rebuild shifts every item's crop, so pixel-diffing
        // across one marks unrelated items as changed on the same tick.
        // Skipping is cheap; polluted tallies are not.
        let isSettling = appState.itemManager.isWithinRestrictionReflowSettleWindow
        if !isSettling {
            for (tag, newImage) in newImages {
                guard let existing = capturesByTag[tag] else { continue }
                volatilityIndex.record(
                    tag: tag,
                    changed: !MenuBarItemGlyphCapture.isVisuallyEqual(existing, newImage),
                    width: newImage.pointSize.width
                )
            }
        }

        // Merge in the new images, preferring settled glyphs over blank
        // or much-narrower (chevron-bleed) candidates.
        //
        // The merge runs on a local copy. capturesByTag is the one
        // property every glyph consumer observes, and the live refresh
        // loop lands here at up to 30 Hz; merging into it in place would
        // invalidate the ThawBar, the search rows and the layout item
        // views on every tick, including the common one where the merge
        // kept every glyph it already had.
        var mergedImages = capturesByTag
        mergedImages.merge(newImages) { existing, new in
            Self.preferredCachedImage(existing: existing, candidate: new)
        }

        // A pass that only re-proved what the cache already holds is
        // changeless: the merge preferred the existing glyphs, and every
        // genuine replacement is visually different from the snapshot
        // above. Feeds the live refresh loop's back-off ladder.
        for tag in newImages.keys {
            guard let merged = mergedImages[tag] else { continue }
            if !MenuBarItemGlyphCapture.isVisuallyEqual(preApplyImages[tag], merged) {
                didChange = true
                break
            }
        }

        // Publish only when this pass changed something. A newly seen
        // tag always does (its snapshot entry is nil), and a tag the
        // invalidation loop dropped and the merge put back was already
        // counted there. The count check covers the one gap: a tag the
        // validity filter above evicted and this pass recaptured with
        // the same pixels, which must still be put back.
        if didChange || mergedImages.count != capturesByTag.count {
            replaceCaptures(with: mergedImages)
        }

        // Prune against the item cache (every managed item, hidden ones
        // included), NOT capturesByTag.keys: at cold start the image cache is
        // near-empty (30 s disk TTL), and pruning on it destroyed most
        // freshly-loaded persisted records.
        volatilityIndex.prune(keeping: Set(appState.itemManager.managedItems.map(\.tag)))
        volatilityIndex.logDistributionIfChanged()

        // Enforce cache size limit using LRU eviction, but never evict
        // items that still exist in the menu bar (valid item tags).
        // This prevents thrashing the cache for visible items when
        // many transient items come and go (e.g. monitor hotplug).
        if capturesByTag.count > Self.maxCacheSize {
            let protectedTags = allValidTags
            let excessCount = capturesByTag.count - Self.maxCacheSize
            let tagsToRemove = leastRecentlyUsedTags(
                count: excessCount,
                excluding: protectedTags
            )

            for tag in tagsToRemove {
                removeCapture(for: tag)
                accessTimestamps.removeValue(forKey: tag)
            }

            if !tagsToRemove.isEmpty {
                MenuBarItemImageCache.diagLog.info(
                    "LRU cache eviction: removed \(tagsToRemove.count) least recently used images (\(protectedTags.count) protected)"
                )
            }
        }

        // Remove stale timestamps for images that no longer exist
        accessTimestamps = accessTimestamps.filter { capturesByTag.keys.contains($0.key) }

        let afterCount = capturesByTag.count
        let finalAccessOrderCount = accessTimestamps.count
        let totalRemoved = beforeCount - afterCount

        // Log cache status for monitoring (verbose only when needed)
        if afterCount > 30 || totalRemoved > 0 {
            MenuBarItemImageCache.diagLog.info(
                "Image cache: \(afterCount) images, LRU order: \(finalAccessOrderCount) entries (removed \(totalRemoved) stale+invalid images)"
            )
        }

        // Warning if cache and access order are out of sync
        if afterCount != finalAccessOrderCount {
            MenuBarItemImageCache.diagLog.warning(
                "Cache inconsistency: \(afterCount) cached images vs \(finalAccessOrderCount) LRU entries"
            )
        }

        return didChange
    }

    /// Restoration action after temporarily revealing a section for prewarm capture.
    nonisolated enum PrewarmRevealRestorationAction: Equatable {
        case hide
        case noOp
        case show(MenuBarSection.Name)

        /// Whether the cleanup may hide the section this prewarm revealed:
        /// only if the user revealed nothing since the capture path's last hide.
        static func cleanupMayHide(
            userRevealDate: Date?,
            lastCaptureHideDate: Date?
        ) -> Bool {
            guard let userRevealDate else { return true }
            guard let lastCaptureHideDate else { return false }
            return userRevealDate < lastCaptureHideDate
        }

        static func resolve(
            previous: MenuBarSection.Name?,
            currentAfterShow: MenuBarSection.Name?
        ) -> PrewarmRevealRestorationAction {
            if previous == nil {
                return .hide
            }
            if previous == currentAfterShow {
                return .noOp
            }
            if let previous {
                return .show(previous)
            }
            return .noOp
        }
    }

    /// Whether prewarm should recapture an item given its cached image state.
    ///
    /// A glyph loaded from disk counts as present. Each saved entry already
    /// expires by its volatility class on load, and recapturing every saved
    /// glyph meant that one missing item made the Thaw Bar reveal and capture
    /// the whole section, one batch after another.
    static nonisolated func prewarmNeedsCapture(
        cachedImage: MenuBarItemGlyphCapture?,
        wouldAttemptCapture: Bool
    ) -> Bool {
        guard wouldAttemptCapture else { return false }
        guard let cachedImage, !cachedImage.isEffectivelyBlank else { return true }
        // Recover from a native overflow chevron («») stored as a successful crop.
        if cachedImage.pointSize.width < Self.minimumTrustedGlyphWidth {
            return true
        }
        return false
    }

    /// Minimum point width for a crop that is trusted as a real status-item glyph.
    /// Narrower crops usually come from native overflow chevron bleed on macOS 27.
    static nonisolated let minimumTrustedGlyphWidth: CGFloat = 15

    /// Asks for a fresh inventory walk, at most every 2 s.
    ///
    /// The capture display and item frames come from the last walk. With several displays
    /// macOS moves or hides the active bar as focus changes, so until the next scheduled walk
    /// every pass reads a bar the items have left and the panes keep their app icons.
    @MainActor
    func requestInventoryRefresh(reason: String) {
        let now = ContinuousClock.now
        if let last = lastInventoryRefreshRequest, now - last < .seconds(2) {
            return
        }
        lastInventoryRefreshRequest = now
        MenuBarItemImageCache.diagLog.debug("recaptureNow: \(reason); refreshing the item inventory")
        Task { @MainActor [weak self] in
            await self?.appState?.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    /// Whether the menu bar host's bar window over display is on screen.
    ///
    /// macOS can slide a display's bar above its top edge while focus is on another display.
    /// Capturing that display then reads blank pixels, and every glyph would fall back to its
    /// app icon until the bar returns. Unknown geometry counts as on screen.
    static func isMenuBarOnScreen(displayID: CGDirectDisplayID) -> Bool {
        guard let host = NSRunningApplication.runningApplications(
            withBundleIdentifier: SharedConstants.menuBarHostingBundleID
        ).first else { return true }
        let barFrames = Bridging.getMenuBarWindowIDs(forProcess: host.processIdentifier, skipWidthFilter: true)
            .compactMap { Bridging.getWindowBounds(for: $0) }
        return isBarOnScreen(barFrames: barFrames, display: CGDisplayBounds(displayID))
    }

    /// isMenuBarOnScreen(displayID:) over known frames: the bar windows spanning display's width.
    static nonisolated func isBarOnScreen(barFrames: [CGRect], display: CGRect) -> Bool {
        let bars = barFrames.filter { abs($0.minX - display.minX) < 1 && abs($0.width - display.width) < 1 }
        guard !bars.isEmpty else { return true }
        return bars.contains { $0.minY >= display.minY - 1 }
    }

    /// Whether capture is a settled glyph worth keeping over a miss: not
    /// blank, and wide enough not to be native overflow chevron bleed.
    static nonisolated func isTrustedGlyph(_ capture: MenuBarItemGlyphCapture) -> Bool {
        !capture.isEffectivelyBlank && capture.pointSize.width >= minimumTrustedGlyphWidth
    }

    /// Chooses between an existing cache entry and a newly captured candidate.
    ///
    /// Prefers keeping a settled non-blank glyph over blank or much-narrower
    /// replacements (chevron bleed), while still allowing legitimate updates
    /// when the candidate is at least as wide.
    static nonisolated func preferredCachedImage(
        existing: MenuBarItemGlyphCapture,
        candidate: MenuBarItemGlyphCapture
    ) -> MenuBarItemGlyphCapture {
        if existing.isEffectivelyBlank {
            return candidate
        }
        if candidate.isEffectivelyBlank {
            return existing
        }
        if candidate.pointSize.width < existing.pointSize.width * 0.75 {
            return existing
        }
        return candidate
    }

    /// How many concealed items are revealed together on a display without a
    /// notch. See revealBatchSize(hasNotch:).
    ///
    /// Revealing one item at a time shows as icons blinking in and out one by
    /// one, and each item pays its own poll loop (an AX enumeration per
    /// attempt) and screenshot pair. A group shares one reveal, one poll loop
    /// and one screenshot pair. Not the whole section, because every revealed
    /// item takes real width: enough of them overflow the bar, pushing items
    /// off screen or into the native chevron, where refreshOverlayItemGlyphs
    /// refuses to capture. Six fits inside the space a concealed section
    /// vacated on any realistic bar.
    private static nonisolated let revealCaptureBatchSize = 6

    /// How many concealed items one reveal may put on the live bar at once.
    ///
    /// What draws the native chevron is width, not concealment. The notch's
    /// lane is small, so revealing six items at once overflows it on a notched
    /// Mac; MenuBarAgent then draws the chevron for exactly the instants the
    /// screenshot pair is taken, and the crops land on arrows. A single
    /// revealed item restores one item's width and always fits. A notchless
    /// lane is wide, so grouping stays there to avoid the reveal parade.
    static nonisolated func revealBatchSize(hasNotch: Bool) -> Int {
        hasNotch ? 1 : revealCaptureBatchSize
    }

    /// Pairs each requested reveal with the live item that answers it, in
    /// request order, resolving a whole batch against one enumeration so two
    /// requests can never claim the same live item.
    ///
    /// Strict identity first, then an owner-scoped fallback for the one shape
    /// strict identity cannot survive. macOS 27 names untitled status items
    /// positionally: the AX walk's per-app fallback counter advances only for
    /// the children it actually enumerates, so a sibling that stays concealed
    /// does not hold its slot. Reveal one of an app's two untitled items and it
    /// comes back as Item-0 when it was minted as Item-1, nothing matches,
    /// the batch resolves empty, no glyph is cached, and the prewarm gate asks
    /// for the same reveal again on every Thaw Bar open.
    ///
    /// The fallback fires only where it cannot mis-pair: both titles carry the
    /// positional Item-N shape (a real title is never renumbered, so a
    /// mismatch there is a different item, not a renamed one), exactly one
    /// request for that app is unmatched, and exactly one of its live items is
    /// unclaimed. Two same-app items revealed together still match strictly,
    /// because revealing both restores the numbering their tags were minted
    /// under. Anything ambiguous stays unresolved rather than guessing, which
    /// costs a reveal and never caches a neighbour's glyph.
    static nonisolated func revealMatches(
        requests: [MenuBarItem],
        live: [MenuBarItem]
    ) -> [MenuBarItem?] {
        var claimed = Set<Int>()
        var matches = [MenuBarItem?](repeating: nil, count: requests.count)

        for (index, request) in requests.enumerated() {
            guard let liveIndex = live.indices.first(where: { candidate in
                !claimed.contains(candidate) && (
                    live[candidate].hasSameIdentity(as: request) ||
                        live[candidate].uniqueIdentifier == request.uniqueIdentifier
                )
            }) else {
                continue
            }
            claimed.insert(liveIndex)
            matches[index] = live[liveIndex]
        }

        let unmatched = requests.indices.filter {
            matches[$0] == nil &&
                MenuBarItemTag.isGenericItemTitle(requests[$0].tag.title)
        }
        for (_, group) in Dictionary(grouping: unmatched, by: { requests[$0].tag.namespace })
            where group.count == 1
        {
            let index = group[0]
            let candidates = live.indices.filter { candidate in
                !claimed.contains(candidate) &&
                    live[candidate].hasSameOwner(as: requests[index]) &&
                    MenuBarItemTag.isGenericItemTitle(live[candidate].tag.title)
            }
            guard candidates.count == 1 else { continue }
            claimed.insert(candidates[0])
            matches[index] = live[candidates[0]]
        }

        return matches
    }

    /// One poll step of waitForRevealedItems: advances the settle state
    /// given the prior settled and previous (last-sighting) maps and the
    /// current current (identifier → live item) matched in this poll.
    ///
    /// An identifier becomes settled when it already has a previous
    /// sighting and its bounds are stable against the current sighting; once
    /// settled it keeps its claim and is not re-measured. An identifier that is
    /// present this poll but not yet settled (or was settled earlier but is
    /// missing this poll) records the current sighting as its new previous,
    /// except a settled identifier that goes missing, which keeps its settled
    /// entry rather than being un-settled by a transient AX drop. An
    /// identifier absent from current and absent from settled clears its
    /// previous entry so a later, differently-positioned sighting is not
    /// measured against a stale one.
    ///
    /// Pure so the settle decision can be tested without a live AX
    /// enumeration. Polling for stable bounds matters because a fixed delay
    /// after a reveal can land while a large section is still recompositing,
    /// when every item's live bounds fail the status-item band check.
    static nonisolated func advanceRevealSettle(
        settled: [String: MenuBarItem],
        previous: [String: MenuBarItem],
        current: [String: MenuBarItem],
        hasStable: (CGRect, CGRect) -> Bool
    ) -> (settled: [String: MenuBarItem], previous: [String: MenuBarItem]) {
        var nextSettled = settled
        var nextPrevious = previous

        for (identifier, liveItem) in current {
            // A settled member keeps its claim; it is not re-measured against
            // a later sighting even if that sighting moved.
            if nextSettled[identifier] != nil {
                continue
            }
            if let prior = nextPrevious[identifier],
               hasStable(prior.bounds, liveItem.bounds)
            {
                nextSettled[identifier] = liveItem
            } else {
                nextPrevious[identifier] = liveItem
            }
        }

        // A non-settled identifier that did not appear in this poll has
        // nothing to measure stability against; drop its prior sighting so a
        // later sighting at a different position is not mis-matched against it.
        // Settled identifiers are left intact: a transient AX drop must not
        // un-settle a member that already proved stable.
        for identifier in previous.keys {
            if current[identifier] == nil, nextSettled[identifier] == nil {
                nextPrevious[identifier] = nil
            }
        }

        return (nextSettled, nextPrevious)
    }

    /// Waits only as long as MenuBarAgent needs to publish precise AX reveal
    /// bounds for a whole revealed group, resolving every member from the same
    /// enumeration.
    ///
    /// A fixed sleep would make an N-item reveal N × settle long even when the
    /// live AX items are available almost immediately. Waiting per item would
    /// cost one AX enumeration per poll attempt per item, and each enumeration
    /// walks every running app; this pays one poll loop per group. AX can
    /// publish an item before MenuBarAgent has finished recompositing its
    /// glyph, so one stable poll interval is required per member before it is
    /// trusted, and members settle at different times.
    ///
    /// Bounds stability does not imply the glyph is rendered, see the
    /// Constants.MenuBarTuning/layoutPrewarmRenderSettle delay the caller
    /// inserts before the SCK screenshot.
    ///
    /// Returns the members that reached stable bounds, paired with the request
    /// they answer, in request order. Members that never settled are absent
    /// rather than reported with untrustworthy bounds; the caller treats a
    /// missing member the same way it treats a missed reveal.
    private func waitForRevealedItems(
        matching items: [MenuBarItem],
        displayID: CGDirectDisplayID
    ) async -> [(requested: MenuBarItem, live: MenuBarItem)] {
        guard !items.isEmpty else { return [] }

        // MenuBarAgent can take over a second to publish a revealed item.
        // The loop leaves as soon as every member settles.
        let maxAttempts = 20
        var previousByIdentifier = [String: MenuBarItem]()
        var settledByIdentifier = [String: MenuBarItem]()

        for attempt in 0 ..< maxAttempts {
            guard !Task.isCancelled else { return [] }

            let liveItems = await MenuBarItem.getMenuBarItems(
                on: displayID,
                option: [.onScreen, .activeSpace]
            )

            // Every member is offered to the match, settled ones included, so a
            // member that settled on an earlier poll keeps its claim and cannot
            // be paired with a second request.
            let matches = Self.revealMatches(requests: items, live: liveItems)
            let currentByIdentifier = Dictionary(
                matches.enumerated().compactMap { index, liveItem in
                    liveItem.map { (items[index].uniqueIdentifier, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )

            let advanced = Self.advanceRevealSettle(
                settled: settledByIdentifier,
                previous: previousByIdentifier,
                current: currentByIdentifier,
                hasStable: { Self.hasStableCaptureBounds(before: $0, after: $1) }
            )
            settledByIdentifier = advanced.settled
            previousByIdentifier = advanced.previous

            if settledByIdentifier.count == items.count {
                break
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        if settledByIdentifier.count < items.count {
            let missing = items
                .filter { settledByIdentifier[$0.uniqueIdentifier] == nil }
                .map(\.logString)
            MenuBarItemImageCache.diagLog.debug(
                "waitForRevealedItems: \(missing.count) of \(items.count) revealed item(s) never settled " +
                    "after \(maxAttempts) polls; no capture for \(missing)"
            )
        }
        return items.compactMap { item in
            settledByIdentifier[item.uniqueIdentifier].map { (requested: item, live: $0) }
        }
    }

    /// What a grouped reveal does with a cache entry it could not refresh.
    ///
    /// The layout prewarm wants a blank or chevron-width entry gone once the
    /// reveal proves nothing better is available, so the thumbnail falls back
    /// to the app icon instead of a stale crop. The overlay keeps whatever it
    /// holds: its strip is on screen, and swapping a glyph for a fallback icon
    /// mid-pass is a visible regression.
    enum RevealMissPolicy {
        case keepExisting
        case dropUntrustedEntries
    }

    /// The live bar as a grouped reveal reads it, so a test can script the
    /// reveal's settle and its screenshot without a screen.
    struct RevealCaptureSources {
        /// The revealed members that reached stable bounds, paired with the
        /// request they answer. See waitForRevealedItems(matching:displayID:).
        let settledItems: @MainActor ([MenuBarItem]) async -> [(requested: MenuBarItem, live: MenuBarItem)]
        /// The pause between stable AX bounds and a fully rendered glyph.
        let renderSettle: @MainActor () async -> Void
        let reader: any MenuBarCaptureReading
    }

    /// Reveals concealed items a few at a time and captures each group from
    /// one screenshot pair.
    ///
    /// Shared by the Thaw Bar / layout-pane prewarm and the overlay refresh so
    /// both pay the grouped cost: one reveal, one poll loop resolving every
    /// member from the same AX enumeration, one render settle and one
    /// screenshot pair per group of the display's batch size. Revealing one
    /// item at a time would keep a dynamic-title neighbour from flickering,
    /// but makes an N-item prewarm N reveals long. Notched displays are the
    /// exception (see revealBatchSize(hasNotch:)).
    ///
    /// Callers filter items first (missing-only, blacklist, native overflow)
    /// and check for cancellation before the first reveal. Merge semantics: a
    /// fresh crop replaces the entry unless
    /// preferredCachedImage(existing:candidate:) keeps the old one, an
    /// unchanged crop is not republished, and a miss follows missPolicy.
    private func captureConcealedItemsByGroupedReveal(
        _ items: [MenuBarItem],
        controller: any MenuBarSectionControlling,
        displayID: CGDirectDisplayID,
        scale: CGFloat,
        missPolicy: RevealMissPolicy
    ) async {
        guard !items.isEmpty, !Task.isCancelled,
              !skipCaptureWhileScreenLocked("grouped reveal capture"),
              let appState else { return }

        // Before the first await: the display the caller resolved these items
        // and displayID against. Every batch answers to this one.
        let admittedDisplayID = appState.itemManager.itemDisplayID

        // Hold the capture service open across every batch, the way the live
        // refresh loop holds it across every tick. Each batch takes a hosting
        // and a strip screenshot, and with no other consumer registered the
        // helper watches its last session close between them and schedules its
        // exit, so a nine-item prewarm can pay several process launches for
        // one logical operation. The hold is scoped to this call rather than
        // left open: a prewarm that finished should let the helper go.
        let holdsCaptureService = ScreenCapture.routesThroughCaptureService
        if holdsCaptureService {
            await MenuBarCaptureServiceClient.shared.beginLiveConsumer()
        }
        defer {
            if holdsCaptureService {
                await MenuBarCaptureServiceClient.shared.endLiveConsumer()
            }
        }

        let batchSize = Self.revealBatchSize(
            hasNotch: NSScreen.screen(for: displayID)?.hasNotch ?? false
        )
        await captureRevealBatches(
            stride(from: 0, to: items.count, by: batchSize)
                .map { Array(items[$0 ..< min($0 + batchSize, items.count)]) },
            controller: controller,
            displayID: displayID,
            admittedDisplayID: admittedDisplayID,
            scale: scale,
            missPolicy: missPolicy,
            appState: appState,
            sources: RevealCaptureSources(
                settledItems: { await self.waitForRevealedItems(matching: $0, displayID: displayID) },
                renderSettle: { try? await Task.sleep(for: Constants.MenuBarTuning.layoutPrewarmRenderSettle) },
                reader: LiveMenuBarCaptureReader()
            )
        )
    }

    /// The reveal loop of captureConcealedItemsByGroupedReveal(_:controller:displayID:scale:missPolicy:),
    /// one batch after another, stopping at the first batch that may not publish.
    ///
    /// admittedDisplayID is the item cache's display when the caller chose
    /// displayID. It is not re-read per batch: pixels are taken from
    /// displayID whatever happens, so a display switch while a reveal settles
    /// must reject the batch rather than become its new baseline.
    func captureRevealBatches(
        _ batches: [[MenuBarItem]],
        controller: any MenuBarSectionControlling,
        displayID: CGDirectDisplayID,
        admittedDisplayID: CGDirectDisplayID?,
        scale: CGFloat,
        missPolicy: RevealMissPolicy,
        appState: AppState,
        sources: RevealCaptureSources
    ) async {
        for batch in batches {
            guard !Task.isCancelled, !skipCaptureWhileScreenLocked("revealing capture batch") else { return }

            for item in batch {
                controller.revealItemTemporarily(item.uniqueIdentifier)
            }
            defer {
                for item in batch {
                    controller.concealTemporarilyRevealedItem(item.uniqueIdentifier)
                }
            }

            let revealed = await sources.settledItems(batch)
            guard !skipCaptureWhileScreenLocked("capture reveal completed") else { return }
            guard !revealed.isEmpty else { continue }

            // AX bounds stabilize before MenuBarAgent finishes recompositing
            // the revealed glyphs; wait one render settle so the screenshot
            // captures fully-rendered icons. One settle for the group, since
            // they were revealed together.
            await sources.renderSettle()
            guard !Task.isCancelled, !skipCaptureWhileScreenLocked("settled capture batch") else { return }

            // Admitted here, after the reveal and its settle, with nothing
            // awaited before the screenshot. Rebuilding the restriction for the
            // reveal (and for the previous batch's conceal) moves the layout
            // generation by itself, so an admission taken any earlier would
            // reject every batch. From here on a change is a real move.
            let admission = CapturePublicationPolicy.admit(
                layout: appState.itemManager.layoutPublication,
                displayID: admittedDisplayID
            )
            // A move already running, or a display that switched while the
            // reveal settled: do not screenshot a bar this batch cannot publish.
            if let rejection = publicationRejection(
                of: admission, appState: appState, ignoreRecentMove: true, isRecapturePass: false
            ) {
                MenuBarItemImageCache.diagLog.debug(
                    "grouped reveal capture: not capturing batch, stopping (\(String(describing: rejection)))"
                )
                return
            }

            // One hosting screenshot and one strip screenshot for the whole
            // group: axBoundsCapture already crops each item out of the same
            // pair of frames, so every crop comes from one instant of the bar
            // rather than from N frames taken while it reflowed between them.
            // Capture against the resolved displayID directly rather than
            // captureImages(appState:), which re-resolves the "active" display
            // and can crop one display's bounds against another's screenshot.
            let captureResult = await axBoundsCapture(
                revealed.map { (item: $0.live, bounds: $0.live.bounds) },
                scale: scale,
                displayID: displayID,
                validateFreshBounds: true,
                // This path just revealed the items itself and waited for
                // their live AX elements, so none of them is concealed here.
                concealedIdentifiers: [],
                using: sources.reader
            )

            guard commitRevealedBatch(
                captureResult,
                revealed: revealed,
                admission: admission,
                missPolicy: missPolicy,
                appState: appState
            ) else { return }
        }
    }

    /// Publishes one revealed batch, or leaves the cache exactly as it was.
    /// False when the batch was rejected.
    ///
    /// Synchronous for the reason commitRecapturePass(_:admission:ignoreRecentMove:appState:)
    /// is: nothing is awaited between the validity check and the ledger, the
    /// dropped misses and the images.
    func commitRevealedBatch(
        _ captureResult: CapturePass,
        revealed: [(requested: MenuBarItem, live: MenuBarItem)],
        admission: CapturePublicationAdmission,
        missPolicy: RevealMissPolicy,
        appState: AppState
    ) -> Bool {
        guard !skipCaptureWhileScreenLocked("publishing capture batch") else { return false }
        if let rejection = publicationRejection(
            of: admission, appState: appState, ignoreRecentMove: true, isRecapturePass: false
        ) {
            MenuBarItemImageCache.diagLog.debug(
                "grouped reveal capture: discarding batch and stopping (\(String(describing: rejection)))"
            )
            return false
        }
        commitCaptureLedger(of: captureResult)

        // A cancel, usually the Thaw Bar closing, also drops the strip's capture
        // ticket, so the misses after it say nothing about the items.
        let stoppedEarly = Task.isCancelled
        if missPolicy == .dropUntrustedEntries, !stoppedEarly {
            for tag in captureResult.invalidatedTags {
                if !captureResult.unconditionallyInvalidatedTags.contains(tag),
                   let existing = capturesByTag[tag],
                   Self.isTrustedGlyph(existing)
                {
                    continue
                }
                removeCapture(for: tag)
                accessTimestamps.removeValue(forKey: tag)
            }
        }

        for pair in revealed {
            // The capture result is keyed by the fresh AX item, while the
            // cache is keyed by the concealed snapshot the caller holds.
            let tag = pair.requested.tag
            guard let image = captureResult.captured[pair.live.tag] else {
                // A miss never wipes a settled glyph. Under the dropping
                // policy a blank or chevron-width entry goes, so a failed
                // reveal cannot leave a stale thumbnail behind.
                if missPolicy == .dropUntrustedEntries, !stoppedEarly,
                   let existing = capturesByTag[tag],
                   !Self.isTrustedGlyph(existing)
                {
                    removeCapture(for: tag)
                    accessTimestamps.removeValue(forKey: tag)
                }
                continue
            }
            if let cachedImage = capturesByTag[tag] {
                let preferred = Self.preferredCachedImage(existing: cachedImage, candidate: image)
                if MenuBarItemGlyphCapture.isVisuallyEqual(preferred, cachedImage) {
                    continue
                }
                setCapture(preferred, for: tag)
            } else {
                setCapture(image, for: tag)
            }
            accessCounter += 1
            accessTimestamps[tag] = accessCounter
        }
        return true
    }

    /// Briefly reveals concealed macOS 27 sections so their live glyphs can be
    /// captured before the assertion hides them again.
    @MainActor
    func prewarmConcealedImages(
        sections requestedSections: [MenuBarSection.Name],
        onlyMissingImages: Bool = true
    ) async {
        // Before the failure reset and the reveal: a locked pass must not toggle
        // the lock screen's bar or clear strikes it did not earn back.
        guard !skipCaptureWhileScreenLocked("prewarmConcealedImages"),
              appState?.menuBarManager.sectionController != nil
        else {
            return
        }

        // One pass at a time: overlapping passes land one's conceal inside the
        // other's screenshot. A queued pass whose bar closed stops here.
        await beginConcealedPrewarm()
        defer { endConcealedPrewarm() }
        guard !Task.isCancelled, !skipCaptureWhileScreenLocked("queued prewarm") else { return }

        let sections = requestedSections.reduce(into: [MenuBarSection.Name]()) { result, section in
            guard section != .visible, !result.contains(section) else { return }
            result.append(section)
        }

        // A visible consumer is asking: the Thaw bar or the layout pane is open
        // and these rows have no image to draw. The failure ledger exists to
        // stop background passes hammering an item that keeps failing; left in
        // force here it would keep a blacklisted item out of this reveal, so it
        // could only ever be captured by the user clicking it.
        if let itemManager = appState?.itemManager {
            let tags = sections.reduce(into: Set<MenuBarItemTag>()) { result, section in
                result.formUnion(itemManager.itemCache[section].map(\.tag))
            }
            if !tags.isEmpty {
                clearCaptureFailures(tags: tags)
                MenuBarItemImageCache.diagLog.debug(
                    "prewarmConcealedImages: forgot recorded failures for \(tags.count) item(s) in " +
                        "\(sections.map(\.rawValue))"
                )
            }
        }

        // Always-hidden items go through the same grouped reveal as hidden
        // ones. Revealing the whole section does not work: closing the Thaw
        // Bar conceals it again, and even revealed the items still report
        // their parked frames.
        //
        // Inline in the caller's task, not an unstructured Task, so closing the
        // Thaw Bar (which cancels cacheTask) stops the reveal loop.
        for section in sections {
            guard let appState else { break }
            let controller = appState.menuBarManager.sectionController

            let sectionItems = appState.itemManager.itemCache[section]
            guard !sectionItems.isEmpty else { continue }

            let displayID = appState.itemManager.itemDisplayID
                ?? windowServer.activeMenuBarDisplayID()
                ?? CGMainDisplayID()
            let isNativeOverflowActive = controller.isNativeOverflowActive(on: displayID)
            let itemsToCapture = sectionItems.filter { item in
                // Thaw Bar Only items draw their app icon; revealing them
                // to capture would flash them on the bar.
                guard !appState.itemManager.isThawBarOnly(item) else {
                    return false
                }
                // Native notch overflow remains in force when Thaw removes
                // an item from its own concealment assertion. A prewarm in
                // that state can only capture the system overflow chevron,
                // never the item's real glyph.
                guard !isNativeOverflowActive else {
                    return false
                }
                return !onlyMissingImages || Self.prewarmNeedsCapture(
                    cachedImage: image(for: item.tag),
                    wouldAttemptCapture: wouldAttemptCapture(of: item)
                )
            }
            guard !itemsToCapture.isEmpty else { continue }

            guard !Task.isCancelled else {
                MenuBarItemImageCache.diagLog.debug(
                    "prewarmConcealedImages: capture cancelled before start for \(section.logString)"
                )
                break
            }

            let scale = NSScreen.screen(for: displayID)?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2

            // Grouped precise reveal, shared with the overlay refresh:
            // batches of a few items, one settle and one screenshot pair
            // per batch, instead of one reveal per item. A blank or
            // chevron-width entry that the reveal cannot better is dropped
            // so the Layout thumbnail falls back to the app icon.
            await captureConcealedItemsByGroupedReveal(
                itemsToCapture,
                controller: controller,
                displayID: displayID,
                scale: scale,
                missPolicy: .dropUntrustedEntries
            )
        }

        // One save after the whole pass rather than one per section: every
        // save PNG-encodes and rewrites the entire cache, so a full prewarm
        // would otherwise pay that cost once per section back-to-back for the
        // same end state.
        saveToDisk()
    }

    /// Waits until no other concealed-section prewarm is running, then marks
    /// this one as running. Waiters are resumed in arrival order.
    @MainActor
    private func beginConcealedPrewarm() async {
        guard isConcealedPrewarmRunning else {
            isConcealedPrewarmRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            concealedPrewarmWaiters.append(continuation)
        }
    }

    /// Hands the running slot straight to the next queued prewarm, so no new
    /// caller can slip in between, or frees it.
    @MainActor
    private func endConcealedPrewarm() {
        if concealedPrewarmWaiters.isEmpty {
            isConcealedPrewarmRunning = false
        } else {
            concealedPrewarmWaiters.removeFirst().resume()
        }
    }

    /// Whether the screen is locked, in which case pass skips its capture.
    ///
    /// Skipping before any item is attempted keeps the lock screen's bad crops
    /// out of recordCaptureFailure(for:), so a lock never blacklists items.
    /// Only transitions are logged, since the live loop calls this every tick.
    func skipCaptureWhileScreenLocked(_ pass: String) -> Bool {
        let locked = screenIsLocked()
        if screenLockTransitions.update(locked) {
            if locked {
                MenuBarItemImageCache.diagLog.info(
                    "\(pass): screen is locked; skipping item captures until it unlocks"
                )
            } else {
                MenuBarItemImageCache.diagLog.info("\(pass): screen unlocked; item captures resume")
            }
        }
        return locked
    }

    func containsTagMatchingIgnoringWindowID(
        _ tags: Set<MenuBarItemTag>,
        target: MenuBarItemTag
    ) -> Bool {
        for tag in tags where tag.matchesIgnoringWindowID(target) {
            return true
        }
        return false
    }

    /// The guarded door into a capture: runs one only when something on screen
    /// would use the result and the bar is quiet enough to trust.
    ///
    /// Two things disqualify a capture. Nothing visible consumes item images,
    /// in which case the screenshot cost buys nothing (waived by
    /// allowBackgroundCapture, used to keep a warm snapshot ready for the
    /// layout pane). Or the bar was just rearranged, in which case the pixels
    /// are mid-slide (waived by skipRecentMoveCheck, and only by callers that
    /// caused the move and waited for it).
    ///
    /// Pass nav when the caller already read navigation state, to avoid a
    /// redundant hop to the main actor.
    func recaptureIfWarranted(
        sections: [MenuBarSection.Name],
        skipRecentMoveCheck: Bool = false,
        allowBackgroundCapture: Bool = false,
        nav: NavigationStateSnapshot? = nil
    ) async {
        guard let appState else {
            MenuBarItemImageCache.diagLog.debug("recaptureIfWarranted: appState is nil, skipping")
            return
        }

        // Use provided snapshot or construct one in a single MainActor hop
        let navSnapshot: NavigationStateSnapshot = if let nav {
            nav
        } else {
            await MainActor.run {
                makeNavigationStateSnapshot()
            }
        }

        if !allowBackgroundCapture {
            let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: navSnapshot)

            guard hasVisibleConsumer else {
                // This is the normal path when ThawBar/search/settings are not visible, not an error
                return
            }
        }

        // A capture is actually about to happen, so this is a real consumer
        // (visible now, or the settings pane prewarming after first open).
        // Make sure the deferred disk load has run before merging fresh
        // captures on top of it.
        await MainActor.run {
            loadFromDiskIfNeeded()
        }

        if !skipRecentMoveCheck {
            guard moveActivity?.occurred(within: .seconds(1)) != true else {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache due to recent item movement"
                )
                return
            }

            // Skip updates during layout reset to prevent stale cache between passes
            if appState.itemManager.isResettingLayout {
                MenuBarItemImageCache.diagLog.debug(
                    "Skipping item image cache because layout reset is in progress"
                )
                return
            }
        }

        MenuBarItemImageCache.diagLog.debug("recaptureIfWarranted: proceeding with cache update for \(sections.count) sections (thawBar=\(navSnapshot.isThawBarPresented), search=\(navSnapshot.isSearchPresented), background=\(allowBackgroundCapture))")
        await recaptureNow(sections: sections, ignoreRecentMove: skipRecentMoveCheck)
    }

    /// Reads what is on screen and recaptures whatever it needs.
    ///
    /// The zero-argument form the observers and the setup path use: it works
    /// out the sections itself instead of being told. ThawBar gets the
    /// recent-move check waived because the panel is opened by the user, not by
    /// a reorder, so its content should appear immediately.
    @MainActor
    func recaptureIfWarranted(nav: NavigationStateSnapshot? = nil) async {
        guard let appState else {
            return
        }

        // Use provided snapshot or construct one in a single MainActor hop
        let navSnapshot: NavigationStateSnapshot = if let nav {
            nav
        } else {
            await MainActor.run {
                makeNavigationStateSnapshot()
            }
        }

        let thawBarSection: MenuBarSection.Name? = navSnapshot.isThawBarPresented
            ? appState.menuBarManager.thawBarPanel.currentSection
            : nil

        await recaptureIfWarranted(
            sections: navSnapshot.liveCaptureScope.sections(thawBarSection: thawBarSection),
            skipRecentMoveCheck: navSnapshot.isThawBarPresented,
            nav: navSnapshot
        )
    }

    /// Forces an immediate capture for the visible layout/search/ThawBar consumer
    /// after a deliberate reorder has settled.
    ///
    /// The periodic live-refresh loop honors a recent-move guard (it skips ticks
    /// within ~2 s of a move) and the capture-invalidation key ignores position,
    /// so a pure reorder leaves the layout UI showing the pre-reorder screenshot
    /// until the next nav change. The reorder caller invokes this once the bar
    /// has re-sorted, so skipRecentMoveCheck is safe here. The visible-consumer
    /// guard inside recaptureIfWarranted(sections:skipRecentMoveCheck:allowBackgroundCapture:nav:)
    /// keeps this free when no capture consumer is on screen.
    @MainActor
    func refreshAfterReorder() async {
        guard let appState else {
            return
        }
        let navSnapshot = makeNavigationStateSnapshot()

        let thawBarSection: MenuBarSection.Name? = navSnapshot.isThawBarPresented
            ? appState.menuBarManager.thawBarPanel.currentSection
            : nil
        let sectionsNeedingDisplay = navSnapshot.liveCaptureScope.sections(thawBarSection: thawBarSection)

        guard !sectionsNeedingDisplay.isEmpty else {
            return
        }

        // AX order verifies before MenuBarAgent finishes compositing the moved
        // glyphs; capturing immediately would store a mid-slide frame. One
        // short render settle mirrors the prewarm paths.
        try? await Task.sleep(for: Constants.MenuBarTuning.layoutPrewarmRenderSettle)

        await recaptureIfWarranted(
            sections: sectionsNeedingDisplay,
            skipRecentMoveCheck: true,
            nav: navSnapshot
        )
    }

    /// Clears all cached images and failure tracking.
    @MainActor
    func clearAll() {
        removeAllCaptures()
        accessTimestamps.removeAll()
        accessCounter = 0
        failedCapturesLock.withLock { $0.removeAll() }
        volatilityIndex.removeAll()
        // Allow the deferred disk load to run again on the next consumer
        // open. Harmless when the caller also deleted the disk files
        // (layout reset), the reload finds nothing and returns.
        hasLoadedFromDisk = false
        // A load already decoding was started for the cache that just went
        // away, so its images are no longer wanted.
        invalidateDiskLoad()
    }

    /// Rebuilds the cache after "Use app icons instead of live previews"
    /// turns off.
    ///
    /// Clearing is unconditional so no entry that rotted while the preference
    /// was on can be shown again. Eager recapture only happens while a capture
    /// consumer is visible; otherwise the layout pane's own preload fills the
    /// gaps the next time it opens.
    @MainActor
    func handleLivePreviewsReenabled() {
        clearAll()
        guard hasVisibleCaptureConsumer() else { return }
        currentUpdateTask?.cancel()
        currentUpdateTask = Task { [weak self] in
            guard let self else { return }
            await self.prewarmConcealedImages(
                sections: [.hidden, .alwaysHidden],
                onlyMissingImages: true
            )
            guard !Task.isCancelled else { return }
            await self.recaptureNow(sections: MenuBarSection.Name.allCases)
            self.saveToDisk()
        }
    }
}
