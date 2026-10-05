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

/// The search interface itself: a query field, the matching rows, and, in the
/// inspector presentation, a bar of actions for whichever row is highlighted.
///
/// One view for both surfaces. The row list, keyboard navigation, query field
/// focus, recents and activation are shared; SearchPresentation decides the
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

    /// Which sections the settings allow the search to look through, and in
    /// what order.
    private struct SearchScope: Equatable {
        let sectionOrder: [MenuBarSection.Name]
        let includesVisible: Bool
        let includesHidden: Bool
        let includesAlwaysHidden: Bool

        func includes(_ name: MenuBarSection.Name) -> Bool {
            switch name {
            case .visible: includesVisible
            case .hidden: includesHidden
            case .alwaysHidden: includesAlwaysHidden
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(MenuBarItemManager.self) private var itemManager
    @Environment(MenuBarSearchModel.self) private var model
    @FocusState private var queryFieldIsFocused: Bool
    @AppStorage(Defaults.Key.rememberSearchQuery.rawValue) private var rememberSearchQuery = Defaults.DefaultValue.rememberSearchQuery
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

    private var searchScope: SearchScope {
        let advanced = appState.settings.advanced
        return SearchScope(
            sectionOrder: advanced.searchSectionOrder,
            includesVisible: advanced.searchIncludeVisible,
            includesHidden: advanced.searchIncludeHidden,
            includesAlwaysHidden: advanced.searchIncludeAlwaysHidden
        )
    }

    var body: some View {
        chrome
            .environment(\.menuBarSearchPanel, panel)
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: appState.navigationState.isSearchPresented, initial: true) { _, isPresented in
                // The panel keeps this view between showings, so onAppear runs once.
                guard isPresented else { return }
                focusQueryField()
            }
            .onChange(of: hasNoMatches) {
                // Swapping the rows for the empty state can cost the field the keyboard.
                guard model.renameSession == nil else { return }
                focusQueryField()
            }
            .onChange(of: model.searchText, initial: true) {
                rebuildDisplayedItems()
                selectFirstSelectableRow()
            }
            .onChange(of: itemManager.itemCache, initial: true) {
                // The launcher's inventory is derived from this cache, so it
                // dies with it and is rebuilt on the next row build.
                model.launcherCandidates = []
                rebuildDisplayedItems()
                if model.selection == nil {
                    selectFirstSelectableRow()
                }
            }
            .onChange(of: searchScope) {
                rebuildDisplayedItems()
                ensureValidSelection()
            }
    }

    // MARK: Chrome

    /// The panel surface the shared row list sits in.
    ///
    /// The inspector is a window: a glass panel with the field floating in a
    /// capsule above the list and an action bar below it. The launcher is a
    /// slab, headline field, hairline, results, because everything else is
    /// something to read on a surface you are about to dismiss.
    @ViewBuilder
    private var chrome: some View {
        let panelShape = RoundedRectangle(cornerRadius: MenuBarSearchPanel.cornerRadius, style: .continuous)
        switch presentation {
        case .inspector:
            GlassEffectContainer {
                contentArea
                    .safeAreaBar(edge: .top, spacing: 0) { queryField }
                    .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
            }
            .scrollEdgeEffectStyle(.automatic, for: .vertical)
            // Clear panel glass over an interactive control capsule: the field
            // reads one step more solid than the surface it floats on, which is
            // the visionOS hierarchy this panel is the flagship for.
            .thawGlass(.panel, in: panelShape)
            .frame(width: presentation.contentSize.width, height: presentation.contentSize.height)
            .fixedSize()
        case .launcher, .assisted:
            VStack(spacing: 0) {
                queryField
                Divider()
                    .opacity(0.4)
                contentArea
            }
            .frame(width: presentation.contentSize.width, height: presentation.contentSize.height)
            .thawGlass(.panel, in: panelShape)
        }
    }

    // MARK: Query field

    /// A non-activating panel hands a SwiftUI field first responder late, so the delay is load-bearing.
    /// The flag is dropped first: it can read true after the field lost the keyboard.
    private func focusQueryField() {
        queryFieldIsFocused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            queryFieldIsFocused = true
        }
    }

    private var queryField: some View {
        queryFieldChrome(queryFieldRow)
    }

    private var queryFieldRow: some View {
        @Bindable var model = model
        let metrics = presentation.queryFieldMetrics
        let prompt = self.prompt

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

    /// What the empty field asks for, which is the clearest statement of what
    /// each surface is: one searches an inventory, the other opens a thing.
    private var prompt: Text {
        switch presentation {
        case .inspector: Text("Search menu bar items…")
        case .launcher: Text("Open a menu bar item…")
        case .assisted: Text("Find a menu bar item…")
        }
    }

    // MARK: Content area

    /// Either the matching rows or the state that explains why there are none.
    @ViewBuilder
    private var contentArea: some View {
        switch presentation {
        case .inspector:
            inspectorContentArea
        case .launcher, .assisted:
            launcherContentArea
        }
    }

    /// The same ladder the launcher walks, minus its "start typing" rung: the
    /// inspector lists everything with an empty query, so an empty list there
    /// means the walk found nothing, not that the user has not asked yet.
    ///
    /// Screen Recording is deliberately absent: without it the rows render
    /// owning-app icons (the same fallback used for failed captures), so the
    /// inspector works under Accessibility alone.
    @ViewBuilder
    private var inspectorContentArea: some View {
        if !AXHelpers.isProcessTrusted() {
            ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "\(Constants.displayName) needs Accessibility to list your menu bar items.",
                actionTitle: "Grant Access",
                action: { appState.permissions.accessibility.performRequest() }
            )
        } else if itemManager.hasNoManagedItems {
            ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "Reading your menu bar…",
                isLoading: true
            )
        } else if hasNoMatches {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No items match",
                caption: "Try part of the item's name or the app that owns it."
            )
        } else {
            rowList
        }
    }

    @ViewBuilder
    private var launcherContentArea: some View {
        if !AXHelpers.isProcessTrusted() {
            // Distinct from "nothing matched": without Accessibility the item
            // walk returns an empty list, which would otherwise read as an
            // empty menu bar.
            ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "\(Constants.displayName) needs Accessibility to list your menu bar items.",
                actionTitle: "Grant Access",
                action: { appState.permissions.accessibility.performRequest() }
            )
        } else if itemManager.hasNoManagedItems {
            ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "Reading your menu bar…",
                isLoading: true
            )
        } else if hasNoMatches {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No items match",
                caption: "Try part of the item's name or the app that owns it."
            )
        } else if model.displayedItems.isEmpty {
            ThawEmptyState(
                systemImage: "clock",
                title: "Start typing to find an item",
                caption: "Items you open from here show up as recents."
            )
        } else {
            rowList
        }
    }

    /// The rows, and the keyboard navigation over them, for both surfaces.
    /// Section headers ride in the list as non-selectable rows, so arrowing
    /// steps over them.
    private var rowList: some View {
        @Bindable var model = model
        return SectionedList(
            selection: $model.selection,
            items: $model.displayedItems,
            isEditing: model.renameSession != nil
        )
        .contentPadding(ThawSpacing.base)
        .scrollContentBackground(.hidden)
    }

    /// Whether the query found nothing, as opposed to there being nothing to
    /// search. The two want different empty states.
    private var hasNoMatches: Bool {
        !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty && model.displayedItems.isEmpty
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: ThawSpacing.base) {
            refusalNotice
            actionRow
                .buttonStyle(SearchPanelButtonStyle())
        }
        .padding(ThawSpacing.compact)
        .padding(.horizontal, ThawSpacing.tight)
    }

    /// Why a move asked for here did not happen.
    ///
    /// The same notice the layout pane shows, reading the same feedback
    /// centre. A refused move from search has nothing else to show for itself,
    /// and the pane that would otherwise explain it is not open.
    @ViewBuilder
    private var refusalNotice: some View {
        if let refusal = appState.layoutFeedback.refusal {
            SettingsWarningPill(
                title: LocalizedStringKey(refusal.title),
                message: LocalizedStringKey(refusal.message),
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                actionTitle: "Dismiss"
            ) {
                appState.layoutFeedback.clear()
            }
            .transition(reduceMotion ? .identity : .opacity)
        }
    }

    private var actionRow: some View {
        HStack {
            Button {
                panel.close()
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(ThawSpacing.hairline)
            }
            .help("Open Settings")
            .accessibilityLabel("Open Settings")

            Toggle("Remember last search", isOn: $rememberSearchQuery)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Spacer()

            if let selection = model.selection, let item = panel.cachedItem(for: selection) {
                if model.renameSession == nil {
                    ShortcutHintButton(title: String(localized: "Edit Name")) {
                        panel.beginRenamingSelection()
                    } hint: {
                        KeyCapView(text: "⌘")
                        Text(verbatim: "+")
                        KeyCapView(text: "E")
                    }
                    ShortcutHintButton(title: String(localized: "Actions…")) {
                        panel.presentItemActions()
                    } hint: {
                        KeyCapView(text: "⌘")
                        Text(verbatim: "+")
                        KeyCapView(text: "K")
                    }
                    // The actions menu hangs off this button, so it has to be
                    // reachable as an AppKit view: the anchor sits behind the
                    // button and takes its frame.
                    .background { ItemActionsMenuAnchor(panel: panel) }
                    ShortcutHintButton(
                        title: isEffectivelyVisible(item)
                            ? String(localized: "Click Item")
                            : String(localized: "Show Item")
                    ) {
                        performAction(for: item)
                    } hint: {
                        KeyCapView(systemImage: "return")
                    }
                } else {
                    ShortcutHintButton(title: String(localized: "Cancel")) {
                        model.renameSession = nil
                    } hint: {
                        KeyCapView(text: "⎋", font: ThawType.detail)
                    }
                    .keyboardShortcut(.cancelAction)
                    ShortcutHintButton(title: String(localized: "Rename")) {
                        panel.commitRename()
                    } hint: {
                        KeyCapView(systemImage: "return")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// Brings the app to the front and opens its settings window.
    private func openSettingsWindow() {
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    // MARK: Selection

    /// Highlights the topmost row that can actually be acted on.
    private func selectFirstSelectableRow() {
        model.selection = model.displayedItems.first(where: \.isSelectable)?.id
    }

    /// Re-selects the first item when the current selection has been
    /// filtered out of displayedItems (or was never set).
    private func ensureValidSelection() {
        if let selection = model.selection, model.displayedItems.contains(where: { $0.id == selection }) {
            return
        }
        selectFirstSelectableRow()
    }

    // MARK: Row building

    /// Rebuilds the rows the list renders, by whichever policy this
    /// presentation searches under.
    private func rebuildDisplayedItems() {
        switch presentation {
        case .inspector: rebuildSectionedRows()
        case .launcher: rebuildRankedRows(recentsOnlyWhenEmpty: true)
        case .assisted: rebuildRankedRows(recentsOnlyWhenEmpty: false)
        }
    }

    /// Rebuilds the rows from the item cache, filtered by the configured
    /// search scope and, when a query is present, ranked against it.
    private func rebuildSectionedRows() {
        let scope = searchScope
        let rows = scope.sectionOrder.flatMap { sectionRows(for: $0, in: scope) }

        guard !model.searchText.isEmpty else {
            // Recents ride on top of the unfiltered list, Spotlight-style.
            // They only render when resolvable, stale identifiers expire
            // silently (see MenuBarSearchRecents).
            let recentItems = recents.resolve(in: itemManager)
            var items = [ListItem]()
            if !recentItems.isEmpty {
                items.append(recentsHeaderRow)
                items += recentItems.map { item in
                    ListItem(
                        content: .item(item),
                        id: .item(item.tag, windowID: item.windowID),
                        isSelectable: true,
                        action: { performAction(for: item) }
                    )
                }
            }
            model.displayedItems = items + rows.map(\.listItem)
            return
        }

        let candidates = rows.filter(\.listItem.isSelectable)
        // Weighted fuzzy match; the ranker settles the ordering.
        let matches = model.fuse.searchSync(model.searchText, in: candidates, by: \.properties)
        let scored = matches.map { (item: candidates[$0.index], diffScore: $0.diffScore) }
        model.displayedItems = SearchRanker.sortedByRelevance(scored).map(\.listItem)
    }

    /// One section's slice of the search list: its header row followed by
    /// its items in reverse cache order. Empty when the scope or the
    /// section's own toggle excludes it.
    private func sectionRows(for name: MenuBarSection.Name, in scope: SearchScope) -> [RankableRow] {
        guard scope.includes(name) else {
            return []
        }
        if let section = appState.menuBarManager.section(withName: name), !section.isEnabled {
            return []
        }

        var rows = [
            RankableRow(
                listItem: ListItem(content: .header(name), id: .header(name), isSelectable: false, action: nil),
                title: name.displayString
            ),
        ]
        for item in itemManager.managedItems(for: name).reversed() where !item.isControlItem {
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

    /// Rebuilds the ranked launchers' rows: what you last opened until you
    /// type, then the ranked matches, unless recentsOnlyWhenEmpty is
    /// false, which is the assisted face's policy: the whole inventory in
    /// menu bar order, with recents on top when there are any.
    ///
    /// The standard launcher assumes a user who can see the bar, so the empty
    /// field stays quiet. For the assisted face reading the bar is the hard
    /// part, so reading the list is the interaction and typing the
    /// accelerator.
    private func rebuildRankedRows(recentsOnlyWhenEmpty: Bool) {
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        let inventory = launcherInventory()

        guard !query.isEmpty else {
            // A launcher opens on recents unless the presentation lists the
            // full inventory.
            //
            // Recents are matched back against the inventory rather than
            // rebuilt, so they carry the owning-app name without a second
            // lookup. Recents the launcher cannot open (spacers, control
            // items) are not in the inventory and drop out here.
            let byIdentity = Dictionary(
                inventory.map { ($0.identityKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let recentCandidates = recents.resolve(in: itemManager).compactMap { byIdentity[$0.uniqueIdentifier] }
            let recentRows = recentCandidates.isEmpty
                ? []
                : [recentsHeaderRow] + candidateRows(for: recentCandidates)
            model.displayedItems = recentsOnlyWhenEmpty
                ? recentRows
                : recentRows + candidateRows(for: inventory)
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
    private func launcherInventory() -> [PaletteCandidate] {
        if model.launcherCandidates.isEmpty {
            model.launcherCandidates = PaletteCandidate.inventory(from: itemManager)
        }
        return model.launcherCandidates
    }

    private var recentsHeaderRow: ListItem {
        ListItem(
            content: .label(String(localized: "Recent")),
            id: .recentsHeader,
            isSelectable: false,
            action: nil
        )
    }

    private func candidateRows(for candidates: [PaletteCandidate]) -> [ListItem] {
        candidates.map { candidate in
            let item = candidate.item
            let content: MenuBarSearchListContent = switch presentation {
            case .assisted:
                .assistedItem(item, ownerName: candidate.subtitle)
            default:
                .launcherItem(item, ownerName: candidate.subtitle)
            }
            return ListItem(
                content: content,
                id: .item(item.tag, windowID: item.windowID),
                isSelectable: true,
                action: { performAction(for: item) }
            )
        }
    }

    // MARK: Activation

    /// Whether item is where the user can already see it, which is what
    /// separates "Click Item" from "Show Item".
    ///
    /// Mirrors the dispatch in MenuBarItemManager.clickConcealedItem(item:with:on:)
    /// so the label describes what Return will actually do. A window-server
    /// on-screen check cannot answer this: macOS 27 status items carry
    /// synthetic window IDs that are never in the on-screen list.
    private func isEffectivelyVisible(_ item: MenuBarItem) -> Bool {
        let controller = appState.menuBarManager.sectionController
        guard controller.section(for: item) == .visible else {
            return false
        }
        // A visible-authored item can still be concealed by the automatic
        // overflow assertion, which the menu bar overlay also drives.
        return !controller.effectivelyConcealedIdentifiers.contains(
            MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
        )
    }

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

// MARK: - Bottom bar pieces

/// A bottom bar action labeled with the key combination that also
/// triggers it.
private struct ShortcutHintButton<Hint: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let hint: () -> Hint

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .padding(.leading, 5)
                hint()
            }
        }
    }
}

/// An empty AppKit view behind the actions button, there so the panel has
/// something to position the actions menu against.
///
/// SwiftUI frames would need converting twice (hosting view, then screen) to
/// reach NSMenu.popUp, and each step can misplace the menu. Handing over the
/// view itself avoids coordinate conversion.
private struct ItemActionsMenuAnchor: NSViewRepresentable {
    let panel: MenuBarSearchPanel

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        panel.itemActionsAnchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // Re-registered rather than set once: the bottom bar rebuilds this
        // subtree whenever the selection comes and goes, and the panel would
        // otherwise keep a reference to a view that is no longer on screen.
        panel.itemActionsAnchor = nsView
    }
}

/// Compact, uniformly sized styling shared by every bottom bar button.
private struct SearchPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 22)
            .frame(minWidth: 22)
            .padding(3)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
