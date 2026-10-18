//
//  SettingsURIParser.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A parameterless thaw:// action any sender may run, the same as its hotkey.
nonisolated enum SettingsURIAction: String, CaseIterable, Equatable, Sendable {
    case toggleHidden = "toggle-hidden"
    case toggleAlwaysHidden = "toggle-always-hidden"
    case toggleSwap = "toggle-swap"
    case search
    case toggleApplicationMenus = "toggle-application-menus"
    case toggleZenMode = "toggle-zen-mode"
    case toggleLayoutEditor = "toggle-layout-editor"
    case openSettings = "open-settings"
    case itemHints = "item-hints"
}

/// The thaw:// operations a launcher drives: it queries, ranks and picks an
/// identifier; Thaw resolves it, acts, and reports what happened.
nonisolated enum LauncherURIOperation: String, CaseIterable, Sendable {
    case listItems = "list-items"
    case activateItem = "activate-item"
    case listProfiles = "list-profiles"
    case applyProfile = "apply-profile"
    case getAppearance = "get-appearance"
    case moveItem = "move-item"

    /// The query parameter carrying the identifier the operation acts on.
    var identifierParameter: String? {
        switch self {
        case .listItems, .listProfiles, .getAppearance: nil
        case .activateItem: "item-id"
        case .applyProfile: "profile-id"
        case .moveItem: "item-id"
        }
    }
}

/// The parameters of thaw://get, passed through as given.
nonisolated struct SettingsURIGetQuery: Equatable, Sendable {
    let key: String?
    let displayUUID: String?
    let callback: String?
    let broadcast: Bool
    let requestId: String?
}

/// The raw move-item parameters; LayoutBatchMove validates them.
nonisolated struct SettingsURIMoveQuery: Equatable, Sendable {
    /// Every non-empty item-id, in the order given, duplicates kept.
    let itemIDs: [String]
    /// The first section value, empty when absent.
    let section: String
    /// The first after-id, nil when absent or empty.
    let afterID: String?

    init(itemIDs: [String], section: String, afterID: String?) {
        self.itemIDs = itemIDs
        self.section = section
        self.afterID = afterID
    }

    init(queryItems: [URLQueryItem]) {
        let parameters = SettingsURIParameters(queryItems)
        self.init(
            itemIDs: parameters.all("item-id").filter { !$0.isEmpty },
            section: parameters.first("section") ?? "",
            afterID: parameters.nonEmpty("after-id")
        )
    }
}

/// The parameters of a launcher operation. Empty values count as absent.
nonisolated struct SettingsURILauncherQuery: Equatable, Sendable {
    /// The item or profile identifier, nil when the operation takes none.
    let identifier: String?
    let callback: String?
    let broadcast: Bool
    let requestId: String?
    /// Present only for move-item.
    let move: SettingsURIMoveQuery?
}

/// The decoded intent of an incoming thaw:// URL, with the parameters each route needs.
nonisolated enum SettingsURIRoute: Equatable, Sendable {
    case set(key: String, value: String, displayUUID: String?)
    case toggle(key: String, displayUUID: String?)
    case get(SettingsURIGetQuery)
    case authorize
    /// The handler requires exactly one of the two, so both stay optional here.
    case revealItem(bundle: String?, itemID: String?, hold: Bool)
    /// Lets go of a hold from reveal-item; takes the same two parameters.
    case releaseItem(bundle: String?, itemID: String?)
    case launcher(LauncherURIOperation, SettingsURILauncherQuery)
    case proxyPress(bundle: String)
    case toggleThawBar
    /// The callback as given; the handler checks the sender can receive it.
    case dumpItems(callback: String?)
    case action(SettingsURIAction)
    /// A known host whose required query parameters were absent.
    case malformed(host: String)
    /// A host that maps to no known route.
    case unrecognized(host: String)
}

/// A parsed thaw:// URL. Every URL yields one, so the call site decides what to do with bad input.
nonisolated struct SettingsURIRequest: Equatable, Sendable {
    let route: SettingsURIRoute

    /// Routes that change settings, act on menu bar items or export data wait for the Settings URI
    /// switch and an approved sender. A malformed request comes only from such a host, so it waits too.
    var requiresAuthorization: Bool {
        switch route {
        case .action, .unrecognized: false
        case .set, .toggle, .get, .authorize, .revealItem, .releaseItem, .launcher, .proxyPress, .toggleThawBar, .dumpItems, .malformed: true
        }
    }

    /// The app version is public metadata, so thaw://get?key=version skips the sender check.
    var isVersionRead: Bool {
        if case let .get(query) = route {
            return query.key == "version"
        }
        return false
    }
}

