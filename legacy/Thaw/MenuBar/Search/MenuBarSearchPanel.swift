//
//  MenuBarSearchPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Ifrit
import SwiftUI

extension EnvironmentValues {
    @Entry var menuBarSearchPanel: MenuBarSearchPanel?
}

/// A panel that contains the menu bar search interface.
final class MenuBarSearchPanel: NSPanel {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarSearchPanel")

    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    /// Model for menu bar item search.
    private let model = MenuBarSearchModel()

    /// Monitor for mouse down events.
    private lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            event.window !== self
        else {
            return event
        }
        if !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)) {
            close()
        }
        return event
    }

    /// Monitor for key down events.
    private lazy var keyDownMonitor = EventMonitor.universal(
        for: [.keyDown]
    ) { [weak self, weak appState] event in
        let keyCode = KeyCode(rawValue: Int(event.keyCode))
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)

        if keyCode == .comma, modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option), !modifiers.contains(.shift) {
            self?.close()
            appState?.activate(withPolicy: .regular)
            appState?.openWindow(.settings)
            return nil
        }

        if keyCode == .e, modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option), !modifiers.contains(.shift) {
            self?.startEditingSelectedItem()
            return nil
        }

        return event
    }

    @MainActor
    func startEditingSelectedItem() {
        guard let selection = model.selection, case let .item(tag, windowID) = selection,
              let item = menuBarItem(for: selection)
        else {
            return
        }
        model.editingName = item.customName ?? ""
        model.editingItemTag = tag
        model.editingItemWindowID = windowID
    }

    func menuBarItem(for selection: MenuBarSearchModel.ItemID)
        -> MenuBarItem?
    {
        switch selection {
        case let .item(tag, windowID):
            if let windowID {
                return appState?.itemManager.itemCache.managedItems.first(where: { $0.windowID == windowID })
            }
            return appState?.itemManager.itemCache.managedItems.first(matching: tag)
        case .header:
            return nil
        }
    }

    @MainActor
    func saveEditingName() {
        guard let tag = model.editingItemTag else {
            return
        }
        Self.diagLog.debug("Saving editing name for tag: \(tag)")
        defer {
            model.editingItemTag = nil
            model.editingItemWindowID = nil
            model.editingName = ""
        }
        let item = if let windowID = model.editingItemWindowID {
            appState?.itemManager.itemCache.managedItems.first(where: { $0.windowID == windowID })
        } else {
            appState?.itemManager.itemCache.managedItems.first(matching: tag)
        }

        guard let item else {
            Self.diagLog.error("Cannot save editing name, no matching item")
            return
        }
        let uniqueIdentifier = item.uniqueIdentifier
        var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        let newName = model.editingName.trimmingCharacters(in: .whitespaces)
        if newName.isEmpty {
            names.removeValue(forKey: uniqueIdentifier)
        } else {
            names[uniqueIdentifier] = newName
        }
        Defaults.set(names, forKey: .menuBarItemCustomNames)
        // Renaming is the only thing that changes a name while the panel is open.
        ItemNameCache.clear()
        // Rows read names from `Defaults`, which Observation doesn't track.
        // Writing `displayedItems` back unchanged still fires `withMutation`,
        // so rows re-render. The local keeps it from reading as `x = x`.
        let itemsToRerender = model.displayedItems
        model.displayedItems = itemsToRerender
    }

    /// The default screen to show the panel on.
    var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool {
        true
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .titled, .fullSizeContentView, .nonactivatingPanel,
                .utilityWindow,
            ],
            backing: .buffered,
            defer: false
        )
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [
            .fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace,
        ]
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        // Close when the panel loses key focus.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        // Frames are saved per display manually, not via setFrameAutosaveName.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Called when the panel loses key focus.
    @objc private func panelResignedKey(_: Notification) {
        close()
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        model.performSetup(with: self)
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if let screen = self.screen {
                    self.saveFrameForDisplay(screen)
                }
            }
            .store(in: &c)

        // Close the panel when the active space changes, or when the screen parameters change.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.activeSpaceDidChangeNotification
            ),
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        )
        .sink { [weak self] _ in
            self?.close()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Shows the search panel on the given screen.
    func show(on screen: NSScreen? = nil) {
        guard let appState else {
            return
        }

        guard let screen = screen ?? defaultScreen else {
            Self.diagLog.error("Missing screen for search panel")
            return
        }

        // Must be set before updating the cache.
        appState.navigationState.isSearchPresented = true

        let hostingView = MenuBarSearchHostingView(
            appState: appState,
            model: model,
            displayID: screen.displayID,
            panel: self
        )
        hostingView.setFrameSize(hostingView.intrinsicContentSize)

        if let savedFrame = loadFrameForDisplay(screen) {
            let visibleFrame = screen.visibleFrame
            let absoluteFrame = CGRect(
                x: savedFrame.origin.x + visibleFrame.minX,
                y: savedFrame.origin.y + visibleFrame.minY,
                width: hostingView.intrinsicContentSize.width,
                height: hostingView.intrinsicContentSize.height
            )

            let adjustedFrame = CGRect(
                x: max(visibleFrame.minX, min(absoluteFrame.origin.x, visibleFrame.maxX - hostingView.intrinsicContentSize.width)),
                y: max(visibleFrame.minY, min(absoluteFrame.origin.y, visibleFrame.maxY - hostingView.intrinsicContentSize.height)),
                width: hostingView.intrinsicContentSize.width,
                height: hostingView.intrinsicContentSize.height
            )

            setFrame(adjustedFrame, display: false)
        } else {
            let centered = CGPoint(
                x: screen.visibleFrame.midX - hostingView.intrinsicContentSize.width / 2,
                y: screen.visibleFrame.midY - hostingView.intrinsicContentSize.height / 2
            )

            setFrame(CGRect(origin: centered, size: hostingView.intrinsicContentSize), display: false)
        }

        contentView = hostingView
        contentView?.layer?.cornerRadius = 16
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.masksToBounds = true
        makeKeyAndOrderFront(nil)

        mouseDownMonitor.start()
        keyDownMonitor.start()

        // Rehide runs before the recache. Cancelled in close() so it doesn't
        // hold appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState] in
            guard let appState else { return }
            await appState.itemManager.rehideTemporarilyShownItems(force: true)
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.updateCache()
            appState.imageCache.logCacheStatus("Search panel opened")
        }
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    /// Dismisses the search panel.
    @MainActor
    override func close() {
        if isVisible, let screen, contentView != nil {
            saveFrameForDisplay(screen)
        }
        cacheTask?.cancel()
        cacheTask = nil
        if !Defaults.bool(forKey: .rememberSearchQuery) {
            model.searchText = ""
        }
        model.editingItemTag = nil
        MenuBarItemIconFallback.forgetIconsForExitedApplications()
        ItemNameCache.clear()
        super.close()
        contentView = nil
        mouseDownMonitor.stop()
        keyDownMonitor.stop()
        appState?.navigationState.isSearchPresented = false
    }

    override func cancelOperation(_: Any?) {
        if model.editingItemTag != nil {
            cancelEditing()
        } else if model.searchText != "", !Defaults.bool(forKey: .rememberSearchQuery) {
            model.searchText = ""
        } else {
            close()
        }
    }

    @MainActor
    func cancelEditing() {
        model.editingItemTag = nil
        model.editingItemWindowID = nil
        model.editingName = ""
    }

    private func saveFrameForDisplay(_ screen: NSScreen) {
        guard isVisible, contentView != nil else {
            return
        }

        let currentFrame = frame
        let actualScreen = NSScreen.screens.first { $0.visibleFrame.intersects(currentFrame) } ?? screen

        guard let uuidString = Bridging.getDisplayUUIDString(for: actualScreen.displayID) else {
            return
        }

        // Saved relative to the display's visible frame.
        let visibleFrame = actualScreen.visibleFrame
        let relativeFrame = CGRect(
            x: currentFrame.minX - visibleFrame.minX,
            y: currentFrame.minY - visibleFrame.minY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        let keyString = "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"
        Defaults.store.set(relativeFrame.dictionaryRepresentation as NSDictionary, forKey: keyString)
        Defaults.store.synchronize()
    }

    private func loadFrameForDisplay(_ screen: NSScreen) -> CGRect? {
        guard let uuidString = Bridging.getDisplayUUIDString(for: screen.displayID) else {
            return nil
        }
        let keyString = "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"

        guard let frameDict = Defaults.store.dictionary(forKey: keyString) else {
            return nil
        }

        guard let savedFrame = CGRect(dictionaryRepresentation: frameDict as CFDictionary) else {
            return nil
        }
        return savedFrame
    }
}

private final class MenuBarSearchHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        model: MenuBarSearchModel,
        displayID: CGDirectDisplayID,
        panel: MenuBarSearchPanel
    ) {
        super.init(
            rootView: AnyView(
                MenuBarSearchContentView(model: model, displayID: displayID, panel: panel) { [weak panel] in
                    panel?.close()
                }
                .environment(appState)
                .environment(appState.itemManager)
                .environment(appState.imageCache)
            )
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }
}

