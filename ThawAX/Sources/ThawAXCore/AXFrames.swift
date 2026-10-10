//
//  AXFrames.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Independent serial lanes keep hung walks from blocking hits or presses: pointer drops stale waiting hits, press preserves every action in order.
/// Walk and menu lanes share one run across identical waiting requests.
public enum AXLane: String, Codable, Sendable, CaseIterable {
    case walk
    case menu
    case pointer
    case press
}

public extension AXHelperRequest {
    var lane: AXLane {
        switch self {
        case .enumerate: .walk
        case .applicationMenuFrames: .menu
        case .hitTest: .pointer
        case .pressStatusItem, .pressHostedItem: .press
        }
    }
}

/// A request tagged so its reply can be matched out of order.
public struct AXRequestFrame: Codable, Sendable, Equatable {
    public var id: UInt64
    public var request: AXHelperRequest

    public init(id: UInt64, request: AXHelperRequest) {
        self.id = id
        self.request = request
    }
}

/// The helper's answer to one AXRequestFrame.
public struct AXReplyFrame: Codable, Sendable, Equatable {
    public enum Outcome: Codable, Sendable, Equatable {
        case reply(AXHelperReply)
        /// A newer request on a latest-wins lane replaced this one before it
        /// ran. The caller asks again if it still cares.
        case superseded
    }

    public var id: UInt64
    public var outcome: Outcome

    public init(id: UInt64, outcome: Outcome) {
        self.id = id
        self.outcome = outcome
    }
}
