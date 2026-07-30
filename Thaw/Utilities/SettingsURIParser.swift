//
//  SettingsURIParser.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A parameterless action reachable via `thaw://`.
enum SettingsURIAction: String, CaseIterable, Equatable {
    case toggleHidden = "toggle-hidden"
    case toggleAlwaysHidden = "toggle-always-hidden"
    case search
    case toggleThawbar = "toggle-thawbar"
    case toggleApplicationMenus = "toggle-application-menus"
    case openSettings = "open-settings"
}

/// The decoded intent of an incoming `thaw://` URL.
enum SettingsURIRoute: Equatable {
    case set(key: String, value: String, displayUUID: String?)
    case toggle(key: String, displayUUID: String?)
    case get(
        key: String?,
        displayUUID: String?,
        callback: String?,
        broadcast: Bool,
        requestId: String?
    )
    case authorize
    case action(SettingsURIAction)
    /// A settings host whose required query parameters were absent.
    case malformed(host: String)
    /// A host that maps to no known route.
    case unrecognized(host: String)
}

/// A parsed `thaw://` URL.
///
/// Parsing is total: every URL yields a request, and unroutable input is
/// represented as ``SettingsURIRoute/malformed(host:)`` or
/// ``SettingsURIRoute/unrecognized(host:)`` rather than being discarded. This
/// keeps the decision of *what to do* with bad input at the call site, where
/// the diagnostic log and the authorization gate live.
struct SettingsURIRequest: Equatable {
    let route: SettingsURIRoute

    /// Manual sender override supplied via the `bundleId` query item.
    ///
    /// Only honored by DEBUG builds; the parser always records it so that the
    /// release-build behavior of ignoring it is expressed at the call site.
    let bundleIdOverride: String?

    /// `thaw://get?key=version` is read-only metadata and skips authorization.
    var isVersionQuery: Bool {
        if case let .get(key, _, _, _, _) = route {
            return key == "version"
        }
        return false
    }

    /// Whether the route passes through the settings authorization gate.
    var requiresAuthorization: Bool {
        switch route {
        case .set, .toggle, .get, .authorize, .malformed:
            true
        case .action, .unrecognized:
            false
        }
    }
}

/// Decomposes `thaw://` URLs into ``SettingsURIRequest`` values.
///
/// This is deliberately free of AppKit, app state, and I/O so that the one
/// parser handling attacker-reachable input can be unit tested and fuzzed.
enum SettingsURIParser {
    static func parse(_ url: URL) -> SettingsURIRequest {
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems

        func query(_ name: String) -> String? {
            items?.first { $0.name == name }?.value
        }

        let bundleIdOverride = query("bundleId").flatMap { $0.isEmpty ? nil : $0 }
        let displayUUID = query("display")

        let route: SettingsURIRoute
        switch host {
        case "set":
            if let key = query("key"), let value = query("value") {
                route = .set(key: key, value: value, displayUUID: displayUUID)
            } else {
                route = .malformed(host: host)
            }
        case "toggle":
            if let key = query("key") {
                route = .toggle(key: key, displayUUID: displayUUID)
            } else {
                route = .malformed(host: host)
            }
        case "get":
            if components == nil {
                route = .malformed(host: host)
            } else {
                route = .get(
                    key: query("key"),
                    displayUUID: displayUUID,
                    callback: query("callback"),
                    broadcast: query("broadcast") == "true",
                    requestId: query("requestId")
                )
            }
        case "authorize":
            route = .authorize
        default:
            if let action = SettingsURIAction(rawValue: host) {
                route = .action(action)
            } else {
                route = .unrecognized(host: host)
            }
        }

        return SettingsURIRequest(route: route, bundleIdOverride: bundleIdOverride)
    }
}
