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

    /// Atomic, so a write cut off by the process exiting leaves the previous file, not half of this one.
    static nonisolated let writeOptions: Data.WritingOptions = .atomic

    /// One picture's entry in the file. A title can end in a number of its own, so the identifier
    /// alone can't say whether its last :<number> is the instance; the load reads it from here.
    static nonisolated func fileEntry(png: Data, scale: CGFloat, instanceIndex: Int) -> [String: Any] {
        var entry: [String: Any] = ["png": png, "scale": scale]
        if instanceIndex > 0 {
            entry["instance"] = instanceIndex
        }
        return entry
    }

    /// Blocks until the saves already queued are on disk; for the moment before the process exits.
    nonisolated func waitForQueuedSaves() {
        queue.sync { /* Returns once the queued work has run. */ }
    }
}
