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

private struct MenuBarSearchPanelKey: EnvironmentKey {
    static let defaultValue: MenuBarSearchPanel? = nil
}

extension EnvironmentValues {
    var menuBarSearchPanel: MenuBarSearchPanel? {
        get { self[MenuBarSearchPanelKey.self] }
        set { self[MenuBarSearchPanelKey.self] = newValue }
    }
}

/// A panel that contains the menu bar search interface.
final class MenuBarSearchPanel: NSPanel {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarSearchPanel")

    /// The shared app state.
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
            if let windowID = windowID {
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

        guard let item = item else {
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
        model.objectWillChange.send()
    }

    /// The default screen to show the panel on.
    var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool {
        true
    }

    /// Creates a menu bar search panel with Liquid Glass effect.
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
        // Liquid Glass: transparent window with shadow
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        // Close panel when it loses key focus (e.g., another app gets focus)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        // setFrameAutosaveName("MenuBarSearchPanel") // Manual persistence is used instead.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Called when the panel loses key focus.
    @objc private func panelResignedKey(_: Notification) {
        close()
    }

    /// Performs the initial setup of the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        model.performSetup(with: self)
    }

    /// Configures the internal observers for the panel.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        // Save the frame when the application terminates.
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
            // Force close and clear any cached screen references on hot-plug
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

        // Important that we set the navigation state before updating the cache.
        appState.navigationState.isSearchPresented = true

        let hostingView = MenuBarSearchHostingView(
            appState: appState,
            model: model,
            displayID: screen.displayID,
            panel: self
        )
        hostingView.setFrameSize(hostingView.intrinsicContentSize)

        // Try to load saved frame for current display
        if let savedFrame = loadFrameForDisplay(screen) {
            // Convert relative position back to absolute coordinates
            let visibleFrame = screen.visibleFrame
            let absoluteFrame = CGRect(
                x: savedFrame.origin.x + visibleFrame.minX,
                y: savedFrame.origin.y + visibleFrame.minY,
                width: hostingView.intrinsicContentSize.width,
                height: hostingView.intrinsicContentSize.height
            )

            // Ensure frame is within this display's visible frame
            let adjustedFrame = CGRect(
                x: max(visibleFrame.minX, min(absoluteFrame.origin.x, visibleFrame.maxX - hostingView.intrinsicContentSize.width)),
                y: max(visibleFrame.minY, min(absoluteFrame.origin.y, visibleFrame.maxY - hostingView.intrinsicContentSize.height)),
                width: hostingView.intrinsicContentSize.width,
                height: hostingView.intrinsicContentSize.height
            )

            setFrame(adjustedFrame, display: false)
        } else {
            // No saved frame for this display, center on screen
            let centered = CGPoint(
                x: screen.visibleFrame.midX - hostingView.intrinsicContentSize.width / 2,
                y: screen.visibleFrame.midY - hostingView.intrinsicContentSize.height / 2
            )

            setFrame(CGRect(origin: centered, size: hostingView.intrinsicContentSize), display: false)
        }

        contentView = hostingView
        // Match window corner radius and curve to glass effect (.continuous)
        contentView?.layer?.cornerRadius = 16
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.masksToBounds = true
        makeKeyAndOrderFront(nil)

        mouseDownMonitor.start()
        keyDownMonitor.start()

        // Rehide temporarily shown items and refresh caches in the
        // background. Ordering is preserved: rehide moves items back
        // to their correct sections before the cache is rebuilt.
        // The task is cancelled in close() to avoid holding appState.
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

    /// Toggles the panel's visibility.
    func toggle() {
        if isVisible { close() } else { show() }
    }

