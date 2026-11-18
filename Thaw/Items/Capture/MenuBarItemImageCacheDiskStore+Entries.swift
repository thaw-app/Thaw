//
//  MenuBarItemImageCacheDiskStore+Entries.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import ImageIO

/// Reading one saved file's entries: which a build may use, and their pictures.
extension MenuBarItemImageCacheDiskStore {
    /// Decodes one file entry into a capture, or nil when its pixels cannot
    /// be read.
    nonisolated func decodeEntry(_ entry: [String: Any], legacyJSON: Bool) -> MenuBarItemGlyphCapture? {
        // The plist stores PNG bytes natively; the legacy JSON stored them
        // base64-encoded. JSONSerialization hands back Double for the stored
        // scale, never CGFloat, so cast through it either way.
        let pngData: Data? = if legacyJSON {
            (entry["png"] as? String).flatMap { Data(base64Encoded: $0) }
        } else {
            entry["png"] as? Data
        }
        guard let scale = entry["scale"] as? Double,
              let data = pngData,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return MenuBarItemGlyphCapture(
            cgImage: cgImage,
            scale: CGFloat(scale),
            isFromEarlierBuild: entry[Self.earlierBuildKey] as? Bool ?? false
        )
    }

    /// The entry key marking a picture an earlier build took.
    static nonisolated let earlierBuildKey = "earlierBuild"

    /// The entries a read may use from a file, or nil when the file has nothing this build can use
    /// and should be deleted. See ImageCacheFileValidity.Verdict.
    static nonisolated func readableEntries(
        _ entries: [String: [String: Any]],
        fileVersion: Int?,
        fileBuild: String?,
        cacheVersion: Int,
        appBuild: String? = ImageCacheFileValidity.appBuild
    ) -> [String: [String: Any]]? {
        switch ImageCacheFileValidity.verdict(fileVersion: fileVersion, fileBuild: fileBuild, cacheVersion: cacheVersion, appBuild: appBuild) {
        case .current:
            return entries
        case .otherBuild:
            let kept = entriesKeptAcrossBuilds(entries)
            return kept.isEmpty ? nil : kept
        case .otherFormat:
            return nil
        }
    }

    /// The entries of another build's file that a read keeps: hidden items' pictures, each marked as
    /// an earlier build's. A visible item's picture is taken again within seconds, so it is dropped.
    static nonisolated func entriesKeptAcrossBuilds(_ entries: [String: [String: Any]]) -> [String: [String: Any]] {
        entries.reduce(into: [:]) { kept, element in
            guard element.value["concealed"] as? Bool == true else { return }
            var entry = element.value
            entry[earlierBuildKey] = true
            kept[element.key] = entry
        }
    }
}