/// Turns thaw:// URLs into requests. Free of AppKit, app state and I/O so it can be unit tested and fuzzed.
nonisolated enum SettingsURIParser {
    static func parse(_ url: URL) -> SettingsURIRequest {
        let host = url.host?.lowercased() ?? ""
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false).map {
            SettingsURIParameters($0.queryItems ?? [])
        }
        return SettingsURIRequest(route: route(host: host, parameters: parameters))
    }

    /// Parameters is nil when the URL has no readable components.
    private static func route(host: String, parameters: SettingsURIParameters?) -> SettingsURIRoute {
        if let action = SettingsURIAction(rawValue: host) {
            return .action(action)
        }
        if let operation = LauncherURIOperation(rawValue: host) {
            return .launcher(operation, launcherQuery(operation, parameters ?? SettingsURIParameters([])))
        }
        if let route = settingsRoute(host: host, parameters: parameters) ?? itemRoute(host: host, parameters: parameters) {
            return route
        }
        return .unrecognized(host: host)
    }

    private static func settingsRoute(host: String, parameters: SettingsURIParameters?) -> SettingsURIRoute? {
        switch host {
        case "set":
            guard let key = parameters?.first("key"), let value = parameters?.first("value") else {
                return .malformed(host: host)
            }
            return .set(key: key, value: value, displayUUID: parameters?.first("display"))
        case "toggle":
            guard let key = parameters?.first("key") else {
                return .malformed(host: host)
            }
            return .toggle(key: key, displayUUID: parameters?.first("display"))
        case "get":
            guard let parameters else {
                return .malformed(host: host)
            }
            return .get(getQuery(parameters))
        case "authorize":
            return .authorize
        default:
            return nil
        }
    }

    private static func itemRoute(host: String, parameters: SettingsURIParameters?) -> SettingsURIRoute? {
        switch host {
        case "reveal-item":
            guard let parameters else {
                return .malformed(host: host)
            }
            return .revealItem(
                bundle: parameters.first("bundle"),
                itemID: parameters.first("item-id"),
                hold: parameters.first("hold") == "true"
            )
        case "release-item":
            guard let parameters else {
                return .malformed(host: host)
            }
            return .releaseItem(bundle: parameters.first("bundle"), itemID: parameters.first("item-id"))
        case "proxy-press":
            guard let bundle = parameters?.nonEmpty("bundle") else {
                return .malformed(host: host)
            }
            return .proxyPress(bundle: bundle)
        case "toggle-thawbar":
            return .toggleThawBar
        case "dump-items":
            return .dumpItems(callback: parameters?.first("callback"))
        default:
            return nil
        }
    }

    private static func getQuery(_ parameters: SettingsURIParameters) -> SettingsURIGetQuery {
        SettingsURIGetQuery(
            key: parameters.first("key"),
            displayUUID: parameters.first("display"),
            callback: parameters.first("callback"),
            broadcast: parameters.first("broadcast") == "true",
            requestId: parameters.first("requestId")
        )
    }

    private static func launcherQuery(
        _ operation: LauncherURIOperation,
        _ parameters: SettingsURIParameters
    ) -> SettingsURILauncherQuery {
        SettingsURILauncherQuery(
            identifier: operation.identifierParameter.flatMap(parameters.nonEmpty),
            callback: parameters.nonEmpty("callback"),
            broadcast: parameters.nonEmpty("broadcast") == "true",
            requestId: parameters.nonEmpty("requestId"),
            move: operation == .moveItem ? SettingsURIMoveQuery(queryItems: parameters.items) : nil
        )
    }
}

/// Query lookups by name. The first item with a name wins, as URLComponents users expect.
private nonisolated struct SettingsURIParameters {
    let items: [URLQueryItem]

    init(_ items: [URLQueryItem]) {
        self.items = items
    }

    func first(_ name: String) -> String? {
        items.first { $0.name == name }?.value
    }

    /// The first value for name, nil when it is absent or empty.
    func nonEmpty(_ name: String) -> String? {
        first(name).flatMap { $0.isEmpty ? nil : $0 }
    }

    func all(_ name: String) -> [String] {
        items.filter { $0.name == name }.compactMap(\.value)
    }
}
