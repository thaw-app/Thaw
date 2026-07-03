//
//  MenuBarBackend.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Operating-system-specific menu-bar section behavior.
///
/// Two adapters make this a real seam: legacy macOS uses physical divider
/// reflow, while macOS 27 uses assertion-backed visibility and assignment-based
/// cache reconstruction.
protocol MenuBarBackend: Sendable {
    var usesAssertionHiding: Bool { get }
    var supportsLegacySectionHiding: Bool { get }

    @MainActor
    func rebucket(
        _ cache: MenuBarItemManager.ItemCache,
        hider: SimpleItemHider?,
        allowsAlwaysHidden: Bool
    ) -> MenuBarItemManager.ItemCache

    func capturableSections(
        from requested: [MenuBarSection.Name],
        revealedSection: MenuBarSection.Name?
    ) -> [MenuBarSection.Name]
}

struct LegacyMenuBarBackend: MenuBarBackend {
    let usesAssertionHiding = false
    let supportsLegacySectionHiding = true

    @MainActor
    func rebucket(
        _ cache: MenuBarItemManager.ItemCache,
        hider _: SimpleItemHider?,
        allowsAlwaysHidden _: Bool
    ) -> MenuBarItemManager.ItemCache {
        cache
    }

    func capturableSections(
        from requested: [MenuBarSection.Name],
        revealedSection _: MenuBarSection.Name?
    ) -> [MenuBarSection.Name] {
        requested
    }
}

struct AssertionMenuBarBackend: MenuBarBackend {
    let usesAssertionHiding = true
    let supportsLegacySectionHiding = false

    @MainActor
    func rebucket(
        _ cache: MenuBarItemManager.ItemCache,
        hider: SimpleItemHider?,
        allowsAlwaysHidden: Bool
    ) -> MenuBarItemManager.ItemCache {
        guard let hider else { return cache }
        return CacheRebucketter.rebucket(
            cache,
            sectionFor: { hider.section(for: $0) },
            sectionAssignment: hider.sectionAssignment,
            allowsAlwaysHidden: allowsAlwaysHidden,
            retainedSnapshotFor: { hider.snapshot(for: $0) },
            orderedItems: { hider.ordered($0, in: $1) }
        )
    }

    func capturableSections(
        from requested: [MenuBarSection.Name],
        revealedSection: MenuBarSection.Name?
    ) -> [MenuBarSection.Name] {
        requested.filter { section in
            switch (section, revealedSection) {
            case (.visible, _), (.hidden, .hidden), (.hidden, .alwaysHidden), (.alwaysHidden, .alwaysHidden):
                true
            default:
                false
            }
        }
    }
}

enum MenuBarBackendFactory {
    static let current: any MenuBarBackend = {
        if #available(macOS 27, *) {
            return AssertionMenuBarBackend()
        } else {
            return LegacyMenuBarBackend()
        }
    }()
}
