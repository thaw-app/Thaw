//
//  NetworkAccessInventoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing

/// Rejects network clients outside the Privacy pane's inventory in shipping sources.
/// Add legitimate clients to both the pane and the allowance in the same change.
@Suite("Network access inventory")
struct NetworkAccessInventoryTests {
    /// Network API names requiring an explicit privacy inventory entry.
    private static let networkClientTokens = [
        "URLSession",
        "NWConnection",
        "NWPathMonitor",
        "NWBrowser",
        "NWListener",
        "WKWebView",
        "CFStreamCreatePairWithSocket",
        "getaddrinfo",
    ]

    /// Includes local packages and bundled extensions; excludes standalone ThawCtl, which has no shipping Xcode target.
    private static let shippingSourceRoots = [
        "Thaw",
        "Shared",
        "MenuBarCaptureService",
        "ThawControls",
        "MenuBarModel/Sources",
        "ThawCapture/Sources",
        "ThawUI/Sources",
    ]

    /// Repository-relative allowances; the updater wrapper uses Sparkle, but is listed in case it needs a network client.
    private static let allowedFiles: Set<String> = [
        "Thaw/System/Updates.swift",
        // The What's New fetch, listed on the Privacy pane with its switch.
        "Thaw/Settings/SettingsPanes/ChangelogView.swift",
    ]

    /// Passive route observation, documented separately from outbound requests.
    /// Allow only this token; adding a network client to the sampler still fails.
    private static let localPathMonitors: Set<String> = [
        "Thaw/Settings/Models/Widgets/StatusIconLiveSampler.swift",
    ]

    private static var repositoryRoot: URL {
        // ThawTests/Settings/<this file> -> repository root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Only the updater touches the network", arguments: shippingSourceRoots)
    func onlyUpdaterTouchesTheNetwork(sourceRoot: String) throws {
        let repositoryRoot = Self.repositoryRoot
        let root = repositoryRoot.appendingPathComponent(sourceRoot)

        // A missing root would otherwise pass with an empty scan.
        try #require(
            FileManager.default.fileExists(atPath: root.path),
            "\(sourceRoot) is no longer a source root; update shippingSourceRoots"
        )

        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )

        var offenders: [String] = []
        var scannedFiles = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
            scannedFiles += 1
            guard !Self.allowedFiles.contains(relative) else {
                continue
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in Self.networkClientTokens where source.contains(token) {
                if token == "NWPathMonitor", Self.localPathMonitors.contains(relative) {
                    continue
                }
                offenders.append("\(relative): \(token)")
            }
        }

        // Same reasoning as the existence check: an empty walk is not a pass.
        #expect(scannedFiles > 0, "\(sourceRoot) contains no Swift sources to scan")

        #expect(
            offenders.isEmpty,
            "A network client appeared outside the Privacy pane's inventory: \(offenders.joined(separator: ", "))"
        )
    }
}
