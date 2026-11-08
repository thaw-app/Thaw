//
//  MenuBarSearchContentView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - Hosting

/// Root of the hosted hierarchy. Hands the shared state down the
/// environment, which also keeps the hosting view's content type concrete.
struct MenuBarSearchRootView: View {
    let appState: AppState
    let model: MenuBarSearchModel
    let panel: MenuBarSearchPanel

    /// The layout for this showing, carried as a value so a change of layout
    /// is a change SwiftUI can see.
    let presentation: SearchPresentation

    var body: some View {
        MenuBarSearchContentView(panel: panel, presentation: presentation)
            .environment(appState)
            .environment(appState.itemManager)
            .environment(model)
            .environment(\.menuBarSearchPanel, panel)
    }
}

/// Hosts the search interface. Insets are zeroed because the chromeless
/// panel hands the content the whole frame.
final class MenuBarSearchHostingView: NSHostingView<MenuBarSearchRootView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }
}

// MARK: - Content

/// The search panel as Floe's launcher: the field and the results in two
/// pieces of glass, in the menu bar's look.
private struct MenuBarSearchContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(MenuBarItemManager.self) private var itemManager
    @Environment(MenuBarSearchModel.self) private var model
    @AppStorage(Defaults.Key.showSearchShortcutBar.rawValue) private var showsShortcutBar = Defaults.DefaultValue.showSearchShortcutBar

    /// Bumped to give the search field the keyboard.
    @State private var focusToken = 0
    @State private var focusTask: Task<Void, Never>?

    let panel: MenuBarSearchPanel
    let presentation: SearchPresentation

    /// Collapsed to the field alone: Compact with nothing typed. A rename
    /// keeps its row on screen.
    private var isCollapsed: Bool {
        presentation.isCollapsed(query: model.searchText) && model.renameSession == nil
    }

    var body: some View {
        let isCollapsed = isCollapsed
        let look = appState.searchLauncherLook
        let pieces = PanelPieces(
            look: look,
            corners: .rounded,
            heights: SearchPanelGeometry.pieceHeights(isCollapsed: isCollapsed)
        )
        GlassEffectContainer {
            PanelSections(showsContent: !isCollapsed) {
                queryField
            } content: {
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MenuBarSearchFooter(panel: panel)
            }
        }
        .frame(
            width: SearchPanelGeometry.fullSize.width,
            height: SearchPanelGeometry.contentSize(isCollapsed: isCollapsed).height,
            alignment: .top
        )
        .modifier(PanelLook(look: look, pieces: pieces))
        .padding(SearchPanelGeometry.margin)
        // The window is resized a moment before or after the content: the field stays at the top meanwhile.
        .frame(maxHeight: .infinity, alignment: .top)
        .disablesAnimations(when: reduceMotion)
        .onChange(of: appState.navigationState.isSearchPresented, initial: true) { _, isPresented in
            // The panel keeps this view between showings, so onAppear runs once.
            guard isPresented else { return }
            refresh()
            model.selectFirstRow()
            focusQueryField()
        }
        .onChange(of: model.renameSession == nil) { _, renameEnded in
            // The rename field had the keyboard, and nothing else takes it back.
            panel.placesQueryCaretAtEnd = false
            guard renameEnded, appState.navigationState.isSearchPresented else { return }
            focusQueryField(caretAtEnd: true)
        }
        .onChange(of: model.searchText) {
            refresh()
            model.selectFirstRow()
        }
        .onChange(of: itemManager.itemCache, initial: true) {
            // The inventory is derived from this cache, so it dies with it.
            model.candidates = []
            refresh()
        }
        .onChange(of: isCollapsed) { _, isCollapsed in
            panel.fitFrame(isCollapsed: isCollapsed)
        }
    }

    private func refresh() {
        model.refresh(from: DisplayedItemInventory.cache(appState: appState), sections: appState.searchSections)
    }

    // MARK: Search field

    private var queryField: some View {
        @Bindable var model = model
        return SearchQueryField(
            prompt: String(localized: "Search menu bar items…"),
            text: $model.searchText,
            focusToken: focusToken
        ) {
            // With the shortcut bar off, ⌘K's menu opens from the field.
            if !showsShortcutBar {
                ItemActionsMenuAnchor(panel: panel)
                    .frame(width: 1, height: 1)
            }
        }
    }

    /// A non-activating panel hands a SwiftUI field the keyboard late, hence the delay.
    /// caretAtEnd leaves the text unselected, so typing appends.
    private func focusQueryField(caretAtEnd: Bool = false) {
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            panel.placesQueryCaretAtEnd = caretAtEnd
            focusToken += 1
        }
    }

    // MARK: Content area

    /// The results, with whatever explains their absence laid over them. The
    /// list stays mounted: swapping it out cost the search field the keyboard.
    private var contentArea: some View {
        let emptyState = emptyState
        return MenuBarSearchList()
            .opacity(emptyState == nil ? 1 : 0)
            .accessibilityHidden(emptyState != nil)
            .overlay {
                if let emptyState {
                    emptyState
                }
            }
    }

    /// What covers the results, or nil while they show. Screen Recording is
    /// not needed: rows fall back to app icons.
    private var emptyState: ThawEmptyState? {
        if !AXHelpers.isProcessTrusted() {
            // Distinct from "nothing matched": without Accessibility the item
            // walk returns an empty list, which would read as an empty menu bar.
            return ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "\(Constants.displayName) needs Accessibility to list your menu bar items.",
                actionTitle: "Grant Access",
                action: { appState.permissions.accessibility.performRequest() }
            )
        }
        if itemManager.hasNoManagedItems {
            return ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "Reading your menu bar…",
                isLoading: true
            )
        }
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty, model.results.isEmpty {
            return .noSearchMatches { model.searchText = "" }
        }
        return nil
    }
}
