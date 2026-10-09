//
//  ThawBarHostingView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI

final class ThawBarHostingView: NSHostingView<ThawBarContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    override func layout() {
        super.layout()
        (window as? ThawBarPanel)?.resizeToContent()
    }

    /// What one showing of the Thaw Bar is built from.
    struct Inputs {
        let appState: AppState
        let colorManager: ThawBarColorManager
        let keyboardFocus: ThawBarKeyboardFocus
        let screen: NSScreen
        let section: MenuBarSection.Name
        let showsOnlyThawBarOnlyItems: Bool
        let folderMembers: [String]?
    }

    init(_ inputs: Inputs) {
        super.init(rootView: Self.makeContentView(inputs))
    }

    /// Reuse the hosting graph with new inputs; rebuilding on each show grows process-lifetime SwiftUI caches.
    func update(_ inputs: Inputs) {
        rootView = Self.makeContentView(inputs)
    }

    private static func makeContentView(_ inputs: Inputs) -> ThawBarContentView {
        ThawBarContentView(
            appState: inputs.appState,
            colorManager: inputs.colorManager,
            keyboardFocus: inputs.keyboardFocus,
            itemManager: inputs.appState.itemManager,
            imageCache: inputs.appState.imageCache,
            menuBarManager: inputs.appState.menuBarManager,
            visibleControlItem: inputs.appState.menuBarManager.section(withName: .visible)?.controlItem,
            screen: inputs.screen,
            section: inputs.section,
            showsOnlyThawBarOnlyItems: inputs.showsOnlyThawBarOnlyItems,
            folderMembers: inputs.folderMembers
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: ThawBarContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }
}
