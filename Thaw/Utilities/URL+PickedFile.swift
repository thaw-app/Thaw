//
//  URL+PickedFile.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension URL {
    /// The contents of a file the user picked in a file importer. Thaw is not
    /// sandboxed, so a picked URL is often a plain file URL that grants no
    /// security-scoped access; the file is read either way, and access is
    /// released only when it was granted.
    nonisolated func contentsOfPickedFile() throws -> Data {
        let didAccess = startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: self)
    }
}
