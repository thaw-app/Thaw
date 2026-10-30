//
//  ProfileDeletion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Missing profile content must not prevent removal of a stale manifest entry.
enum ProfileDeletion {
    /// Keeps undo available for readable profiles and propagates every error except missing content.
    static func snapshotForUndo(load: () throws -> Profile) throws -> Profile? {
        do {
            return try load()
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    /// A listed profile may have already lost its file; unrelated deletion failures still throw.
    static func removeFile(at url: URL, isListed: Bool) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile && isListed {
            // Only the stale manifest entry remains to be removed.
        }
    }
}
