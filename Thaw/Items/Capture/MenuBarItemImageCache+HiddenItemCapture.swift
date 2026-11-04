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
    /// The items left alone because their picture was already good.
    let kept: Int

    init(captured: Int, total: Int, missing: [String], kept: Int = 0) {
        self.captured = captured
        self.total = total
        self.missing = missing
        self.kept = kept
    }

    /// Tallies items as (name, got a new picture), with kept items counted apart. The same
    /// name lists once, since an app's items can share one.
    static func tally(_ items: [(name: String, hasImage: Bool)], kept: Int = 0) -> HiddenItemCaptureResult {
        var missing: [String] = []
        for item in items where !item.hasImage && !missing.contains(item.name) {
            missing.append(item.name)
        }
        return HiddenItemCaptureResult(captured: items.count(where: \.hasImage), total: items.count, missing: missing, kept: kept)
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
    /// reveal makes macOS rebuild the bar. Items whose picture is already good are left
    /// alone unless retakingAll, since each reveal risks a worse one. Nil when no capture can run.
    @MainActor
    func captureHiddenItems(retakingAll: Bool = false) async -> HiddenItemCaptureResult? {
        guard let appState else { return nil }
        let native = appState.menuBarManager.nativeAppHidingExperiment
        native.allowsCaptureReveal = true
        defer { native.allowsCaptureReveal = false }
        guard ConcealedPrewarmGate.mayReveal(for: appState) else { return nil }

        let sections: [MenuBarSection.Name] = [.hidden, .alwaysHidden]
        let alreadyGood = retakingAll ? [] : Set(sections.flatMap { appState.itemManager.itemCache[$0] }
            .filter { !Self.prewarmNeedsCapture(cachedImage: image(for: $0.tag), wouldAttemptCapture: true) }
            .map(\.tag))
        let tally = RequestedCaptureTally()
        await prewarmConcealedImages(sections: sections, onlyMissingImages: !retakingAll, tally: tally)
        let newlyCaptured = tally.tags

        let items = sections.flatMap { appState.itemManager.itemCache[$0] }
            .filter { Self.isCapturable($0) && !Self.isBlankItem($0.bounds) }
        let attempted = items.filter { !alreadyGood.contains($0.tag) || Self.isTag($0.tag, in: newlyCaptured) }
        return .tally(
            attempted.map { (name: $0.displayName, hasImage: Self.isTag($0.tag, in: newlyCaptured)) },
            kept: items.count - attempted.count
        )
    }

    /// Whether a pass captured tag. A reveal can rebuild the bar, so a window ID
    /// that changed during the pass doesn't count against a non-system item.
    static nonisolated func isTag(_ tag: MenuBarItemTag, in captured: Set<MenuBarItemTag>) -> Bool {
        captured.contains(tag) || (!tag.isSystemItem && captured.contains { $0.matchesIgnoringWindowID(tag) })
    }
}
