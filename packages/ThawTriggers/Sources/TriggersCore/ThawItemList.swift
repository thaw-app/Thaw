//
//  ThawItemList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A menu bar item as thaw://list-items describes it.
public struct ThawItem: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let section: String
    public let bundleId: String?

    public init(id: String, name: String, section: String, bundleId: String?) {
        self.id = id
        self.name = name
        self.section = section
        self.bundleId = bundleId
    }
}

/// Reads Thaw's answer to thaw://list-items.
public enum ThawItemList {
    public enum Failure: Error, Equatable, Sendable {
        case thaw(code: String, details: String)
    }

    public struct Reply: Equatable, Sendable {
        public let requestID: String?
        public let items: Result<[ThawItem], Failure>
    }

    private struct Payload: Decodable {
        let items: [ThawItem]
    }

    private struct Envelope: Decodable {
        let operation: String
        let requestId: String?
        let status: String
        let error: String?
        let details: String?
        let data: Payload?
    }

    /// The reply in a callback URL, or nil when the URL isn't one.
    public static func reply(fromCallback url: URL) -> Reply? {
        guard url.host == "list-items",
              let json = URLComponents(url: url, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "data" })?.value,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(json.utf8)),
              envelope.operation == "list-items"
        else {
            return nil
        }
        if envelope.status == "success", let items = envelope.data?.items {
            return Reply(requestID: envelope.requestId, items: .success(items))
        }
        let failure = Failure.thaw(code: envelope.error ?? "unknown", details: envelope.details ?? "")
        return Reply(requestID: envelope.requestId, items: .failure(failure))
    }
}
