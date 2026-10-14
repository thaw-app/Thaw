//
//  NewIconSectionFollower.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Observation

/// Which new icons join their app's hidden ones. macOS 27 hides per app, so a
/// new icon left in Visible would bring a fully hidden app back onto the bar.
nonisolated struct NewIconArrivals {
    /// An app that rewrites an icon's title looks like a stream of new icons;
    /// past this many in one session it is left alone.
    static let placementsPerApp = 3

    private(set) var seen: Set<String>
    private var placed: [String: Int] = [:]

    init(seen: Set<String>) {
        self.seen = Set(seen.map(MenuBarItemTag.canonicalPersistentIdentifier))
    }

    /// The unseen icons in current whose app's other icons all share one hidden
    /// section, with that section. Everything in current counts as seen afterwards.
    mutating func placements(
        current: [String],
        saved: [String],
        authored: (String) -> MenuBarSectionName
    ) -> [(identifier: String, section: MenuBarSectionName)] {
        let current = MenuBarItemTag.canonicalPersistentIdentifiers(current)
        let arrivals = current.filter { !seen.contains($0) }
        guard !arrivals.isEmpty else { return [] }
        let known = Set(current).union(MenuBarItemTag.canonicalPersistentIdentifiers(saved)).subtracting(arrivals)
        seen.formUnion(arrivals)
        return arrivals.compactMap { arrival in
            guard let app = Self.app(of: arrival), !app.hasPrefix("com.apple.") else { return nil }
            let sections = Set(known.filter { Self.app(of: $0) == app }.map(authored))
            guard sections.count == 1, let section = sections.first, section != .visible,
                  placed[app, default: 0] < Self.placementsPerApp
            else { return nil }
            placed[app, default: 0] += 1
            return (arrival, section)
        }
    }

    /// The bundle ID in front of an identifier's first colon.
    private static func app(of identifier: String) -> String? {
        identifier.firstIndex(of: ":").map { String(identifier[..<$0]) }
    }
}

/// Applies NewIconArrivals as the item cache changes.
@MainActor
final class NewIconSectionFollower {
    private static let diagLog = DiagLog(category: "NewIconSectionFollower")
    private var task: Task<Void, Never>?

    func start(appState: AppState) {
        task?.cancel()
        task = Task { @MainActor [weak appState] in
            guard let itemManager = appState?.itemManager else { return }
            var arrivals: NewIconArrivals?
            let changes = Observations { itemManager.managedItems.filter { !$0.isControlItem }.map(\.uniqueIdentifier) }
            for await current in changes {
                guard let appState else { return }
                let controller = appState.menuBarManager.sectionController
                let saved = Array(controller.sectionItemOrder.values.joined())
                // The first read only says what is already there.
                guard arrivals != nil else {
                    arrivals = NewIconArrivals(seen: itemManager.knownItemIdentifiers.union(saved).union(current))
                    continue
                }
                let placements = arrivals?.placements(
                    current: current, saved: saved, authored: controller.authoredSection(for:)
                ) ?? []
                for placement in placements {
                    Self.diagLog.info("\(placement.identifier) is new and its app is in \(placement.section); placing it there")
                    appState.menuBarManager.assignSection(placement.section, identifier: placement.identifier)
                }
            }
        }
    }
}
