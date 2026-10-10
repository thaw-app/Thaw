//
//  CaptureScopeGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing

/// Keep every capture in ThawCapture so "What Thaw Sees" can show all regions Thaw reads.
@Suite("Capture scope guard")
struct CaptureScopeGuardTests {
    /// A frame-acquisition symbol and the files allowed to name it.
    private struct Rule {
        let symbol: String
        /// Repo-relative path prefixes that may reference symbol.
        let allowedPrefixes: [String]
        /// Why the exemptions exist, quoted back in the failure message.
        let rationale: String
    }

    private static let captureSources = "ThawCapture/Sources/"

    /// Bridging defines but does not call private capture primitives; leave the SkyLight loader there and enforce call-site boundaries.
    private static let bridgingDefinitions = [
        "MenuBarModel/Sources/MenuBarModel/Bridging.swift",
        "MenuBarModel/Sources/MenuBarModel/Shims.swift",
    ]

    private static let rules: [Rule] = [
        Rule(
            symbol: "Bridging.captureWindowsImage",
            // Prefix matching covers SCK and future variants at call sites, but not static func definitions.
            allowedPrefixes: [captureSources],
            rationale: "window capture is reached through ScreenCapture.captureWindows"
        ),
        Rule(
            symbol: "SCScreenshotManager",
            allowedPrefixes: [captureSources] + bridgingDefinitions,
            rationale: "single-shot ScreenCaptureKit capture belongs to ThawCapture"
        ),
        Rule(
            symbol: "SCStream(",
            allowedPrefixes: [captureSources] + bridgingDefinitions,
            rationale: "streamed ScreenCaptureKit capture belongs to ThawCapture"
        ),
        Rule(
            symbol: "SkyLightAPI.createImageFromArray",
            allowedPrefixes: [captureSources] + bridgingDefinitions,
            rationale: "the SkyLight image primitive is not a path Thaw takes"
        ),
        Rule(
            symbol: "CGWindowListCreateImage",
            allowedPrefixes: [captureSources] + bridgingDefinitions,
            rationale: "the deprecated CoreGraphics capture is not a supported path"
        ),
        Rule(
            symbol: "CGDisplayCreateImage",
            allowedPrefixes: [captureSources] + bridgingDefinitions,
            rationale: "whole-display capture is not a path Thaw takes at all"
        ),
    ]

    @Test
    func everyFrameAcquisitionLivesInThawCapture() throws {
        let root = try #require(Self.repositoryRoot(), "could not locate the repository root")
        let sources = try Self.swiftSources(under: root)
        #expect(!sources.isEmpty, "found no sources to scan; the scan itself is broken")

        for rule in Self.rules {
            let offenders = sources.filter { path in
                guard !rule.allowedPrefixes.contains(where: path.hasPrefix) else {
                    return false
                }
                guard let contents = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else {
                    return false
                }
                return Self.mentions(rule.symbol, inCodeOf: contents)
            }

            #expect(
                offenders.isEmpty,
                """
                \(rule.symbol) is referenced outside ThawCapture, in \
                \(offenders.sorted().joined(separator: ", ")). \
                Move the capture into ThawCapture, \(rule.rationale), or the \
                "What Thaw Sees" inspector no longer shows everything Thaw reads.
                """
            )
        }
    }

    // MARK: Scanning

    /// Ignore prose references so comments explaining capture choices do not trigger the guard.
    private static func mentions(_ symbol: String, inCodeOf contents: String) -> Bool {
        contents.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else {
                return false
            }
            // Anything after // on a code line is prose too.
            let code = trimmed.components(separatedBy: "//").first ?? trimmed
            return code.contains(symbol)
        }
    }

    /// Repo-relative paths of every Swift source under root.
    private static func swiftSources(under root: URL) throws -> [String] {
        let skipped: Set = [".build", ".git", ".swiftpm", ".swiftpm-overrides", "Build", "DerivedData"]
        var paths = [String]()

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if skipped.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            guard url.pathExtension == "swift" else {
                continue
            }
            // This file names every guarded symbol by definition.
            guard url.lastPathComponent != URL(filePath: #filePath).lastPathComponent else {
                continue
            }
            paths.append(url.path().replacingOccurrences(of: root.path(), with: ""))
        }
        return paths
    }

    /// Walks up from this file: <root>/ThawCapture/Tests/ThawCaptureTests/<self>.
    private static func repositoryRoot() -> URL? {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent() // ThawCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ThawCapture
            .deletingLastPathComponent() // <root>
        // A moved test file would otherwise scan nothing and pass silently.
        let marker = root.appending(path: "ThawCapture/Package.swift")
        return FileManager.default.fileExists(atPath: marker.path()) ? root : nil
    }
}
