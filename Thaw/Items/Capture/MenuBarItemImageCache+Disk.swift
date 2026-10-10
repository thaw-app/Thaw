//
//  MenuBarItemImageCache+Disk.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Disk Persistence

    /// Persists what is currently trusted for a faster restart. The file,
    /// its format, and the save queue live on MenuBarItemImageCacheDiskStore.
    func saveToDisk() {
        guard diskStore.isEnabled else { return }
        guard !capturesByTag.isEmpty else { return }

        let concealedIdentifiers = appState.map { appState in
            Set(
                MenuBarSection.Name.allCases
                    .filter { $0 != .visible }
                    .flatMap { appState.itemManager.itemCache[$0] }
                    .map(\.tag.tagIdentifier)
            )
        } ?? []
        diskStore.enqueueSave(
            Self.diskPersistableCaptures(
                capturesByTag: capturesByTag,
                accessTimestamps: accessTimestamps
            ),
            concealedIdentifiers: concealedIdentifiers
        )
    }

    /// Collapses the live cache to one capture per tagIdentifier, the key the
    /// disk format is written under.
    ///
    /// capturesByTag is keyed by MenuBarItemTag, which carries the window ID
    /// and literal title. tagIdentifier drops the window ID (so an entry
    /// survives an app restart) and canonicalizes the title (so "CPU 42%" and
    /// "CPU 43%" match). Two live tags therefore often share one identifier,
    /// and projecting them straight into a dictionary keyed by identifier
    /// traps on the duplicate key.
    ///
    /// The most recently accessed tag wins, since that is what live surfaces
    /// draw; the window ID breaks a tie toward the newer window. Collapsing
    /// first also spares the losers a PNG encode and keeps the store's
    /// "encoded everything or write nothing" count check meaningful.
    static nonisolated func diskPersistableCaptures(
        capturesByTag: [MenuBarItemTag: MenuBarItemGlyphCapture],
        accessTimestamps: [MenuBarItemTag: UInt64]
    ) -> [MenuBarItemTag: MenuBarItemGlyphCapture] {
        var winnersByIdentifier = [String: (tag: MenuBarItemTag, rank: (UInt64, CGWindowID))]()
        winnersByIdentifier.reserveCapacity(capturesByTag.count)

        for tag in capturesByTag.keys {
            let rank = (accessTimestamps[tag] ?? 0, tag.windowID ?? 0)
            let identifier = tag.tagIdentifier
            if let incumbent = winnersByIdentifier[identifier], incumbent.rank >= rank {
                continue
            }
            winnersByIdentifier[identifier] = (tag, rank)
        }

        return winnersByIdentifier.values.reduce(into: [:]) { result, winner in
            result[winner.tag] = capturesByTag[winner.tag]
        }
    }

    /// Loads cached images from disk the first time a consumer opens.
    ///
    /// Defers the decoded-CGImage resident cost from bootstrap to the first
    /// Thaw Bar / Search / layout-pane open. Subsequent calls are no-ops:
    /// once loaded, the images live in capturesByTag until the idle trim
    /// drops them. The trim re-arms this so a reopen reads disk again
    /// (gap-filling only, TTL applied) before the live capture path runs.
    @MainActor
    func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true
        loadFromDisk()
    }

    /// Selects the disk entries that fill a real gap in the live cache.
    ///
    /// A gap is recognized by the disk key's identity, not MenuBarItemTag's.
    /// A tag rebuilt from the file carries no window ID, so a plain
    /// capturesByTag[tag] == nil check misses the live entry for the same item
    /// and inserts a duplicate beside it. Both project to one identifier and
    /// trap the save queue, and the recapture eviction filter (which ignores
    /// window IDs so disk entries survive) keeps the pair alive for the whole
    /// process.
    ///
    /// Matching on the identifier means a stale disk pixel never overwrites a
    /// fresh capture. Ordering the candidates keeps the choice deterministic if
    /// the file holds two identifiers that canonicalize together.
    static nonisolated func diskGapFillSelections(
        loaded: [MenuBarItemTag: MenuBarItemGlyphCapture],
        cachedTags: some Sequence<MenuBarItemTag>
    ) -> [MenuBarItemTag: MenuBarItemGlyphCapture] {
        var occupied = Set(cachedTags.map(\.tagIdentifier))
        var selections = [MenuBarItemTag: MenuBarItemGlyphCapture]()

        for tag in loaded.keys.sorted(by: { $0.tagIdentifier < $1.tagIdentifier })
            where occupied.insert(tag.tagIdentifier).inserted
        {
            selections[tag] = loaded[tag]
        }
        return selections
    }

    /// Loads cached images from disk.
    ///
    /// The load is tracked rather than fired and forgotten. It decodes on a
    /// background task and merges back on the main actor, and in between the
    /// cache can be emptied on purpose by a reset or by the idle trim that
    /// exists precisely to hand those pages back. A load in flight across
    /// either one would restore the images that were just released, so the
    /// task is held for cancellation and its merge is gated on the generation
    /// it started in.
    @MainActor
    private func loadFromDisk() {
        diskLoadTask?.cancel()
        let generation = diskLoadGeneration
        diskLoadTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            guard let file = self.diskStore.readSaveFile() else { return }

            let (classifications, occupiedIdentifiers) = await MainActor.run {
                (
                    self.volatilityIndex.classificationsByKey(),
                    Set(self.capturesByTag.keys.map(\.tagIdentifier))
                )
            }
            guard !Task.isCancelled else { return }

            // Per-item TTL: the file carries one save timestamp, but each
            // item's allowed age depends on its volatility class. The store
            // has already deleted the file when even stable items would be
            // expired.
            var expiredCount = 0
            var parsed = [(tag: MenuBarItemTag, entry: [String: Any])]()
            for (tagString, entry) in file.entries {
                let wasConcealed = entry["concealed"] as? Bool ?? false
                guard file.age <= self.diskStore.diskCacheTTL(
                    for: classifications[tagString],
                    wasConcealed: wasConcealed
                ) else {
                    expiredCount += 1
                    continue
                }
                let parts = tagString.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let tag = MenuBarItemTag(
                    namespace: .string(String(parts[0])),
                    title: String(parts[1]),
                    windowID: nil
                )
                parsed.append((tag, entry))
            }

            // Skip decoding entries whose identifier the live cache already
            // holds; the load only fills gaps, and after an idle trim that is
            // most of the file. The live cache can gain entries during the
            // decode, so this is only a prefilter: the merge below still asks
            // diskGapFillSelections. Same key and ordering, so the entries
            // dropped here are exactly the ones it would drop.
            var claimed = occupiedIdentifiers
            let candidates = parsed
                .sorted { $0.tag.tagIdentifier < $1.tag.tagIdentifier }
                .filter { claimed.insert($0.tag.tagIdentifier).inserted }

            var loadedImages = [MenuBarItemTag: MenuBarItemGlyphCapture]()

            for (tag, entry) in candidates {
                guard !Task.isCancelled else { return }
                if let capture = self.diskStore.decodeEntry(entry, legacyJSON: file.isLegacyJSON) {
                    loadedImages[tag] = capture
                }
            }

            if !loadedImages.isEmpty {
                let imagesToLoad = loadedImages
                let skipped = expiredCount
                await MainActor.run {
                    // A reset or an idle trim that landed while this task
                    // was decoding released these very pages on purpose.
                    // Restoring them here would undo that silently.
                    guard self.diskLoadGeneration == generation else {
                        MenuBarItemImageCache.diagLog.debug(
                            "Discarding a disk load that finished after the cache was released"
                        )
                        return
                    }
                    let loadedCount = self.mergeDiskCaptures(imagesToLoad)
                    MenuBarItemImageCache.diagLog.debug(
                        "Loaded \(loadedCount) images from disk cache (\(Int(file.age))s old, \(skipped) expired by volatility TTL)"
                    )
                }
            }
        }
    }

    /// Applies a decoded disk snapshot without replacing a live capture.
    /// The loader checks its generation before calling this on the main actor.
    @MainActor
    @discardableResult
    func mergeDiskCaptures(_ loaded: [MenuBarItemTag: MenuBarItemGlyphCapture]) -> Int {
        let gapFill = Self.diskGapFillSelections(
            loaded: loaded,
            cachedTags: capturesByTag.keys
        )
        for (tag, image) in gapFill {
            setCapture(image, for: tag)
            // Concealed glyphs may never be read or recaptured this session.
            // Register them now rather than relying on a consumer to do it.
            updateAccessOrder(for: tag)
        }
        return gapFill.count
    }

    /// Abandons any disk load still in flight and makes its merge a no-op.
    ///
    /// Called by every path that empties the cache deliberately. Cancelling
    /// alone is not enough: the task may already be past its last cancellation
    /// check and on its way to the merge, so the generation is what actually
    /// refuses the result.
    @MainActor
    func invalidateDiskLoad() {
        diskLoadTask?.cancel()
        diskLoadTask = nil
        diskLoadGeneration &+= 1
    }

    /// Blocks saves while a reset deletes the file, and makes the store forget
    /// what it believes is on disk.
    func suspendDiskPersistenceForReset() async {
        await diskStore.suspendForReset()
    }

    /// Restores persistence after a reset failed and the cache file survived.
    func resumeDiskPersistenceAfterFailedReset() {
        diskStore.resumeAfterFailedReset()
    }
}
