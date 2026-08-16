//
//  MenuBarItemManager+CacheGate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import AXSwift6
import Cocoa
import Collections
import Combine

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics
import Observation
import os.lock

// MARK: - Cache Gate

extension MenuBarItemManager {
    enum LayoutResetTarget: Sendable {
        case visible
        case hidden
        case alwaysHidden

        nonisolated func contains(
            itemBounds: CGRect,
            hiddenBounds: CGRect,
            alwaysHiddenBounds: CGRect?
        ) -> Bool {
            switch self {
            case .visible:
                return itemBounds.minX >= hiddenBounds.maxX
            case .hidden:
                guard itemBounds.maxX <= hiddenBounds.minX else { return false }
                guard let alwaysHiddenBounds else { return true }
                return itemBounds.minX >= alwaysHiddenBounds.maxX
            case .alwaysHidden:
                guard let alwaysHiddenBounds else { return false }
                return itemBounds.maxX <= alwaysHiddenBounds.minX
            }
        }

        var logString: String {
            switch self {
            case .visible: "visible"
            case .hidden: "hidden"
            case .alwaysHidden: "always-hidden"
            }
        }

        nonisolated var movesAllCandidatesInFirstPass: Bool {
            switch self {
            case .hidden: true
            case .visible, .alwaysHidden: false
            }
        }

        nonisolated var requiresAlwaysHiddenDivider: Bool {
            switch self {
            case .alwaysHidden: true
            case .visible, .hidden: false
            }
        }
    }

    /// Serializes cache operations to prevent races between concurrent
    /// `cacheItemsRegardless` calls. When a relocation move is in flight,
    /// a concurrent call could snapshot item positions before the move
    /// completes, caching them in the wrong section.
    ///
    /// Concurrent calls are dropped; the next trigger (space change,
    /// periodic refresh, app launch notification) will pick up changes.
    actor CacheGate {
        private var isInProgress = false

        func begin() -> Bool {
            guard !isInProgress else { return false }
            isInProgress = true
            return true
        }

        func end() {
            isInProgress = false
        }
    }
}
