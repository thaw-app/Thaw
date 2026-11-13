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
    /// macOS had no room on the bar, so nothing was revealed: a revealed item would stay behind its overflow arrow.
    let barIsFull: Bool

    init(captured: Int, total: Int, missing: [String], kept: Int = 0, barIsFull: Bool = false) {
        self.captured = captured
        self.total = total
        self.missing = missing
        self.kept = kept
        self.barIsFull = barIsFull
    }

    static let fullBar = HiddenItemCaptureResult(captured: 0, total: 0, missing: [], barIsFull: true)

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
    /// Unlike the automatic passes this also runs under Native hiding, where each
    /// reveal makes macOS rebuild the bar. See RevealCapturePrewarm.captureHiddenItems(retakingAll:).
    @MainActor
    func captureHiddenItems(retakingAll: Bool = false) async -> HiddenItemCaptureResult? {
        guard let appState else { return nil }
        let native = appState.menuBarManager.nativeAppHidingExperiment
        native.allowsCaptureReveal = true
        defer {
            native.allowsCaptureReveal = false
            withExtendedLifetime(appState) { /* Only keeps appState alive to here. */ }
        }
        return await concealedPrewarm().captureHiddenItems(retakingAll: retakingAll)
    }

    /// Counts kept and attempted pictures using identities that survive a rebuilt menu bar.
    /// Known pictures stay counted even when Native hiding makes their parked frames narrow.
    static nonisolated func hiddenItemCaptureResult(
        items: [MenuBarItem], alreadyGood: Set<MenuBarItemTag>, newlyCaptured: Set<MenuBarItemTag>
    ) -> HiddenItemCaptureResult {
        let pictured = alreadyGood.union(newlyCaptured)
        let items = items.filter {
            Self.isCapturable($0) && !$0.tag.isControlCenterGovernable
                && (!Self.isBlankItem($0.bounds) || Self.isTag($0.tag, in: pictured))
        }
        let attempted = items.filter { !Self.isTag($0.tag, in: alreadyGood) || Self.isTag($0.tag, in: newlyCaptured) }
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
