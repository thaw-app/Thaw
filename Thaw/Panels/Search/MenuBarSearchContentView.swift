//
//  MenuBarSearchContentView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Ifrit
import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - Hosting

/// Root of the hosted hierarchy. Exists to hand the shared state down the
/// environment, which also keeps the hosting view's content type concrete.
struct MenuBarSearchRootView: View {
    let appState: AppState
    let model: MenuBarSearchModel
    let displayID: CGDirectDisplayID
    let panel: MenuBarSearchPanel

    /// The face the panel is wearing for this showing.
    ///
    /// Carried as a value rather than read back off panel so that changing
    /// the mode changes this view, which is what tells SwiftUI the hosted
    /// hierarchy is stale. The panel is a reference: reading through it left
    /// every field of this struct identical across a mode change.
    let presentation: SearchPresentation

    var body: some View {
        MenuBarSearchContentView(displayID: displayID, panel: panel, presentation: presentation)
            .environment(appState)
            .environment(appState.itemManager)
            .environment(appState.imageCache)
            .environment(model)
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

/// The search interface itself: a query field, the matching rows, and a bar
/// of actions for whichever row is highlighted.
///
/// One view for every face. Rows, keyboard navigation, focus, recents, rename,
/// the action bar and activation are shared; SearchPresentation decides the
/// chrome and which row-building policy fills the list.
private struct MenuBarSearchContentView: View {
    private typealias ListItem = SectionedListItem<MenuBarSearchModel.ItemID, MenuBarSearchListContent>

    /// A row paired with the title the fuzzy matcher ranks it by.
    private struct RankableRow: Searchable {
        let listItem: ListItem
        let title: String

        var properties: [FuseProp] {
            [FuseProp(title, weight: SearchWeights.menuBarItem.title)]
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(MenuBarItemManager.self) private var itemManager
    @Environment(MenuBarSearchModel.self) private var model
    @FocusState private var queryFieldIsFocused: Bool
    @AppStorage(Defaults.Key.showSearchShortcutBar.rawValue) private var showsShortcutBar = Defaults.DefaultValue.showSearchShortcutBar
    /// The pending refocus of the query field, replaced by the next one.
    @State private var focusTask: Task<Void, Never>?
    /// Recently activated items, shown when the query is empty. Storage is
    /// UserDefaults-backed; this instance is a stateless lens onto it.
    private let recents = MenuBarSearchRecents()

    let displayID: CGDirectDisplayID
    let panel: MenuBarSearchPanel

    /// Which face the hosting panel is wearing. Passed down from the showing
    /// that built this view rather than read back off panel, so a mode
    /// change is a change SwiftUI can see. MenuBarSearchPanel.show(on:)
    /// builds the root view immediately after adopting the mode, so the two
    /// cannot disagree.
    let presentation: SearchPresentation

    var body: some View {
        chrome
            .environment(\.menuBarSearchPanel, panel)
            .disablesAnimations(when: reduceMotion)
            .onChange(of: appState.navigationState.isSearchPresented, initial: true) { _, isPresented in
                // The panel keeps this view between showings, so onAppear runs once.
                guard isPresented else { return }
                model.selectFirstSelectableRow()
                focusQueryField()
            }
            .onChange(of: model.renameSession == nil) { _, renameEnded in
                // The rename field had the keyboard, and nothing else takes it back.
                panel.placesQueryCaretAtEnd = false
                guard renameEnded, appState.navigationState.isSearchPresented else { return }
                focusQueryField(caretAtEnd: true)
            }
            .onChange(of: model.searchText, initial: true) {
                rebuildDisplayedItems()
                model.selectFirstSelectableRow()
            }
            .onChange(of: itemManager.itemCache, initial: true) {
                // The launcher's inventory is derived from this cache, so it
                // dies with it and is rebuilt on the next row build.
                model.launcherCandidates = []
                rebuildDisplayedItems()
                model.revalidateSelection()
            }
    }

    // MARK: Chrome

    /// The panel surface the shared row list sits in.
    ///
    /// The inspector is a window: a glass panel with the field floating in a
    /// capsule above the list and an action bar below it. The launcher is
    /// Floe's: the field in a piece of glass of its own, a gap, then the
    /// results over the action bar. The assisted face is one slab, headline
    /// field, hairline, results, hairline, the same action bar, so its rows
    /// can be renamed and moved without switching modes.
    private static let launcherLook = LauncherLook(hasShadow: false)

    private static let launcherPieces = PanelPieces(
        look: launcherLook,
        corners: .rounded,
        heights: .launcher(height: SearchPresentation.launcher.contentSize.height)
    )

    @ViewBuilder
    private var chrome: some View {
        let panelShape = RoundedRectangle(cornerRadius: MenuBarSearchPanel.cornerRadius, style: .continuous)
        switch presentation {
        case .inspector:
            GlassEffectContainer {
                contentArea
                    .safeAreaBar(edge: .top, spacing: 0) { queryField }
                    .safeAreaBar(edge: .bottom, spacing: 0) { MenuBarSearchFooter(panel: panel, showsDivider: false) }
            }
            .scrollEdgeEffectStyle(.automatic, for: .vertical)
            // Clear panel glass over an interactive control capsule: the field
            // reads one step more solid than the surface it floats on, which is
            // the visionOS hierarchy this panel is the flagship for.
            .thawGlass(.panel, in: panelShape)
            .frame(width: presentation.contentSize.width, height: presentation.contentSize.height)
            .fixedSize()
        case .launcher:
            PanelSections {
                queryField
            } content: {
                contentArea
                MenuBarSearchFooter(panel: panel, showsDivider: false)
            }
            // The window draws the shadow: it ends at the panel's edge, where
            // a piece's own would be cut off.
            .modifier(PanelLook(look: Self.launcherLook, pieces: Self.launcherPieces))
            .frame(width: presentation.contentSize.width, height: presentation.contentSize.height)
        case .assisted:
            VStack(spacing: 0) {
                queryField
                Divider()
                    .opacity(0.4)
                contentArea
                MenuBarSearchFooter(panel: panel, showsDivider: true)
            }
            .frame(width: presentation.contentSize.width, height: presentation.contentSize.height)
            .thawGlass(.panel, in: panelShape)
        }
    }

    // MARK: Query field

    /// A non-activating panel hands a SwiftUI field first responder late, so the delay is load-bearing.
    /// The flag is dropped first: it can read true after the field lost the keyboard.
    /// With caretAtEnd the field keeps its text unselected, so typing adds to the query.
    private func focusQueryField(caretAtEnd: Bool = false) {
        focusTask?.cancel()
        queryFieldIsFocused = false
        focusTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            panel.placesQueryCaretAtEnd = caretAtEnd
            queryFieldIsFocused = true
        }
    }

    private var queryField: some View {
        queryFieldChrome(queryFieldRow)
    }

    private var queryFieldRow: some View {
        @Bindable var model = model
        let metrics = presentation.queryFieldMetrics
        let prompt = Text("Search menu bar items…")

        return HStack(spacing: ThawSpacing.row) {
            // Sized by the field's own text style, so it scales with the
            // query, Larger Text included, instead of staying put beside it.
            Image(systemName: "magnifyingglass")
                .font(metrics.font)
                .foregroundStyle(.secondary)

            TextField(text: $model.searchText, prompt: prompt) {
                prompt
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(metrics.font)
            .textContentType(.none)
            .autocorrectionDisabled(true)
            .writingToolsBehavior(.disabled)
            .focused($queryFieldIsFocused)
            // With the shortcut bar off, ⌘K's menu opens under the field.
            .background(alignment: .bottomLeading) {
                if !showsShortcutBar {
                    ItemActionsMenuAnchor(panel: panel)
                        .frame(width: 1, height: 1)
                }
            }

            if metrics.hasTrailingSpacer {
                Spacer()
            }
        }
        .padding(metrics.padding)
    }

    /// Wraps the field in the inspector's inset glass capsule, or passes it
    /// through flush for the launcher.
    @ViewBuilder
    private func queryFieldChrome(_ field: some View) -> some View {
        let fieldShape = Capsule(style: .continuous)
        if presentation.queryFieldMetrics.isCapsule {
            field
                .thawGlass(.field(isFocused: queryFieldIsFocused), in: fieldShape)
                .padding(.horizontal, ThawSpacing.inset)
                .padding(.top, ThawSpacing.inset)
                .padding(.bottom, ThawSpacing.row)
        } else {
            field
        }
    }

    // MARK: Content area

    /// The rows, with whatever explains their absence laid over them. The
    /// list stays mounted: swapping it out cost the query field the keyboard.
    private var contentArea: some View {
        let emptyState = emptyState
        return rowList
            .opacity(emptyState == nil ? 1 : 0)
            .accessibilityHidden(emptyState != nil)
            .overlay {
                if let emptyState {
                    emptyState
                }
            }
    }

    /// What covers the rows, or nil while they show. Every surface lists
    /// the whole inventory with an empty query, so the rows only go missing
    /// when the walk found nothing or nothing matched.
    private var emptyState: ThawEmptyState? {
        unavailableState
    }

    /// What every surface shows while there is nothing to list yet, or nil once there is.
    ///
    /// Screen Recording is deliberately absent: without it the rows render
    /// owning-app icons (the same fallback used for failed captures), so the
    /// search works under Accessibility alone.
    private var unavailableState: ThawEmptyState? {
        if !AXHelpers.isProcessTrusted() {
            // Distinct from "nothing matched": without Accessibility the item
            // walk returns an empty list, which would otherwise read as an
            // empty menu bar.
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
        if hasNoMatches {
            return .noSearchMatches { model.searchText = "" }
        }
        return nil
    }

    /// The rows, and the keyboard navigation over them, for both surfaces.
    /// Section headers ride in the list as non-selectable rows, so arrowing
    /// steps over them.
    @ViewBuilder
    private var rowList: some View {
        if presentation == .launcher {
            LauncherSearchResults()
        } else {
            sectionedRowList
        }
    }

    private var sectionedRowList: some View {
        @Bindable var model = model
        return SectionedList(
            selection: $model.selection,
            items: $model.displayedItems,
            // Only turns the list's own arrow and Return handling off: the
            // panel's key monitor owns those keys, and a second handler wrote
            // a stale highlight back after each held-arrow repeat.
            isEditing: true
        )
        .contentPadding(ThawSpacing.base)
        .scrollContentBackground(.hidden)
    }

    /// Whether the query found nothing, as opposed to there being nothing to
    /// search. The two want different empty states.
    private var hasNoMatches: Bool {
        !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty && model.displayedItems.isEmpty
    }

    // MARK: Row building

    /// Rebuilds the rows the list renders, by whichever policy this
    /// presentation searches under.
    private func rebuildDisplayedItems() {
        switch presentation {
        case .inspector: rebuildSectionedRows()
        case .launcher, .assisted: rebuildRankedRows()
        }
    }

    /// Rebuilds the rows from the item cache, section by section and, when a
    /// query is present, ranked against it.
    private func rebuildSectionedRows() {
        // The same inventory the Layout previews list.
        let inventory = DisplayedItemInventory.cache(appState: appState)
        let rows = MenuBarSection.Name.allCases.flatMap { sectionRows(for: $0, in: inventory) }

        guard !model.searchText.isEmpty else {
            // Recents ride on top of the unfiltered list, Spotlight-style.
            // They only render when resolvable, stale identifiers expire
            // silently (see MenuBarSearchRecents).
            let recentRows = recents.resolve(in: inventory).map { item in
                ListItem(
                    content: .item(item),
                    id: .item(item.tag, windowID: item.windowID),
                    isSelectable: true,
                    action: { performAction(for: item) }
                )
            }
            model.displayedItems = ListItem.recentsAbove(recentRows, rows.map(\.listItem), restHeader: nil)
            return
        }

        let candidates = rows.filter(\.listItem.isSelectable)
        // Weighted fuzzy match; the ranker settles the ordering.
        let matches = model.fuse.searchSync(model.searchText, in: candidates, by: \.properties)
        let scored = matches.map { (item: candidates[$0.index], diffScore: $0.diffScore) }
        model.displayedItems = SearchRanker.sortedByRelevance(scored).map(\.listItem)
    }

    /// One section's slice of the search list: its header row followed by
    /// its items in reverse cache order. Empty when the section is turned off.
    private func sectionRows(for name: MenuBarSection.Name, in inventory: MenuBarItemCache) -> [RankableRow] {
        if let section = appState.menuBarManager.section(withName: name), !section.isEnabled {
            return []
        }

        var rows = [
            RankableRow(
                listItem: ListItem(content: .header(name), id: .header(name), isSelectable: false, action: nil),
                title: name.localizedName
            ),
        ]
        for item in inventory.managedItems(for: name).reversed() where !item.isControlItem {
            rows.append(RankableRow(
                listItem: ListItem(
                    content: .item(item),
                    id: .item(item.tag, windowID: item.windowID),
                    isSelectable: true,
                    action: { performAction(for: item) }
                ),
                // item.displayName resolves the owning process via
                // NSRunningApplication(processIdentifier:) on every read;
                // this runs on every search-result rebuild (every keystroke),
                // so route through the memoized lookup to avoid allocating a
                // fresh NSRunningApplication per item per keystroke. Same
                // leak shape as the Thaw Bar's accessibility label.
                title: MenuBarItemDisplayName.displayName(for: item)
            ))
        }
        return rows
    }

    /// Rebuilds the ranked launchers' rows: until you type, the whole
    /// inventory in menu bar order with recents on top, so the arrows have
    /// something to move through as soon as the panel opens; then the
    /// ranked matches.
    private func rebuildRankedRows() {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        let retained = DisplayedItemInventory.cache(appState: appState)
        let inventory = launcherInventory(from: retained)

        guard !query.isEmpty else {
            // Recents are matched back against the inventory rather than
            // rebuilt, so they carry the owning-app name without a second
            // lookup. Recents the launcher cannot open (spacers, control
            // items) are not in the inventory and drop out here.
            let byIdentity = Dictionary(
                inventory.map { ($0.identityKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let recentCandidates = recents.resolve(in: retained).compactMap { byIdentity[$0.uniqueIdentifier] }
            model.displayedItems = ListItem.recentsAbove(
                candidateRows(for: recentCandidates),
                candidateRows(for: inventory),
                restHeader: .allItemsHeader
            )
            return
        }

        model.displayedItems = candidateRows(
            for: PaletteCandidate.ranked(matching: query, in: inventory, using: model.fuse)
        )
    }

    /// The launcher's inventory, built once per turnover of the item cache.
    ///
    /// Building a candidate resolves each item's owning application, an
    /// NSRunningApplication allocation per item, the exact shape
    /// MenuBarItemDisplayName exists to keep out of per-keystroke work. So
    /// the list is cached on the model and only dropped when the cache it was
    /// derived from turns over.
    private func launcherInventory(from retained: MenuBarItemCache) -> [PaletteCandidate] {
        if model.launcherCandidates.isEmpty {
            model.launcherCandidates = PaletteCandidate.inventory(from: retained)
        }
        return model.launcherCandidates
    }

    private func candidateRows(for candidates: [PaletteCandidate]) -> [ListItem] {
        candidates.map { candidate in
            let item = candidate.item
            let content: MenuBarSearchListContent = presentation == .assisted
                ? .assistedItem(item, ownerName: candidate.subtitle)
                : .launcherItem(item, ownerName: candidate.subtitle)
            return ListItem(
                content: content,
                id: .item(item.tag, windowID: item.windowID),
                isSelectable: true,
                action: { performAction(for: item) }
            )
        }
    }

    // MARK: Activation

    /// Dismisses the panel, then shows or clicks item.
    ///
    /// The panel has to be down before the click lands: a key-taking panel over
    /// the menu bar swallows the item's own menu.
    private func performAction(for item: MenuBarItem) {
        if model.renameSession?.targets(item) == true {
            return
        }
        panel.close()
        recents.record(item)
        Task {
            // Wait until the search panel is fully closed before acting on
            // the selected item. Uses KVO on isVisible so we resume as soon
            // as the panel hides rather than waiting a fixed 25 ms.
            await panel.waitUntilClosed(timeout: .milliseconds(200))
            await itemManager.activate(item: item, on: displayID)
        }
    }
}