    /// Dismisses the search panel.
    @MainActor
    override func close() {
        // Only save if window is actually visible and has content
        if isVisible, let screen = screen, contentView != nil {
            saveFrameForDisplay(screen)
        }
        cacheTask?.cancel()
        cacheTask = nil
        if !Defaults.bool(forKey: .rememberSearchQuery) {
            model.searchText = ""
        }
        model.editingItemTag = nil
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

    /// Saves the frame for a specific display.
    private func saveFrameForDisplay(_ screen: NSScreen) {
        // Only save if window is visible and has content
        guard isVisible, contentView != nil else {
            return
        }

        // Get current window frame and ensure we're saving from the right screen
        let currentFrame = frame
        let actualScreen = NSScreen.screens.first { $0.visibleFrame.intersects(currentFrame) } ?? screen

        guard let uuidString = Bridging.getDisplayUUIDString(for: actualScreen.displayID) else {
            return
        }

        // Save position relative to the display's visible frame for consistency
        let visibleFrame = actualScreen.visibleFrame
        let relativeFrame = CGRect(
            x: currentFrame.minX - visibleFrame.minX,
            y: currentFrame.minY - visibleFrame.minY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        let keyString = "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"
        UserDefaults.standard.set(relativeFrame.dictionaryRepresentation as NSDictionary, forKey: keyString)
        UserDefaults.standard.synchronize()
    }

    /// Loads the saved frame for a specific display.
    private func loadFrameForDisplay(_ screen: NSScreen) -> CGRect? {
        guard let uuidString = Bridging.getDisplayUUIDString(for: screen.displayID) else {
            return nil
        }
        let keyString = "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"

        guard let frameDict = UserDefaults.standard.dictionary(forKey: keyString) else {
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
                MenuBarSearchContentView(displayID: displayID, panel: panel) { [weak panel] in
                    panel?.close()
                }
                .environmentObject(appState)
                .environmentObject(appState.itemManager)
                .environmentObject(appState.imageCache)
                .environmentObject(model)
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

    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var model: MenuBarSearchModel
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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: 600, height: 400)
            .fixedSize()
            .onAppear {
                // Delay focus slightly to ensure the window is fully key
                // and the text field is ready to receive focus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    searchFieldIsFocused = true
                }
            }
            .onChange(of: model.searchText, initial: true) {
                updateDisplayedItems()
                selectFirstDisplayedItem()
            }
            .onChange(of: itemManager.itemCache, initial: true) {
                updateDisplayedItems()
                if model.selection == nil {
                    selectFirstDisplayedItem()
                }
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
                .opacity(0.7)
                .padding(.horizontal, 15)
        }
    }

    private func openPermissionsSettings() {
        closePanel()
        itemManager.appState?.navigationState.settingsNavigationIdentifier = .advanced
        itemManager.appState?.activate(withPolicy: .regular)
        itemManager.appState?.openWindow(.settings)
    }

    @ViewBuilder
    private var mainContent: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Screen recording permissions are required to search menu bar items.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    openPermissionsSettings()
                } label: {
                    Text("Open \(Constants.displayName) Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasItems {
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
                itemManager.appState?.activate(withPolicy: .regular)
                itemManager.appState?.openWindow(.settings)
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
        model.selection = model.displayedItems.first { $0.isSelectable }?.id
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

        let searchItems: [SearchItem] = MenuBarSection.Name.allCases
            .reduce(into: []) { items, name in
                if
                    let appState = itemManager.appState,
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
                        MenuBarSearchItemView(item: item)
                    }
                    items.append(SearchItem(listItem: listItem, title: item.displayName))
                }
            }

        if model.searchText.isEmpty {
            model.displayedItems = searchItems.map { $0.listItem }
        } else {
            let selectableItems = searchItems.filter {
                $0.listItem.isSelectable
            }
            // Using weighted search via FuseProp
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
                .map { $0.listItem }
        }
    }

    private func performAction(for item: MenuBarItem) {
        if model.editingItemTag == item.tag, model.editingItemWindowID == item.windowID {
            return
        }
        closePanel()
        Task {
            // Wait until the search panel is fully closed before acting on
            // the selected item. Uses KVO on isVisible so we resume as soon
            // as the panel hides rather than waiting a fixed 25 ms.
            await panel.waitUntilClosed(timeout: .milliseconds(200))
            if Bridging.isWindowOnScreen(item.windowID) {
                try await itemManager.click(item: item, with: .left)
            } else {
                // temporarilyShow handles move, click, and fallback click
                // internally so shownInterfaceWindow is always captured.
                await itemManager.temporarilyShow(
                    item: item,
                    clickingWith: .left,
                    on: displayID
                )
            }
        }
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
                    Text("⌘")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(.secondary)

                Text("+")

                HStack(spacing: 0) {
                    Text("E")
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

                Text("⎋")
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

@MainActor
private let controlCenterIcon: NSImage? = {
    guard
        let app =
        NSRunningApplication
            .runningApplications(
                withBundleIdentifier: "com.apple.controlcenter"
            )
            .first
    else {
        return nil
    }
    return app.icon
}()

private struct MenuBarSearchItemView: View {
    @Environment(\.menuBarSearchPanel) var panel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var model: MenuBarSearchModel

    let item: MenuBarItem
    @FocusState private var isEditing: Bool

    private var itemImage: NSImage {
        guard
            let cached = imageCache.images[item.tag],
            let trimmed = cached.cgImage.trimmingTransparency(around: [
                .minXEdge, .maxXEdge,
            ])
        else {
            return NSImage()
        }
        let size = CGSize(
            width: CGFloat(trimmed.width) / cached.scale,
            height: CGFloat(trimmed.height) / cached.scale
        )
        return NSImage(cgImage: trimmed, size: size)
    }

    private var appIcon: NSImage? {
        guard let app = item.sourceApplication else {
            return nil
        }
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return controlCenterIcon
        default:
            return app.icon
        }
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
        Text(item.displayName)
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

    private var itemView: some View {
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
