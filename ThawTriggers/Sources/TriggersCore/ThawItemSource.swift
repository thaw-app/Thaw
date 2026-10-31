//
//  ThawItemSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

/// The menu bar items Thaw last reported, asked for with thaw://list-items.
@MainActor
@Observable
public final class ThawItemSource {
    public private(set) var items: [ThawItem] = []
    public private(set) var problem: String?
    @ObservationIgnored public var request: ((String) -> Void)?
    @ObservationIgnored private var pendingRequestID: String?

    public init() {}

    public func refresh() {
        let requestID = UUID().uuidString
        pendingRequestID = requestID
        request?(requestID)
    }

    public func receive(_ reply: ThawItemList.Reply) {
        guard reply.requestID == pendingRequestID else { return }
        switch reply.items {
        case let .success(items):
            self.items = items
            problem = nil
        case let .failure(.thaw(_, details)):
            problem = details
        }
    }
}
