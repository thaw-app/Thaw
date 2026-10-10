//
//  AXQueries.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// One frame carries one request; reads and presses run off the app's main thread so hung owners cannot stall input taps.
public enum AXHelperRequest: Codable, Sendable, Equatable {
    /// Walks every status item on the menu bar.
    case enumerate(AXEnumerateRequest)
    /// Reads the frames of an application's menu bar titles.
    case applicationMenuFrames(pid: pid_t)
    /// Resolves the element under a point in global screen coordinates.
    case hitTest(x: Double, y: Double)
    /// Presses one of an application's own status items. With several, the
    /// one whose frame centre lies within the tolerance of the target wins.
    case pressStatusItem(pid: pid_t, targetX: Double, targetY: Double, tolerance: Double)
    /// Presses a status item MenuBarAgent hosts on behalf of sourcePID.
    case pressHostedItem(sourcePID: pid_t)
}

/// The helper's answer to an AXHelperRequest.
public enum AXHelperReply: Codable, Sendable, Equatable {
    case enumerate(AXEnumerateReply)
    /// frames is nil when the app's menu bar could not be read, which is
    /// different from a menu bar with no titles.
    case applicationMenuFrames(frames: [CGRect]?, accessibilityTrusted: Bool)
    case hitTest(AXHitTestResult?, accessibilityTrusted: Bool)
    case press(pressed: Bool, accessibilityTrusted: Bool)

    /// Whether the helper was trusted for Accessibility when it answered.
    public var accessibilityTrusted: Bool {
        switch self {
        case let .enumerate(reply): reply.accessibilityTrusted
        case let .applicationMenuFrames(_, trusted): trusted
        case let .hitTest(_, trusted): trusted
        case let .press(_, trusted): trusted
        }
    }
}

/// The element under a point, reduced to what the app decides on.
public struct AXHitTestResult: Codable, Sendable, Equatable {
    public var pid: pid_t
    public var role: String?

    public init(pid: pid_t, role: String?) {
        self.pid = pid
        self.role = role
    }
}
