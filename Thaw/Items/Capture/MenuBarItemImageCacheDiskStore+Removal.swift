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
}
