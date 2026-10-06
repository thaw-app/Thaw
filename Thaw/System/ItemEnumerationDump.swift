//
//  ItemEnumerationDump.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawAXCore

/// Diagnose stable item keys by recording raw AXExtrasMenuBar identity attributes in local JSON; no network upload.
/// thaw://dump-items?callback=<url> writes to ~/Library/Logs/Thaw/ and returns only a path and per-app summary via URL.
enum ItemEnumerationDump {
    private static let diagLog = DiagLog(category: "ItemEnumerationDump")

    /// Include first-level children because some apps publish identity on an inner button, not the container.
    struct DumpedItem: Codable {
        let index: Int
        let occurrence: Int
        let role: String?
        let title: String?
        let identifier: String?
        let description: String?
        let help: String?
        let valueDescription: String?
        let stringValue: String?
        let frameX: Double
        let frameY: Double
        let frameWidth: Double
        let frameHeight: Double
        let childCount: Int
        /// Child identity attributes for containers that publish none.
        let innerAttributes: [Inner]?

        struct Inner: Codable {
            let role: String?
            let title: String?
            let identifier: String?
            let description: String?
            let help: String?
        }
    }

    struct DumpedApp: Codable {
        let bundleIdentifier: String
        let processIdentifier: Int
        let items: [DumpedItem]
    }

    struct Report: Codable {
        let timestamp: String
        let apps: [DumpedApp]
        let discovery: [DiscoveryResult]?
    }

    struct DiscoveryResult: Codable {
        let bundleIdentifier: String
        let processIdentifier: Int
        let result: String
    }

    @discardableResult
    static func run() -> URL? {
        var dumpedApps: [DumpedApp] = []
        var discovery: [DiscoveryResult] = []

        for runningApp in NSWorkspace.shared.runningApplications {
            var result = "application wrapper unavailable; terminated=\(runningApp.isTerminated)"
            defer {
                discovery.append(DiscoveryResult(
                    bundleIdentifier: runningApp.bundleIdentifier ?? "(unknown)",
                    processIdentifier: Int(runningApp.processIdentifier),
                    result: result
                ))
            }
            guard let app = AXHelpers.application(for: runningApp) else {
                continue
            }
            result = "extras menu bar absent or unreadable"
            guard let bar = AXHelpers.extrasMenuBar(for: app) else { continue }
            guard let children = AXHelpers.childrenIfAvailable(for: bar) else {
                result = "extras menu bar children unreadable"
                continue
            }
            result = "extras menu bar children=\(children.count)"
            guard !children.isEmpty else {
                continue
            }

            // Match production's per-app screen-x occurrence order; read each frame only once.
            let frames = children.map { AXHelpers.frame(for: $0) }
            let xOrder = children.indices.sorted { lhs, rhs in
                (frames[lhs]?.minX ?? .infinity) < (frames[rhs]?.minX ?? .infinity)
            }

            var items: [DumpedItem] = []
            for (occurrence, childIndex) in xOrder.enumerated() {
                let child = children[childIndex]
                let frame = frames[childIndex] ?? .zero
                let innerChildren = AXHelpers.children(for: child)

                let inner = innerChildren.map { element in
                    let attributes = AXHelpers.descendantAttributes(for: element)
                    return DumpedItem.Inner(
                        role: attributes.role,
                        title: attributes.title?.trimmed,
                        identifier: attributes.identifier?.trimmed,
                        description: attributes.accessibilityDescription?.trimmed,
                        help: AXHelpers.help(for: element)?.trimmed
                    )
                }

                items.append(
                    DumpedItem(
                        index: childIndex,
                        occurrence: occurrence,
                        role: AXHelpers.roleString(for: child),
                        title: AXHelpers.title(for: child)?.trimmed,
                        identifier: AXHelpers.identifier(for: child)?.trimmed,
                        description: AXHelpers.description(for: child)?.trimmed,
                        help: AXHelpers.help(for: child)?.trimmed,
                        valueDescription: AXHelpers.valueDescription(for: child)?.trimmed,
                        stringValue: AXHelpers.stringValue(for: child)?.trimmed,
                        frameX: frame.minX,
                        frameY: frame.minY,
                        frameWidth: frame.width,
                        frameHeight: frame.height,
                        childCount: innerChildren.count,
                        innerAttributes: inner.isEmpty ? nil : inner
                    )
                )
            }

            dumpedApps.append(
                DumpedApp(
                    bundleIdentifier: runningApp.bundleIdentifier ?? "(pid \(runningApp.processIdentifier))",
                    processIdentifier: Int(runningApp.processIdentifier),
                    items: items
                )
            )
        }

        let report = Report(timestamp: ISO8601DateFormatter().string(from: Date()), apps: dumpedApps, discovery: discovery)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else {
            diagLog.error("dump: failed to encode report")
            return nil
        }

        let directory = logsDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            diagLog.error("dump: cannot create \(directory.path): \(error.localizedDescription)")
            return nil
        }

        let fileURL = directory.appendingPathComponent("item-dump-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            diagLog.error("dump: write failed: \(error.localizedDescription)")
            return nil
        }

        let totalItems = dumpedApps.reduce(0) { $0 + $1.items.count }
        diagLog.info("dump: \(totalItems) item(s) across \(dumpedApps.count) app(s) → \(fileURL.path)")
        return fileURL
    }

    /// Send only the file path and a URL-sized per-app summary through the thawctl callback.
    static func respond(fileURL: URL, callback: String?) {
        guard let callback, !callback.isEmpty else {
            return
        }
        guard var components = URLComponents(string: callback),
              components.scheme?.isEmpty == false
        else {
            diagLog.warning("dump: invalid callback URL \(callback)")
            return
        }

        let summary: [[String: Any]] = readApps(from: fileURL).map { app in
            [
                "bundle": app.bundleIdentifier,
                "count": app.items.count,
                "keyed": app.items.filter { $0.identifier != nil || $0.description != nil || $0.title != nil }.count,
            ]
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "type", value: "item-dump"))
        queryItems.append(URLQueryItem(name: "file", value: fileURL.path))
        if let summaryData = try? JSONSerialization.data(withJSONObject: summary),
           let summaryJSON = String(data: summaryData, encoding: .utf8)
        {
            queryItems.append(URLQueryItem(name: "data", value: summaryJSON))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            diagLog.warning("dump: failed to compose callback URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func readApps(from fileURL: URL) -> [DumpedApp] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder().decode(Report.self, from: data))?.apps ?? []
    }

    private static func logsDirectory() -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Thaw", isDirectory: true)
    }
}

private extension String {
    /// Cap long live metric strings for readable dumps and short callback URLs.
    var trimmed: String {
        String(prefix(200))
    }
}
