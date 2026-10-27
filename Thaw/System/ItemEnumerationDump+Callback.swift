//
//  ItemEnumerationDump+Callback.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Where a dump may be delivered and what the delivery carries, apart from the AX walk that makes it.
extension ItemEnumerationDump {
    /// Schemes a dump never goes to: web and messaging schemes would carry it off the machine,
    /// and the rest run code or read files.
    static let refusedCallbackSchemes: Set<String> = [
        "http", "https", "ftp", "ftps", "sftp", "ws", "wss", "mailto", "sms", "tel",
        "file", "javascript", "data", "about", "blob",
    ]

    /// The callback a dump may be delivered to, or nil unless its scheme is handled by the approved sender itself.
    /// handlerBundleIdentifier names the app that would open a URL, which tests supply directly.
    static func deliverableCallback(
        _ callback: String?,
        senderBundleIdentifier: String,
        handlerBundleIdentifier: (URL) -> String?
    ) -> URLComponents? {
        guard let callback, !callback.isEmpty,
              let components = URLComponents(string: callback),
              let scheme = components.scheme?.lowercased(), !scheme.isEmpty,
              !refusedCallbackSchemes.contains(scheme), !scheme.hasPrefix("x-apple-"),
              let url = components.url,
              let handler = handlerBundleIdentifier(url),
              handler.caseInsensitiveCompare(senderBundleIdentifier) == .orderedSame
        else {
            return nil
        }
        return components
    }

    /// The callback URL with only the file path and a URL-sized per-app summary appended.
    static func callbackURL(_ callback: URLComponents, fileURL: URL, apps: [DumpedApp]) -> URL? {
        let summary: [[String: Any]] = apps.map { app in
            [
                "bundle": app.bundleIdentifier,
                "count": app.items.count,
                "keyed": app.items.filter { $0.identifier != nil || $0.description != nil || $0.title != nil }.count,
            ]
        }

        var components = callback
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "type", value: "item-dump"))
        queryItems.append(URLQueryItem(name: "file", value: fileURL.path))
        if let summaryData = try? JSONSerialization.data(withJSONObject: summary, options: .sortedKeys),
           let summaryJSON = String(data: summaryData, encoding: .utf8)
        {
            queryItems.append(URLQueryItem(name: "data", value: summaryJSON))
        }
        components.queryItems = queryItems
        return components.url
    }
}