private struct MenuBarSearchContentView: View {
    private typealias ListItem = SectionedListItem<MenuBarSearchModel.ItemID>

    @Environment(AppState.self) var appState: AppState
    @Environment(MenuBarItemManager.self) var itemManager: MenuBarItemManager
    @Environment(MenuBarItemImageCache.self) var imageCache: MenuBarItemImageCache
    // Held as `@Bindable` rather than from `@Environment` so computed
    // properties outside `body` can use `$model` bindings.
    @Bindable var model: MenuBarSearchModel
    @FocusState private var searchFieldIsFocused: Bool
    @AppStorage(Defaults.Key.rememberSearchQuery.rawValue) private var rememberSearchQuery = Defaults.DefaultValue.rememberSearchQuery

    let displayID: CGDirectDisplayID
    let panel: MenuBarSearchPanel
    let closePanel: () -> Void

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    private var bottomBarPadding: CGFloat {
        7
    }

    private var bottomBarHorizontalPadding: CGFloat {
        4
    }

    var body: some View {
        mainContent
            .safeAreaBar(edge: .top, spacing: 0) {
                searchField
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .scrollEdgeEffectStyle(.automatic, for: .vertical)
            .environment(\.menuBarSearchPanel, panel)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
            .frame(width: 600, height: 400)
            .fixedSize()
            .onAppear {
                // Set now and again after an async hop, for the turn where the
                // hosting view is still being installed. A delay drops a fast
                // typist's first keystroke with an error sound (#969).
                searchFieldIsFocused = true
                DispatchQueue.main.async { searchFieldIsFocused = true }
            }
            .onChange(of: model.searchText, initial: true) {
                updateDisplayedItems()
                selectFirstDisplayedItem()
            }
            .onChange(of: itemManager.itemCache, initial: true) {
                // A new cache can name an item whose source process resolved
                // late, so the memo must be cleared.
                ItemNameCache.clear()
                updateDisplayedItems()
                if model.selection == nil {
                    selectFirstDisplayedItem()
                }
            }
            .onChange(of: appState.settings.advanced.searchSectionOrder) {
                updateDisplayedItems()
                ensureValidSelection()
            }
            .onChange(of: appState.settings.advanced.searchIncludeVisible) {
                updateDisplayedItems()
                ensureValidSelection()
            }
            .onChange(of: appState.settings.advanced.searchIncludeHidden) {
                updateDisplayedItems()
                ensureValidSelection()
            }
            .onChange(of: appState.settings.advanced.searchIncludeAlwaysHidden) {
                updateDisplayedItems()
                ensureValidSelection()
            }
    }

    @ViewBuilder
    private var searchField: some View {
        let promptText = Text("Search menu bar items…")

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                TextField(text: $model.searchText, prompt: promptText) {
                    promptText
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .textContentType(.none)
                .autocorrectionDisabled(true)
                .focused($searchFieldIsFocused)

                Spacer()
            }
            .padding(15)

            Divider()
                .padding(.horizontal, 15)
        }
    }

