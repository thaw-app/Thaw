//
//  MenuBarItemImageCacheDiskStore+Removal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

extension MenuBarItemImageCacheDiskStore {
    /// Deletes the cache files after any save already queued, so none writes them back.
    nonisolated func removeCacheFiles() {
        let files = [cacheFileURL, legacyCacheFileURL].compactMap(\.self)
        queue.async {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Reads the save file once the disk work queued before this call has run. A load that starts
    /// right after removeCacheFiles() then finds the files gone, instead of reading them back first.
    nonisolated func readSaveFileAfterQueuedWork() async -> SaveFileContents? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
        return readSaveFile()
    }
}
