//
//  ControlItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Observation

// MARK: - ControlItem

/// A status item that controls a section in the menu bar.
@MainActor
final class ControlItem {
    nonisolated enum Identifier: String, CaseIterable {
        case visible = "Thaw.ControlItem.Visible"
        case hidden = "Thaw.ControlItem.Hidden"
        case alwaysHidden = "Thaw.ControlItem.AlwaysHidden"

        var tag: MenuBarItemTag {
            switch self {
            case .visible: .visibleControlItem
            case .hidden: .hiddenControlItem
            case .alwaysHidden: .alwaysHiddenControlItem
            }
        }

        /// Returns the length associated with this identifier and
        /// the given hiding state.
        func length(for state: HidingState) -> CGFloat {
            switch self {
            case .visible:
                Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .showSection: Lengths.standard
                case .hideSection: Lengths.expanded
                }
            }
        }
    }

    enum HidingState {
        case showSection
        case hideSection
    }

    private nonisolated enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10000
    }

    /// Nonzero seed length used to make AppKit materialize a WindowServer
    /// window before the intended control-item length is applied.
    static nonisolated let statusItemMaterializationLength: CGFloat = 1

    private final class StatusItemStorage {
        let statusItem: NSStatusItem
        let constraint: NSLayoutConstraint?

        /// Set once dispose() has run, so deinit doesn't remove the
        /// status item a second time.
        private var isDisposed = false

        @MainActor
        init(controlItem: ControlItem) {
            ControlItemDefaults.preflightSetup(for: controlItem.identifier)

            // A zero-length status item can stay a synthetic window with no
            // CGWindowID. One point forces a real one; updateStatusItem fixes
            // the length right after.
            self.statusItem = NSStatusBar.system.statusItem(
                withLength: ControlItem.statusItemMaterializationLength
            )
            self.statusItem.autosaveName = controlItem.identifier.rawValue

            if let button = statusItem.button {
                if let contentView = button.window?.contentView {
                    let constraints = contentView.constraintsAffectingLayout(for: .horizontal)
                    if let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button)) {
                        assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
                        self.constraint = constraint
                    } else {
                        self.constraint = nil
                    }

                    NSLayoutConstraint.activate([
                        button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                    ])
                } else {
                    self.constraint = nil
                }

                button.target = controlItem
                button.action = #selector(controlItem.performAction)
                button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            } else {
                self.constraint = nil
            }
        }

        @MainActor
        deinit {
            guard !isDisposed else {
                return
            }
            removeStatusItem()
        }

        /// Tears down the status item before a replacement is created at the
        /// same autosaveName. Left to deinit, the old item's removal would
        /// overwrite the slot with its stale position after the new item
        /// restored it.
        @MainActor
        func dispose() {
            guard !isDisposed else {
                return
            }
            isDisposed = true
            removeStatusItem()
        }

        private func removeStatusItem() {
            // Removing the status item deletes the preferred position, so
            // cache and restore it. Dividers too, or a recreate discards the
            // position preflightSetup just seeded.
            let autosaveName = statusItem.autosaveName as String
            let cached = ControlItemDefaults[.preferredPosition, autosaveName]
            NSStatusBar.system.removeStatusItem(statusItem)
            ControlItemDefaults.setIgnoringSectionDividerGuard(
                .preferredPosition,
                autosaveName,
                to: cached
            )
        }
    }

    @Published var state = HidingState.hideSection

    @Published private(set) var window: NSWindow?

    @Published private(set) var frame: CGRect?

    @Published private(set) var screen: NSScreen?

    @Published private(set) var onScreenFrame: CGRect?

    /// Whether the menu bar accepted this item but isn't rendering it,
    /// usually because macOS parked it in the notch dead zone.
    ///
    /// Derived from NSWindow.occlusionState, so it needs no Screen Recording
    /// grant. Debounced; see ControlItemOcclusion.
    @Published private(set) var isOccluded = false

    let identifier: Identifier

    private lazy var storage = StatusItemStorage(controlItem: self)

    /// Spacer items used to extend hidden/always-hidden width on ultra-wide displays.
    private var spacerItems = [NSStatusItem]()

    /// What the button's image was last built from. `NSImage` compares by
    /// identity, so the source is what tells a real change from a repeat.
    private var appliedImageSource: ImageSource?

    private struct ImageSource: Equatable {
        let image: ControlItemImage?
        let customIceIconIsTemplate: Bool
    }

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    private nonisolated let diagLog = DiagLog(category: "ControlItem")

    /// Debounces the raw occlusionState readings behind isOccluded.
    private var occlusionEvaluator = ControlItemOcclusion.Evaluator()

    /// When the displays were last reconfigured, used to discard the occlusion
    /// readings taken while the new layout is still settling.
    private var lastDisplayChange: Date?

    /// Settings are @Observable, so they're observed via Observations
    /// rather than Combine publishers.
    private var showIceIconObservationTask: Task<Void, Never>?
    private var iceIconObservationTask: Task<Void, Never>?
    private var sectionDividerStyleObservationTask: Task<Void, Never>?
    private var alwaysHiddenSectionObservationTask: Task<Void, Never>?

    private var isDraggingMenuBarItemObservationTask: Task<Void, Never>?

    deinit {
        showIceIconObservationTask?.cancel()
        iceIconObservationTask?.cancel()
        sectionDividerStyleObservationTask?.cancel()
        alwaysHiddenSectionObservationTask?.cancel()
        isDraggingMenuBarItemObservationTask?.cancel()
    }

    /// Observers bound to the current NSStatusItem. KVO publishers latch onto
    /// object identity, so these are rebuilt by recreateStatusItem().
    private var statusItemCancellables = Set<AnyCancellable>()

    private var statusItem: NSStatusItem {
        storage.statusItem
    }

    private var constraint: NSLayoutConstraint? {
        storage.constraint
    }

    /// A Boolean value that indicates whether the control item serves as
    /// a divider between sections.
    var isSectionDivider: Bool {
        identifier != .visible
    }

    /// A Boolean value that indicates whether the control item is currently
    /// displayed in the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    init(identifier: Identifier) {
        self.identifier = identifier
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        // Apply the icon preference synchronously. The status item is born
        // visible and the observers below are async, so a disabled icon
        // would otherwise show a blank slot at launch.
        if identifier == .visible {
            setIceIconDisplayed(appState.settings.general.showIceIcon)
        }
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $state
            // On macOS 26 every status item scene commit leaks Core Animation
            // fence ports, so skip same-value writes.
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &c)

        $window.removeNil()
            .map { $0.publisher(for: \.frame) }
            .switchToLatest()
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frame = frame
            }
            .store(in: &c)

        $window.removeNil()
            .map { $0.publisher(for: \.screen) }
            .switchToLatest()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.screen = screen
            }
            .store(in: &c)

        $screen.removeNil()
            .map { $0.publisher(for: \.frame) }
            .switchToLatest()
            .combineLatest($frame.removeNil())
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screenFrame, frame in
                guard let self else {
                    return
                }
                if screenFrame.intersects(frame) {
                    onScreenFrame = frame
                } else {
                    onScreenFrame = nil
                }
            }
            .store(in: &c)

        if let appState {
            isDraggingMenuBarItemObservationTask?.cancel()
            isDraggingMenuBarItemObservationTask = Task { [weak self, weak appState] in
                var previous: Bool?
                let changes = Observations { appState?.isDraggingMenuBarItem }
                for await isDragging in changes {
                    guard let self else { return }
                    guard let isDragging, isDragging != previous else { continue }
                    previous = isDragging
                    updateStatusItem()
                }
            }

            if identifier == .visible {
                let generalSettings = appState.settings.general
                showIceIconObservationTask?.cancel()
                showIceIconObservationTask = Task { [weak self] in
                    let changes = Observations { generalSettings.showIceIcon }
                    for await shouldShow in changes {
                        guard let self else { return }
                        setIceIconDisplayed(shouldShow)
                    }
                }

                iceIconObservationTask?.cancel()
                iceIconObservationTask = Task { [weak self] in
                    let changes = Observations { (generalSettings.iceIcon, generalSettings.customIceIconIsTemplate) }
                    for await _ in changes {
                        guard let self else { return }
                        updateStatusItem()
                    }
                }
            }

            if isSectionDivider {
                let advancedSettings = appState.settings.advanced
                sectionDividerStyleObservationTask?.cancel()
                sectionDividerStyleObservationTask = Task { [weak self] in
                    let changes = Observations { advancedSettings.sectionDividerStyle }
                    for await _ in changes {
                        guard let self else { return }
                        updateStatusItem()
                    }
                }
            }
        }

        cancellables = c

        configureStatusItemCancellables()
    }

    /// Configures observers bound to the current NSStatusItem. Called again
    /// after recreateStatusItem(), since KVO publishers would keep watching
    /// the detached old item.
    private func configureStatusItemCancellables() {
        var c = Set<AnyCancellable>()

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard
                    let self,
                    let menuBarManager = appState?.menuBarManager,
                    let section = menuBarManager.section(withName: sectionName),
                    let hotkey = section.hotkey
                else {
                    return
                }
                if isVisible {
                    hotkey.enable()
                } else {
                    hotkey.disable()
                }
            }
            .store(in: &c)

        statusItem.publisher(for: \.button).removeNil()
            .map { $0.publisher(for: \.window) }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.window = window
            }
            .store(in: &c)

        if identifier == .alwaysHidden, let appState {
            let advancedSettings = appState.settings.advanced
            let reactToAlwaysHiddenSectionState: () -> Void = { [weak self] in
                guard let self else { return }
                if advancedSettings.enableAlwaysHiddenSection {
                    addToMenuBar()
                } else {
                    removeFromMenuBar()
                }
            }

            // Re-derive add/remove whenever isVisible changes.
            statusItem.publisher(for: \.isVisible)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { _ in reactToAlwaysHiddenSectionState() }
                .store(in: &c)

            alwaysHiddenSectionObservationTask?.cancel()
            alwaysHiddenSectionObservationTask = Task {
                let changes = Observations { advancedSettings.enableAlwaysHiddenSection }
                for await _ in changes {
                    reactToAlwaysHiddenSectionState()
                }
            }
        }

        configureOcclusionObservers(storingIn: &c)

        statusItemCancellables = c
    }

    /// Wires up the occlusion signal behind isOccluded. Bound to the current
    /// NSStatusItem, so recreateStatusItem() re-subscribes it.
    private func configureOcclusionObservers(storingIn c: inout Set<AnyCancellable>) {
        let displayChanges = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .replace(with: ())

        // Record the reconfiguration first, so the samples that the same
        // notification triggers below are already inside the grace window.
        displayChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                lastDisplayChange = .now
                occlusionEvaluator.reset()
            }
            .store(in: &c)

        // An already-occluded window posts nothing once the layout settles,
        // so re-sample after the grace window.
        let settledAfterDisplayChange = displayChanges
            .delay(
                for: .seconds(ControlItemOcclusion.displayChangeGrace + 0.1),
                scheduler: DispatchQueue.main
            )
            .eraseToAnyPublisher()

        let occlusionChanges = NotificationCenter.default
            .publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .compactMap { $0.object as? NSWindow }
            .filter { [weak self] window in
                window === self?.window
            }
            .replace(with: ())
            .eraseToAnyPublisher()

        let visibilityChanges = statusItem.publisher(for: \.isVisible)
            .removeDuplicates()
            .replace(with: ())
            .eraseToAnyPublisher()

        Publishers.MergeMany(occlusionChanges, visibilityChanges, settledAfterDisplayChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.sampleOcclusion()
            }
            .store(in: &c)
    }

    /// Takes one occlusion reading and publishes the verdict if it changed.
    private func sampleOcclusion() {
        guard let window else {
            // No window to read. Leave the last verdict alone unless it
            // claimed occlusion, which can no longer be substantiated.
            occlusionEvaluator.reset()
            if isOccluded {
                isOccluded = false
            }
            return
        }

        let sample = ControlItemOcclusion.Sample(
            isOccluded: !window.occlusionState.contains(.visible),
            isInMenuBar: statusItem.isVisible,
            secondsSinceDisplayChange: lastDisplayChange
                .map { Date.now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        )

        guard let verdict = occlusionEvaluator.evaluate(sample) else {
            return
        }

        isOccluded = verdict
        if verdict {
            diagLog.warning(
                "\(identifier.rawValue) is occluded — the menu bar accepted the status item but is not rendering it"
            )
        } else {
            diagLog.notice("\(identifier.rawValue) is no longer occluded")
        }
    }

    /// Rebuilds the underlying NSStatusItem from scratch.
    ///
    /// Recovery for when ControlItemPair lookup keeps failing because the
    /// windowNumber matches no CG window ID (#754), or when a collapsed
    /// divider must discard its stale position.
    ///
    /// The old item must be disposed before the new one is created, or its
    /// deferred removal overwrites the shared autosave slot with a stale
    /// position.
    @MainActor
    func recreateStatusItem(preferredPosition: CGFloat? = nil) {
        storage.dispose()
        if let preferredPosition {
            ControlItemDefaults.setIgnoringSectionDividerGuard(
                .preferredPosition,
                identifier.rawValue,
                to: preferredPosition
            )
        }
        storage = StatusItemStorage(controlItem: self)
        appliedImageSource = nil
        configureStatusItemCancellables()
        updateStatusItem()
    }

    /// Updates the appearance of the status item using the current hiding state.
    ///
    /// Writes only values that changed: on macOS 26 every status item write
    /// leaks Core Animation fence ports inside AppKit.
    private func updateStatusItem() {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        let customIceIconIsTemplate = appState.settings.general.customIceIconIsTemplate
        setIfChanged(button, \.font, NSFont.boldSystemFont(ofSize: NSFont.systemFontSize))

        switch identifier {
        case .visible:
            if !appState.settings.general.showIceIcon {
                setIfChanged(button, \.title, "")
                setImage(nil, customIceIconIsTemplate: customIceIconIsTemplate, on: button)
                hideIceIconCompletely()
                return
            }
            updateStatusItemVisibility(true)
            setIfChanged(button, \.appearsDisabled, false)
            setIfChanged(button, \.title, "")

            let icon = appState.settings.general.iceIcon
            let image = switch state {
            case .showSection: icon.visible
            case .hideSection: icon.hidden
            }
            setImage(
                image,
                customIceIconIsTemplate: customIceIconIsTemplate,
                on: button
            ) { built in
                guard case .custom = icon.name else {
                    return built
                }
                let originalWidth = built.size.width
                let originalHeight = built.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                return built.resized(to: newSize)
            }
        case .hidden, .alwaysHidden:
            switch state {
            case .showSection:
                setIfChanged(button, \.isEnabled, true)
                setIfChanged(button, \.alphaValue, 1)
                switch appState.settings.advanced.sectionDividerStyle {
                case .noDivider:
                    updateStatusItemVisibility(false)
                    setIfChanged(button, \.appearsDisabled, true)
                    setIfChanged(button, \.isHighlighted, false)
                    setImage(nil, customIceIconIsTemplate: customIceIconIsTemplate, on: button)

                    // We still want a subtle marker between sections.
                    let showsMarker = appState.isDraggingMenuBarItem
                        && appState.settings.advanced.showAllSectionsOnUserDrag
                    setIfChanged(button, \.title, showsMarker ? "|" : "")
                case .chevron:
                    updateStatusItemVisibility(true)
                    setIfChanged(button, \.appearsDisabled, false)
                    setIfChanged(button, \.title, "")
                    setImage(
                        .builtin(.chevronSmall),
                        customIceIconIsTemplate: customIceIconIsTemplate,
                        on: button
                    )
                }
            case .hideSection:
                updateStatusItemVisibility(true)
                setIfChanged(button, \.appearsDisabled, true)
                setIfChanged(button, \.isHighlighted, false)
                setIfChanged(button, \.title, "")
                setImage(nil, customIceIconIsTemplate: customIceIconIsTemplate, on: button)
                // The constraint stays active so items are pushed off-screen.
                setIfChanged(button, \.isEnabled, false)
                setIfChanged(button, \.alphaValue, 0)
            }
        }
    }

    /// See ``updateStatusItem()`` for why repeated writes matter.
    private func setIfChanged<Root: AnyObject, Value: Equatable>(
        _ object: Root,
        _ keyPath: ReferenceWritableKeyPath<Root, Value>,
        _ value: Value
    ) {
        if object[keyPath: keyPath] != value {
            object[keyPath: keyPath] = value
        }
    }

    /// Sets the button's image, building it only when its source changed.
    private func setImage(
        _ image: ControlItemImage?,
        customIceIconIsTemplate: Bool,
        on button: NSStatusBarButton,
        adjust: (NSImage) -> NSImage? = { $0 }
    ) {
        let source = ImageSource(image: image, customIceIconIsTemplate: customIceIconIsTemplate)
        guard source != appliedImageSource else {
            return
        }
        appliedImageSource = source
        button.image = image?
            .nsImage(customIceIconIsTemplate: customIceIconIsTemplate)
            .flatMap(adjust)
    }

    /// Updates the visibility of the status item.
    ///
    /// The hidden and always-hidden items must stay in the menu bar, since
    /// their positions define the sections, and isVisible = false removes
    /// them. So this toggles the width constraint and length instead.
    private func updateStatusItemVisibility(_ isVisible: Bool) {
        guard let appState else {
            return
        }

        if isVisible {
            if let constraint {
                setIfChanged(constraint, \.isActive, true)
            }
            setIfChanged(statusItem, \.length, identifier.length(for: state))

            let shouldUseSpacers = (identifier == .hidden || identifier == .alwaysHidden) && state == .hideSection
            updateSpacerItems(forHiddenState: shouldUseSpacers)
        } else {
            updateSpacerItems(forHiddenState: false)
            let showOnDrag = appState.settings.advanced.showAllSectionsOnUserDrag
            let isDragging = appState.isDraggingMenuBarItem

            let shouldShow = showOnDrag && isDragging

            if let constraint {
                setIfChanged(constraint, \.isActive, false)
            }
            setIfChanged(statusItem, \.length, shouldShow ? 3 : 0)
            setWindowWidthIfChanged(shouldShow ? 3 : 1)
        }
    }

    private func setWindowWidthIfChanged(_ width: CGFloat) {
        guard let window, window.frame.width != width else {
            return
        }
        let size = withMutableCopy(of: window.frame.size) { $0.width = width }
        window.setContentSize(size)
    }

    /// Adds or removes spacer items to extend the hidden/always-hidden section width.
    private func updateSpacerItems(forHiddenState isHiddenState: Bool) {
        guard identifier != .visible else {
            removeSpacerItems()
            return
        }

        guard isHiddenState else {
            removeSpacerItems()
            return
        }

        let needed = requiredSpacerCount()

        if spacerItems.count != needed {
            removeSpacerItems()

            spacerItems = (0 ..< needed).map { index in
                // One point forces a real window with a CGWindowID, as in
                // StatusItemStorage.
                let item = NSStatusBar.system.statusItem(
                    withLength: ControlItem.statusItemMaterializationLength
                )
                item.autosaveName = "\(identifier.rawValue).Spacer.\(index)"

                if let button = item.button {
                    button.title = ""
                    button.image = nil
                    button.isEnabled = false
                    button.appearsDisabled = true
                    button.alphaValue = 0
                }

                return item
            }
        }

        spacerItems.forEach { setIfChanged($0, \.length, Lengths.expanded) }
    }

    private func removeSpacerItems() {
        for item in spacerItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        spacerItems.removeAll()
    }

    /// Calculates how many spacer items are needed to push hidden items off ultra-wide displays.
    private func requiredSpacerCount() -> Int {
        let maxScreenWidth = NSScreen.screens.map(\.frame.width).max() ?? 6000
        guard maxScreenWidth > 5120 else { return 0 }

        let desiredWidth = maxScreenWidth * 3
        let remaining = desiredWidth - Lengths.expanded
        guard remaining > 0 else { return 0 }
        return Int(ceil(remaining / Lengths.expanded))
    }

    private func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }
        // isVisible = false deletes the preferred position, so cache and
        // restore it. Dividers too, or one can land on top of the other.
        let autosaveName = statusItem.autosaveName as String
        let cached = ControlItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        ControlItemDefaults.setIgnoringSectionDividerGuard(
            .preferredPosition,
            autosaveName,
            to: cached
        )
    }

    /// Updates the status item's visibility without clearing its preferred position.
    private func setIceIconDisplayed(_ shouldShow: Bool) {
        statusItem.isVisible = true
        if shouldShow {
            updateStatusItem()
            return
        }

        hideIceIconCompletely()
    }

    /// Hides the Ice icon without removing the status item or losing autosave data.
    private func hideIceIconCompletely() {
        if let constraint {
            setIfChanged(constraint, \.isActive, false)
        }
        setIfChanged(statusItem, \.length, 0)
        setWindowWidthIfChanged(1)
    }

    @objc private func performAction() {
        guard
            let appState,
            let event = NSApp.currentEvent
        else {
            return
        }
        let menuBarManager = appState.menuBarManager

        switch event.type {
        case .leftMouseDown:
            // Drop phantom left clicks while no menu bar items are on screen,
            // as during the reveal over a fullscreen app. Presentation options
            // are per-app, so check the item list. Right clicks still pass.
            let screenForCheck = window?.screen ?? NSScreen.main
            if let screen = screenForCheck, !screen.isSystemMenuBarVisible() {
                return
            }

            // Capture now, not when the Task runs.
            let modifierFlags = event.modifierFlags

            // Running this from a Task seems to improve the visual
            // responsiveness of the status item's button.
            Task { [appState] in
                if
                    appState.settings.advanced.useDoubleClickToShowAlwaysHiddenSection,
                    event.clickCount > 1,
                    identifier == .visible,
                    let alwaysHidden = menuBarManager.section(withName: .alwaysHidden),
                    alwaysHidden.isEnabled
                {
                    alwaysHidden.show()
                    return
                }

                if modifierFlags.contains(.control) {
                    showMenu()
                    return
                }

                if modifierFlags.contains(.option) {
                    // Option-click: only toggle always-hidden if enabled.
                    if
                        appState.settings.advanced.useOptionClickToShowAlwaysHiddenSection,
                        let section = menuBarManager.section(withName: .alwaysHidden),
                        section.isEnabled
                    {
                        section.toggle()
                    }
                    return
                }

                if
                    let section = menuBarManager.section(withName: sectionName),
                    section.isEnabled
                {
                    section.toggle()
                }
            }
        case .rightMouseUp:
            showMenu()
        default:
            return
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            appState.settings.hotkeys.hotkey(withAction: action)
        }

        let menu = NSMenu(title: Bundle.main.displayName)
        // Each item's isEnabled is the authority here. Automatic validation
        // would re-enable "All Trigger Features Off" simply because self
        // responds to its action.
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(
            title: String(localized: "\(Constants.displayName) Settings…"),
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(
            title: String(localized: "Search Menu Bar Items"),
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        )
        searchItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        if
            let hotkey = hotkey(withAction: .searchMenuBarItems),
            let keyCombination = hotkey.keyCombination
        {
            searchItem.keyEquivalent = keyCombination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
        }
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(.separator())

        if appState.settings.triggers.featureFlags.showsAllOffInMenuBarMenu {
            let allTriggerFeaturesOffItem = NSMenuItem(
                title: String(localized: "All Trigger Features Off"),
                action: #selector(disableAllTriggerFeatureFlags),
                keyEquivalent: ""
            )
            allTriggerFeaturesOffItem.image = NSImage(
                systemSymbolName: "power",
                accessibilityDescription: "All Trigger Features Off"
            )
            allTriggerFeaturesOffItem.target = self
            allTriggerFeaturesOffItem.isEnabled = appState.settings.triggers.featureFlags.hasEnabledFlags
            menu.addItem(allTriggerFeaturesOffItem)

            menu.addItem(.separator())
        }

        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.isEnabled
            else {
                continue
            }
            let sectionTitle: String
            let iconName: String
            switch (section.isHidden, name) {
            case (true, .hidden):
                sectionTitle = String(localized: "Show Hidden Section")
                iconName = "eye"
            case (false, .hidden):
                sectionTitle = String(localized: "Hide Hidden Section")
                iconName = "eye.slash"
            case (true, .alwaysHidden):
                sectionTitle = String(localized: "Show Always-Hidden Section")
                iconName = "eye"
            case (false, .alwaysHidden):
                sectionTitle = String(localized: "Hide Always-Hidden Section")
                iconName = "eye.slash"
            default:
                sectionTitle = String(localized: "\(section.isHidden ? "Show" : "Hide") \(name.displayString) Section")
                iconName = section.isHidden ? "eye" : "eye.slash"
            }
            let item = NSMenuItem(
                title: sectionTitle,
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: sectionTitle)
            if
                let hotkey = section.hotkey,
                let keyCombination = hotkey.keyCombination
            {
                item.keyEquivalent = keyCombination.key.keyEquivalent
                item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
            }
            item.target = self
            item.representedObject = section
            menu.addItem(item)
        }

        let profileManager = appState.profileManager
        if !profileManager.profiles.isEmpty {
            menu.addItem(.separator())

            let profilesItem = NSMenuItem(
                title: String(localized: "Profiles"),
                action: nil,
                keyEquivalent: ""
            )
            profilesItem.image = NSImage(
                systemSymbolName: "person.crop.rectangle.stack",
                accessibilityDescription: "Profiles"
            )
            let profilesMenu = NSMenu()
            for meta in profileManager.profiles {
                let item = NSMenuItem(
                    title: meta.name,
                    action: #selector(applyProfileFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = meta.id
                if meta.id == profileManager.activeProfileID {
                    item.state = .on
                }
                profilesMenu.addItem(item)
            }
            profilesItem.submenu = profilesMenu
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Check for Updates")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        let supportItem = NSMenuItem(
            title: String(localized: "Support \(Constants.displayName)…"),
            action: #selector(openDonateURL),
            keyEquivalent: ""
        )
        supportItem.image = NSImage(systemSymbolName: "heart.circle.fill", accessibilityDescription: "Support")
        supportItem.target = self
        menu.addItem(supportItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit \(Constants.displayName)"),
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)

        let restartItem = NSMenuItem(
            title: String(localized: "Restart \(Constants.displayName)"),
            action: #selector(restartFromMenu),
            keyEquivalent: "q"
        )
        restartItem.keyEquivalentModifierMask = [.command, .option]
        restartItem.isAlternate = true
        restartItem.target = self
        restartItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Restart")
        menu.addItem(restartItem)

        return menu
    }

    @objc private func restartFromMenu() {
        appState?.restartSelf()
    }

    private func showMenu() {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        statusItem.showMenu(menu)
    }

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        section.toggle()
    }

    @objc private func disableAllTriggerFeatureFlags() {
        appState?.settings.triggers.featureFlags.disableAll()
    }

    @objc private func showSearchPanel() {
        appState?.menuBarManager.searchPanel.show()
    }

    /// Applies the profile selected from the context menu.
    @objc private func applyProfileFromMenu(_ menuItem: NSMenuItem) {
        guard
            let profileID = menuItem.representedObject as? UUID,
            let appState,
            appState.profileManager.layoutTask == nil,
            profileID != appState.profileManager.activeProfileID
        else { return }
        let profileManager = appState.profileManager
        Task {
            guard let profile = try? profileManager.loadProfile(id: profileID) else { return }
            let previousID = profileManager.activeProfileID
            profileManager.activeProfileID = profileID
            profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
        }
    }

    /// Opens the settings window and checks for app updates.
    @objc private func checkForUpdates() {
        guard let appState else {
            return
        }
        appState.updatesManager.checkForUpdates()
    }

    @objc private func openDonateURL() {
        NSWorkspace.shared.open(Constants.donateURL)
    }
}