    private func openPermissionsSettings() {
        closePanel()
        appState.navigationState.settingsNavigationIdentifier = .advanced
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    @ViewBuilder
    private var mainContent: some View {
        // No Screen Recording branch: search matches names, and `itemView`
        // omits the glyph preview when there's no capture.
        if hasItems {
            SectionedList(
                selection: $model.selection,
                items: $model.displayedItems,
                isEditing: model.editingItemTag != nil
            )
            .contentPadding(8)
            .scrollContentBackground(.hidden)
        } else {
            VStack {
                Text("Loading menu bar items…")
                    .font(.title2)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack {
            SettingsButton {
                closePanel()
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            }

            Toggle("Keep search", isOn: $rememberSearchQuery)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Spacer()

            if let selection = model.selection, let item = panel.menuBarItem(for: selection) {
                if model.editingItemTag == nil {
                    EditNameButton {
                        panel.startEditingSelectedItem()
                    }
                    ShowItemButton(item: item) {
                        performAction(for: item)
                    }
                } else {
                    EditDiscardButton {
                        panel.cancelEditing()
                    }
                    EditConfirmButton {
                        panel.saveEditingName()
                    }
                }
            }
        }
        .padding(bottomBarPadding)
        .padding(.horizontal, bottomBarHorizontalPadding)
        .buttonStyle(BottomBarButtonStyle())
    }

    private func selectFirstDisplayedItem() {
        guard !model.displayedItems.isEmpty else {
            model.selection = nil
            return
        }
        model.selection = model.displayedItems.first { $0.isSelectable }?.id
    }

    /// Re-selects the first item when the current selection has been
    /// filtered out of `displayedItems` (or was never set).
    private func ensureValidSelection() {
        guard let selection = model.selection else {
            selectFirstDisplayedItem()
            return
        }
        if !model.displayedItems.contains(where: { $0.id == selection }) {
            selectFirstDisplayedItem()
        }
    }

    private func updateDisplayedItems() {
        struct SearchItem: Searchable {
            let listItem: ListItem
            let title: String

            var properties: [FuseProp] {
                [FuseProp(title)]
            }
        }
        typealias ScoredItem = (listItem: ListItem, score: Double)

        let advanced = appState.settings.advanced
        let orderedNames = advanced.searchSectionOrder

        let searchItems: [SearchItem] = orderedNames
            .reduce(into: []) { items, name in
                let included = switch name {
                case .visible: advanced.searchIncludeVisible
                case .hidden: advanced.searchIncludeHidden
                case .alwaysHidden: advanced.searchIncludeAlwaysHidden
                }
                guard included else { return }

                if
                    let section = appState.menuBarManager.section(
                        withName: name
                    ),
                    !section.isEnabled
                {
                    return
                }

                let headerItem = ListItem.header(id: .header(name)) {
                    Text(name.localized)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.leading, 6)
                }
                items.append(SearchItem(listItem: headerItem, title: name.displayString))

                for item in itemManager.itemCache.managedItems(for: name)
                    .reversed()
                {
                    guard !item.isControlItem else {
                        continue
                    }
                    let listItem = ListItem.item(id: .item(item.tag, windowID: item.windowID)) {
                        performAction(for: item)
                    } content: {
                        MenuBarSearchItemView(model: model, item: item)
                    }
                    items.append(SearchItem(listItem: listItem, title: ItemNameCache.displayName(for: item)))
                }
            }

        if model.searchText.isEmpty {
            model.displayedItems = searchItems.map(\.listItem)
        } else {
            let selectableItems = searchItems.filter(\.listItem.isSelectable)
            let fuseResults = model.fuse.searchSync(model.searchText, in: selectableItems, by: \.properties)

            model.displayedItems = fuseResults
                .map { result in
                    let item = selectableItems[result.index]
                    let score = 1.0 - result.diffScore
                    return ScoredItem(item.listItem, score)
                }
                .sorted { (lhs: ScoredItem, rhs: ScoredItem) -> Bool in
                    lhs.score > rhs.score
                }
                .map(\.listItem)
        }
    }

    private func performAction(for item: MenuBarItem) {
        if model.editingItemTag == item.tag, model.editingItemWindowID == item.windowID {
            return
        }
        closePanel()
        Task {
            // Act only once the panel has fully closed.
            await panel.waitUntilClosed(timeout: .milliseconds(200))
            await itemManager.activate(item: item, on: displayID)
            if appState.settings.advanced.moveCursorToRevealedItem {
                moveCursor(to: item)
            }
        }
    }

    /// Moves the pointer onto `item` once it has been revealed, so that the
    /// menu it opened sits under the pointer.
    private func moveCursor(to item: MenuBarItem) {
        // The cached bounds predate the reveal, so read the live window
        // bounds to find where the item actually ended up.
        let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        guard
            let point = MouseHelpers.cursorPoint(
                overItemWithBounds: bounds,
                displayBounds: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            )
        else {
            return
        }
        MouseHelpers.warpCursor(to: point)
    }
}

private struct EditNameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(String(localized: "Edit Name"))
                    .padding(.leading, 5)

                HStack(spacing: 0) {
                    Text(verbatim: "⌘")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(.secondary)

                Text(verbatim: "+")

                HStack(spacing: 0) {
                    Text(verbatim: "E")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EditConfirmButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(
                    String(localized: "Confirm")
                )
                .padding(.leading, 5)

                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                    .bold()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
}

private struct EditDiscardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(
                    String(localized: "Discard")
                )
                .padding(.leading, 5)

                Text(verbatim: "⎋")
                    .font(.system(size: 12))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(.iceCubeStroke)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .padding(2)
        }
    }
}

