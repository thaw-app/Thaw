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
    /// The items still without a picture, by name.
    let missing: [String]

    var total: Int {
        captured + missing.count
    }

    /// Tallies items as (name, has a picture). The same name lists once, since an
    /// app's items can share one.
    static func tally(_ items: [(name: String, hasImage: Bool)]) -> HiddenItemCaptureResult {
        var missing: [String] = []
        for item in items where !item.hasImage && !missing.contains(item.name) {
            missing.append(item.name)
        }
        return HiddenItemCaptureResult(captured: items.count(where: \.hasImage), missing: missing)
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
        await prewarmConcealedImages(sections: sections, onlyMissingImages: false)

        let items = sections.flatMap { appState.itemManager.itemCache[$0] }
        return .tally(items.map { (name: $0.displayName, hasImage: image(for: $0.tag) != nil) })
    }
}
