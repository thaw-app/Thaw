//
//  URL+PickedFile.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension URL {
    /// Reads a picked file, starting security-scoped access only when the URL grants it.
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