private struct ShowItemButton: View {
    let item: MenuBarItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(
                    Bridging.isWindowOnScreen(item.windowID)
                        ? String(localized: "Click Item")
                        : String(localized: "Show Item")
                )
                .padding(.leading, 5)

                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                    .bold()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 22)
            .frame(minWidth: 22)
            .padding(3)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

/// Memoizes item display names for the search rows.
///
/// `MenuBarItem.displayName` reads defaults, Launch Services, and regexes,
/// and search asks for it per item and per row on every keystroke.
///
/// Cleared when the panel closes and when a name is edited.
@MainActor
private enum ItemNameCache {
    private static var names = [MenuBarItemTag: String]()

    static func displayName(for item: MenuBarItem) -> String {
        if let cached = names[item.tag] {
            return cached
        }
        let name = item.displayName
        names[item.tag] = name
        return name
    }

    static func clear() {
        names.removeAll()
    }
}

private struct MenuBarSearchItemView: View {
    @Environment(\.menuBarSearchPanel) var panel
    @Environment(AppState.self) var appState: AppState
    @Environment(MenuBarItemImageCache.self) var imageCache: MenuBarItemImageCache
    @Bindable var model: MenuBarSearchModel

    let item: MenuBarItem
    @FocusState private var isEditing: Bool

