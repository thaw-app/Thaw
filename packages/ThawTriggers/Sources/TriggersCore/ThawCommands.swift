//
//  ThawCommands.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The thaw:// requests the module sends. See docs/URI_SCHEMES.md.
public enum ThawCommands {
    /// Keeps an item shown until ``release(itemID:)``.
    public static func hold(itemID: String) -> URL {
        url("reveal-item", ["item-id": itemID, "hold": "true"])
    }

    public static func release(itemID: String) -> URL {
        url("release-item", ["item-id": itemID])
    }

    /// Asks for the menu bar items; Thaw answers by opening
    /// `<callbackScheme>://list-items?data=<json>`.
    public static func listItems(callbackScheme: String, requestID: String) -> URL {
        url("list-items", ["callback": "\(callbackScheme)://list-items", "requestId": requestID])
    }

    private static func url(_ host: String, _ parameters: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = "thaw"
        components.host = host
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            preconditionFailure("thaw://\(host) with these parameters is always a valid URL")
        }
        return url
    }
}
