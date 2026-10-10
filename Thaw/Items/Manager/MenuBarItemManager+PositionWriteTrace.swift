//
//  MenuBarItemManager+PositionWriteTrace.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Retained diagnostic instrumentation for reveal-order conflicts.
/// Filter [DEBUG-order-trace] and correlate BEGIN/END records by their ID.
///
/// Reading the table twice and resolving every item's key is real work on
/// every position write, so it only happens while diagnostic logging is on.
@MainActor
struct PositionWriteTrace {
    private let id = UUID().uuidString
    private let store: PermittedPositionStore
    private let before: [String: Int]
    private static let log = DiagLog(category: "PositionWriteTrace")

    /// nil while diagnostic logging is off.
    init?(context: String, items: [MenuBarItem], desiredOrder: [String], state: @autoclosure () -> String) {
        guard DiagnosticLogger.shared.isEnabled else { return nil }
        store = MenuBarPositionStoreProvider.current
        before = store.readPositions()
        let keys = before.keys.sorted()
        let inputs = items.map { item in
            let key = store.resolveKey(for: item, existingKeys: keys, positions: before, liveItems: items)
            return "\(item.uniqueIdentifier){key=\(key ?? "unresolved"),x=\(item.bounds.minX)," +
                "width=\(item.bounds.width),onScreen=\(item.isOnScreen)}"
        }
        Self.log.info("[DEBUG-order-trace] \(id) BEGIN \(context); \(state())")
        Self.log.info("[DEBUG-order-trace] \(id) desired=\(desiredOrder)")
        Self.log.info("[DEBUG-order-trace] \(id) inputs=\(inputs)")
        Self.log.info("[DEBUG-order-trace] \(id) before=\(before.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
    }

    /// Synchronous observation around a write, not proof that Thaw alone
    /// changed these rows: MenuBarAgent can also update the table concurrently.
    func finish(result: String) {
        let after = store.readPositions()
        let changes = Set(before.keys).union(after.keys).sorted().compactMap { key -> String? in
            guard before[key] != after[key] else { return nil }
            return "\(key):\(before[key].map(String.init) ?? "absent")->\(after[key].map(String.init) ?? "absent")"
        }
        Self.log.info("[DEBUG-order-trace] \(id) END result=\(result); observedChanges=\(changes)")
    }
}

extension MenuBarItemManager {
    func tracePositionWrite(context: String, items: [MenuBarItem], desiredOrder: [String]) -> PositionWriteTrace? {
        let controller = appState?.menuBarManager.sectionController
        return PositionWriteTrace(
            context: context,
            items: items,
            desiredOrder: desiredOrder,
            state: {
                let sections = items.map { item in
                    "\(item.uniqueIdentifier)=\(controller?.authoredSection(for: item.uniqueIdentifier).rawValue ?? "unknown")"
                }
                return "revealed=\(controller?.revealedSection?.rawValue ?? "none"); " +
                    "transition=\(appState?.menuBarManager.isRevealHideTransitionActive ?? false); " +
                    "cancelled=\(Task.isCancelled); sections=\(sections)"
            }()
        )
    }
}