    /// The captured glyph, or `nil` when there is none to draw.
    private var itemImage: NSImage? {
        let captured = imageCache.trimmedImage(for: item.tag)
        // When icons are preferred, the trailing preview would repeat the
        // leading app icon.
        if MenuBarItemIconFallback.shouldUseAppIcon(
            for: item,
            hasCapture: captured != nil,
            prefersAppIcon: appState.settings.advanced.alwaysUseAppIconForMenuBarItems
        ) {
            return nil
        }
        return captured
    }

    private var appIcon: NSImage? {
        MenuBarItemIconFallback.appIcon(for: item)
    }

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    private var dimension: CGFloat {
        26
    }

    private var padding: CGFloat {
        6
    }

    var body: some View {
        HStack {
            if model.editingItemTag == item.tag, model.editingItemWindowID == item.windowID {
                HStack(spacing: 8) {
                    labelIcon
                    TextField(item.autoDetectedName, text: $model.editingName)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .focused($isEditing)
                        .textContentType(.none)
                        .autocorrectionDisabled(true)
                        .onSubmit {
                            panel?.saveEditingName()
                        }
                        .onExitCommand {
                            model.editingItemTag = nil
                            model.editingItemWindowID = nil
                            model.editingName = ""
                        }
                        .onAppear {
                            isEditing = true
                        }
                        .onDisappear {
                            isEditing = false
                        }
                }
            } else {
                Label {
                    labelText
                } icon: {
                    labelIcon
                }
            }
            Spacer()
            itemView
        }
        .padding(padding)
    }

    private var labelText: some View {
        Text(ItemNameCache.displayName(for: item))
    }

    @ViewBuilder
    private var labelIcon: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: dimension, height: dimension)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.gradient)
                .strokeBorder(Color.primary.gradient.quaternary)
                .overlay {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .padding(3)
                        .shadow(radius: 2)
                }
                .padding(2.5)
                .shadow(color: .black.opacity(0.1), radius: 2)
                .frame(width: dimension, height: dimension)
        }
    }

    @ViewBuilder
    private var itemView: some View {
        if let itemImage {
            Image(nsImage: itemImage)
                .frame(
                    width: item.bounds.width,
                    height: dimension
                )
                .menuBarItemContainer(
                    appState: appState,
                    colorInfo: model.averageColorInfo
                )
                .clipShape(backgroundShape)
                .overlay {
                    backgroundShape
                        .strokeBorder(.quaternary)
                }
        }
    }
}