// MARK: - ControlItemDefaults

/// Proxy getters and setters for a control item's stored
/// UserDefaults values.
nonisolated enum ControlItemDefaults {
    /// Accesses the value associated with the specified key
    /// and autosave name.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            let stringKey = key.stringKey(for: autosaveName)
            return Defaults.store.object(forKey: stringKey) as? Value
        }
        set {
            // Prevent saving preferred position for section divider chevrons
            if key.isPreferredPosition, isSectionDivider(autosaveName: autosaveName) {
                return
            }
            let stringKey = key.stringKey(for: autosaveName)
            return Defaults.store.set(newValue, forKey: stringKey)
        }
    }

    /// Writes a value without the section-divider guard above.
    ///
    /// AppKit writes the preferred position itself, so the guard only ever
    /// blocked Thaw's own divider seeding. With no stored position both
    /// dividers can land at the same X, collapsing the span between them.
    /// Only preflightSetup(for:) and resetChevronPositions() should bypass it.
    static func setIgnoringSectionDividerGuard<Value>(
        _ key: Key<Value>,
        _ autosaveName: String,
        to newValue: Value?
    ) {
        Defaults.store.set(newValue, forKey: key.stringKey(for: autosaveName))
    }

    /// Returns whether the given autosave name belongs to a section divider.
    static func isSectionDivider(autosaveName: String) -> Bool {
        autosaveName == ControlItem.Identifier.hidden.rawValue ||
            autosaveName == ControlItem.Identifier.alwaysHidden.rawValue
    }

    /// Migrates the given control item defaults key from an old
    /// autosave name to a new autosave name.
    static func migrate(key: Key<some Any>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }

    /// Performs some initial required setup work before the
    /// creation of a control item.
    static func preflightSetup(for identifier: ControlItem.Identifier) {
        let autosaveName = identifier.rawValue

        // Visible and hidden control items go before existing items. Seed
        // only when nothing is stored: this runs on every launch and every
        // recreate, and re-stamping would collapse the user's hidden section.
        if ControlItemDefaults[.preferredPosition, autosaveName] == nil {
            switch identifier {
            case .visible:
                ControlItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, autosaveName, to: 1)
            case .alwaysHidden:
                break
            }
        }

        // The control item should be visible by default. We change
        // this after finishing setup, if needed.
        if ControlItemDefaults[.visible, autosaveName] == nil {
            ControlItemDefaults[.visible, autosaveName] = true
        }
        if ControlItemDefaults[.visibleCC, autosaveName] == nil {
            ControlItemDefaults[.visibleCC, autosaveName] = true
        }
    }

    /// Resets chevron section divider positions to their defaults.
    static func resetChevronPositions() {
        ControlItemDefaults.setIgnoringSectionDividerGuard(
            .preferredPosition,
            ControlItem.Identifier.hidden.rawValue,
            to: 1
        )
        // Always-hidden position is handled dynamically
    }
}

// MARK: - ControlItemDefaults.Key

nonisolated extension ControlItemDefaults {
    /// Keys used to look up UserDefaults values for control items.
    struct Key<Value> {
        let rawValue: String

        /// Whether this key represents a preferred position.
        var isPreferredPosition: Bool {
            rawValue == "Preferred Position"
        }

        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>

nonisolated extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: "Preferred Position")
}

// MARK: ControlItemDefaults.Key<Bool>

nonisolated extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
