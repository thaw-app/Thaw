//
//  MenuBarItemImageCache+HiddenItemCapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// How a capture the user asked for went.
nonisolated struct HiddenItemCaptureResult: Equatable {
    let captured: Int
    let total: Int
    /// The items this capture got no new picture of, by name.
    let missing: [String]

    /// Tallies items as (name, got a new picture). The same name lists once, since an
    /// app's items can share one.
    static func tally(_ items: [(name: String, hasImage: Bool)]) -> HiddenItemCaptureResult {
        var missing: [String] = []
        for item in items where !item.hasImage && !missing.contains(item.name) {
            missing.append(item.name)
        }
        return HiddenItemCaptureResult(captured: items.count(where: \.hasImage), total: items.count, missing: missing)
    }
}

extension MenuBarItemImageCache {
    /// Whether a prewarm leaves this item out for having no size on the bar. An app
    /// Native hiding keeps off the bar has none until this capture reveals it.
    @MainActor
    func skipsAsBlank(_ item: MenuBarItem) -> Bool {
        appState?.menuBarManager.nativeAppHidingExperiment.allowsCaptureReveal != true
            && Self.isBlankItem(item.bounds)
    }

    /// Unlike the automatic passes this also runs under Native hiding, where each
    /// reveal makes macOS rebuild the bar. Nil when no capture can run.
    @MainActor
    func captureHiddenItems() async -> HiddenItemCaptureResult? {
        guard let appState else { return nil }
        let native = appState.menuBarManager.nativeAppHidingExperiment
        native.allowsCaptureReveal = true
        defer { native.allowsCaptureReveal = false }
        guard ConcealedPrewarmGate.mayReveal(for: appState) else { return nil }

        let sections: [MenuBarSection.Name] = [.hidden, .alwaysHidden]
        let tally = RequestedCaptureTally()
        await prewarmConcealedImages(sections: sections, onlyMissingImages: false, tally: tally)
        let newlyCaptured = tally.tags

        let items = sections.flatMap { appState.itemManager.itemCache[$0] }
            .filter { Self.isCapturable($0) && !Self.isBlankItem($0.bounds) }
        return .tally(items.map { (name: $0.displayName, hasImage: Self.isTag($0.tag, in: newlyCaptured)) })
    }

    /// Whether a pass captured tag. A reveal can rebuild the bar, so a window ID
    /// that changed during the pass doesn't count against a non-system item.
    static nonisolated func isTag(_ tag: MenuBarItemTag, in captured: Set<MenuBarItemTag>) -> Bool {
        captured.contains(tag) || (!tag.isSystemItem && captured.contains { $0.matchesIgnoringWindowID(tag) })
    }
}
