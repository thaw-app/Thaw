//
//  ControlItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

// MARK: - ControlItem

/// A status item that controls a section in the menu bar.
@MainActor
final class ControlItem: NSObject {
    private let diagLog = DiagLog(category: "ControlItem")

    /// An identifier for a control item.
    enum Identifier: String, CaseIterable {
        /// The identifier for the control item for the visible section.
        case visible = "Thaw.ControlItem.Visible"
        /// The identifier for the control item for the hidden section.
        case hidden = "Thaw.ControlItem.Hidden"
        /// The identifier for the control item for the always-hidden section.
        case alwaysHidden = "Thaw.ControlItem.AlwaysHidden"

        /// A tag for the control item with this identifier.
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
                case .showSection:
                    Lengths.standard
                case .hideSection:
                    // macOS 27 no longer reflows over-wide status items, so an
                    // expanded divider just overflows off the right edge and
                    // confuses section classification instead of hiding anything.
                    // Keep it at standard width there.
                    MenuBarBackendFactory.current.supportsLegacySectionHiding ? Lengths.expanded : Lengths.standard
                }
            }
        }
    }

    /// A hiding state for a control item.
    enum HidingState {
        case showSection
        case hideSection
    }

    /// The visual treatment for a hidden/always-hidden section divider.
    enum SectionDividerPresentation: Equatable {
        /// Collapse the status item because the user selected no divider.
        case hidden
        /// Show the small, interactive chevron between sections.
        case chevron
        /// Keep the legacy expanded divider invisible while it reflows items.
        case legacyConcealedSection
    }

    /// Resolves divider appearance independently of AppKit so the macOS 26 and
    /// macOS 27 policies cannot accidentally bleed into each other.
    static nonisolated func sectionDividerPresentation(
        state: HidingState,
        style: SectionDividerStyle,
        supportsSectionHiding: Bool
    ) -> SectionDividerPresentation {
        if case .hideSection = state {
            return supportsSectionHiding ? .legacyConcealedSection : .hidden
        }
        return switch style {
        case .noDivider: .hidden
        case .chevron: .chevron
        }
    }

    /// A namespace for control item lengths.
    private enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10000
    }

    /// Storage for a control item's underlying status item.
    private final class StatusItemStorage {
        /// The Objective-C selector for AppKit's control-event target API.
        ///
        /// Xcode 26's SDK does not declare this API, even though macOS 27 uses
        /// it to deliver semantic status-item activation. Resolve it at runtime
        /// so distribution builds can continue using the older SDK.
        private static let addTargetSelector = NSSelectorFromString("addTarget:action:forControlEvents:")

        /// Raw value of `NSControl.Event.primaryActionTriggered` in macOS 27.
        private static let primaryActionTriggeredEvent: UInt = 1 << 13

        let statusItem: NSStatusItem
        let constraint: NSLayoutConstraint?

        /// Registers the macOS 27 semantic primary action when AppKit exposes
        /// the control-event API at runtime.
        @available(macOS 27, *)
        private static func registerPrimaryAction(
            for button: NSStatusBarButton,
            controlItem: ControlItem
        ) -> Bool {
            let selector = addTargetSelector
            guard button.responds(to: selector) else {
                return false
            }

            typealias AddTargetImp = @convention(c) (
                AnyObject,
                Selector,
                AnyObject?,
                Selector,
                UInt
            ) -> Void

            // `responds(to:)` only proves the selector resolves to *some* IMP,
            // not that it matches the (void, id, SEL, id, SEL, NSUInteger) C
            // convention assumed below. Verify the runtime's type encoding
            // before invoking a raw `unsafeBitCast` IMP so a future macOS 27.x
            // point release that changes the signature fails loudly instead of
            // corrupting the call stack.
            guard
                let method = class_getInstanceMethod(type(of: button), selector),
                let encodingPointer = method_getTypeEncoding(method)
            else {
                assertionFailure("addTarget:action:forControlEvents: has no resolvable type encoding; refusing to bind the primary action.")
                return false
            }
            let encoding = String(cString: encodingPointer)
            guard encoding.hasPrefix("v@:@:"), encoding.hasSuffix("Q") else {
                assertionFailure("addTarget:action:forControlEvents: signature (\(encoding)) no longer matches the assumed (void, id, SEL, id, SEL, NSUInteger) C convention; refusing to bind the primary action.")
                return false
            }

            let implementation = unsafeBitCast(button.method(for: selector), to: AddTargetImp.self)
            implementation(
                button,
                selector,
                controlItem,
                #selector(controlItem.performPrimaryAction),
                primaryActionTriggeredEvent
            )
            return true
        }

        /// Creates a new storage instance.
        @MainActor
        init(controlItem: ControlItem) {
            ControlItemDefaults.preflightSetup(for: controlItem)

            self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
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

                if #available(macOS 27, *),
                   controlItem.identifier == .visible,
                   Self.registerPrimaryAction(for: button, controlItem: controlItem)
                {
                    // MenuBarAgent forwards semantic primary activation, but
                    // not the status button's secondary-click gesture. The HID
                    // event path handles that gesture using the live icon frame.
                } else {
                    button.target = controlItem
                    button.action = #selector(controlItem.performAction)
                    button.sendAction(on: [.leftMouseDown, .rightMouseUp])
                }

                // On macOS 27 the WindowServer no longer exposes individual
                // menu bar item windows, so Thaw enumerates items through the
                // Accessibility tree instead (see MenuBarItemAXProvider). AX
                // does not surface the status item's autosaveName, so publish
                // the control item's stable identifier as the accessibility
                // identifier. This lets the AX enumerator recognize Thaw's own
                // control items (and match them to their MenuBarItemTag) the
                // same way the CGS path matched on the window title. Only needed
                // on macOS 27; leave macOS 26 untouched.
                if #available(macOS 27, *) {
                    button.setAccessibilityIdentifier(controlItem.identifier.rawValue)
                }
            } else {
                self.constraint = nil
            }
        }

        deinit {
            removeStatusItem()
        }

        /// Removes the status item from the status bar.
        private func removeStatusItem() {
            // Removing the status item has the unwanted side effect of
            // deleting the preferred position. Cache and restore it,
            // but only for non-section-divider items.
            let autosaveName = statusItem.autosaveName as String
            let isSectionDivider = ControlItemDefaults.isSectionDivider(autosaveName: autosaveName)
            let cached = ControlItemDefaults[.preferredPosition, autosaveName]
            NSStatusBar.system.removeStatusItem(statusItem)
            ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: autosaveName)
            if ControlItemDefaults.shouldRestorePreferredPositionAfterRemoval(
                autosaveName: autosaveName,
                isSectionDivider: isSectionDivider
            ) {
                ControlItemDefaults[.preferredPosition, autosaveName] = cached
            }
        }
    }

    /// The control item's hiding state (`@Published`).
    @Published var state = HidingState.hideSection

    /// The control item's window (`@Published`).
    @Published private(set) var window: NSWindow?

    /// The control item's frame (`@Published`).
    @Published private(set) var frame: CGRect?

    /// The control item's screen (`@Published`).
    @Published private(set) var screen: NSScreen?

    /// The control item's frame, if it is onscreen (`@Published`).
    @Published private(set) var onScreenFrame: CGRect?

    /// The control item's identifier.
    let identifier: Identifier

    /// Lazy storage for the control item's underlying status item.
    private lazy var storage = StatusItemStorage(controlItem: self)

    /// Spacer items used to extend hidden/always-hidden width on ultra-wide displays.
    private var spacerItems = [NSStatusItem]()

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Task animating a legacy section divider width change.
    private var lengthAnimationTask: Task<Void, Never>?

    /// Whether next visibility update should animate the divider width.
    private var shouldAnimateNextVisibilityUpdate = false

    /// The control item's underlying status item.
    private var statusItem: NSStatusItem {
        storage.statusItem
    }

    /// A horizontal constraint for the control item's content view.
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

    /// Animates next legacy divider visibility update.
    func animateNextVisibilityUpdate() {
        shouldAnimateNextVisibilityUpdate = true
    }

    /// The corresponding section name for the control item.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Creates a control item with the given identifier.
    init(identifier: Identifier) {
        self.identifier = identifier
        super.init()
    }

    /// Performs the initial setup of the control item.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    /// Configures the internal observers for the control item.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &c)

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
            .flatMap { $0.publisher(for: \.window) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.window = window
            }
            .store(in: &c)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frame = frame
            }
            .store(in: &c)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.screen) }
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.screen = screen
            }
            .store(in: &c)

        $screen.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
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
            appState.$isDraggingMenuBarItem
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isDragging in
                    guard let self else {
                        return
                    }
                    if isDragging {
                        updateStatusItem()
                    }
                }
                .store(in: &c)

            if identifier == .visible {
                appState.settings.general.$showIceIcon
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] shouldShow in
                        guard let self else {
                            return
                        }
                        setIceIconDisplayed(shouldShow)
                    }
                    .store(in: &c)

                appState.settings.general.$iceIcon
                    .combineLatest(appState.settings.general.$customIceIconIsTemplate)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }

            if identifier == .alwaysHidden {
                appState.settings.advanced.$enableAlwaysHiddenSection
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] shouldEnable, _ in
                        guard let self else {
                            return
                        }
                        if shouldEnable {
                            addToMenuBar()
                        } else {
                            removeFromMenuBar()
                        }
                    }
                    .store(in: &c)
            }

            if isSectionDivider {
                appState.settings.advanced.$sectionDividerStyle
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }
        }

        cancellables = c
    }

    /// Updates the appearance of the status item using the current hiding state.
    private func updateStatusItem() {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        button.title = ""
        button.image = nil

        switch identifier {
        case .visible:
            if !appState.settings.general.showIceIcon {
                hideIceIconCompletely()
                return
            }
            ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: identifier.rawValue)
            addToMenuBar()
            updateStatusItemVisibility(true)
            button.isEnabled = true
            button.alphaValue = 1
            button.appearsDisabled = false
            button.isHighlighted = false

            let icon = appState.settings.general.iceIcon

            // We can usually just create the image directly from the icon.
            var image = switch state {
            case .showSection: icon.visible.nsImage(for: appState)
            case .hideSection: icon.hidden.nsImage(for: appState)
            }

            if
                case .custom = icon.name,
                let originalImage = image
            {
                // Custom icons need to be resized to fit inside the button.
                let originalWidth = originalImage.size.width
                let originalHeight = originalImage.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                image = originalImage.resized(to: newSize)
            }

            button.image = image
        case .hidden, .alwaysHidden:
            switch Self.sectionDividerPresentation(
                state: state,
                style: appState.settings.advanced.sectionDividerStyle,
                supportsSectionHiding: MenuBarBackendFactory.current.supportsLegacySectionHiding
            ) {
            case .hidden:
                button.isEnabled = true
                button.alphaValue = 1
                updateStatusItemVisibility(false)
                button.appearsDisabled = true
                button.isHighlighted = false

                if appState.isDraggingMenuBarItem, appState.settings.advanced.showAllSectionsOnUserDrag {
                    // We still want a subtle marker between sections.
                    button.title = "|"
                }
            case .chevron:
                updateStatusItemVisibility(true)
                button.isEnabled = true
                button.alphaValue = 1
                button.appearsDisabled = false
                button.image = ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
            case .legacyConcealedSection:
                updateStatusItemVisibility(true)
                button.appearsDisabled = true
                button.isHighlighted = false
                // Match the spacer item pattern: invisible and non-interactive.
                // The constraint stays active so items are pushed off-screen.
                button.isEnabled = false
                button.alphaValue = 0
            }
        }
    }

    /// Updates the visibility of the status item.
    ///
    /// The hidden and always-hidden control items must always be present in
    /// the menu bar, as we use their positions to determine the items in each
    /// section. Setting `statusItem.isVisible` to `false` completely removes
    /// the item. Instead, we toggle the width constraint on the item's content
    /// view, update the item's length, then adjust the content size of the
    /// item's window if needed.
    private func updateStatusItemVisibility(_ isVisible: Bool) {
        guard let appState else {
            return
        }

        let animateLength = shouldAnimateNextVisibilityUpdate
            && MenuBarBackendFactory.current.supportsLegacySectionHiding
            && (identifier == .hidden || identifier == .alwaysHidden)
            && !appState.isDraggingMenuBarItem
        shouldAnimateNextVisibilityUpdate = false

        if isVisible {
            constraint?.isActive = true
            setStatusItemLength(identifier.length(for: state), animated: animateLength)

            let shouldUseSpacers = MenuBarBackendFactory.current.supportsLegacySectionHiding
                && (identifier == .hidden || identifier == .alwaysHidden)
                && state == .hideSection
            updateSpacerItems(forHiddenState: shouldUseSpacers)
        } else {
            updateSpacerItems(forHiddenState: false)
            let showOnDrag = appState.settings.advanced.showAllSectionsOnUserDrag
            let isDragging = appState.isDraggingMenuBarItem

            let shouldShow = showOnDrag && isDragging

            constraint?.isActive = false
            setStatusItemLength(shouldShow ? 3 : 0, animated: animateLength)

            if let window {
                let size = withMutableCopy(of: window.frame.size) { $0.width = shouldShow ? 3 : 1 }
                window.setContentSize(size)
            }
        }
    }

    /// Updates status item length immediately or with a short width animation.
    private func setStatusItemLength(_ targetLength: CGFloat, animated: Bool) {
        lengthAnimationTask?.cancel()

        guard animated else {
            lengthAnimationTask = nil
            statusItem.length = targetLength
            return
        }

        let resolvedTargetLength = resolvedAnimationLength(for: targetLength)
        let startLength = resolvedCurrentLength()
        guard abs(startLength - resolvedTargetLength) > 1 else {
            statusItem.length = targetLength
            return
        }

        lengthAnimationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let duration: TimeInterval = 0.22
            let frameCount = 16

            for frame in 1 ... frameCount {
                guard !Task.isCancelled else {
                    return
                }

                let progress = CGFloat(frame) / CGFloat(frameCount)
                let eased = Self.easeInOutCubic(progress)
                self.statusItem.length = startLength + (resolvedTargetLength - startLength) * eased
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000 / Double(frameCount))))
            }

            guard !Task.isCancelled else {
                return
            }

            self.statusItem.length = targetLength
            self.lengthAnimationTask = nil
        }
    }

    /// Current status-item width suitable as animation start value.
    private func resolvedCurrentLength() -> CGFloat {
        if statusItem.length >= 0 {
            return statusItem.length
        }

        if let button = statusItem.button, button.bounds.width > 0 {
            return button.bounds.width
        }

        return identifier == .visible ? 24 : 18
    }

    /// Converts variable status-item length to an animatable normal width.
    private func resolvedAnimationLength(for length: CGFloat) -> CGFloat {
        guard length == NSStatusItem.variableLength else {
            return length
        }

        return identifier == .visible ? 24 : 18
    }

    /// Smoothstep-like curve for section divider width changes.
    private static func easeInOutCubic(_ progress: CGFloat) -> CGFloat {
        if progress < 0.5 {
            return 4 * progress * progress * progress
        }

        let f = -2 * progress + 2
        return 1 - (f * f * f) / 2
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
                let item = NSStatusBar.system.statusItem(withLength: 0)
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

        spacerItems.forEach { $0.length = Lengths.expanded }
    }

    /// Removes spacer items from the status bar.
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

    /// Adds the control item to the menu bar.
    private func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Removes the control item from the menu bar.
    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }
        // Setting `statusItem.isVisible` to `false` has the unwanted side
        // effect of deleting the preferred position. Cache and restore it,
        // but only for non-section-divider items.
        let autosaveName = statusItem.autosaveName as String
        let isSectionDivider = (identifier == .hidden || identifier == .alwaysHidden)
        let cached = ControlItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: autosaveName)
        if ControlItemDefaults.shouldRestorePreferredPositionAfterRemoval(
            autosaveName: autosaveName,
            isSectionDivider: isSectionDivider
        ) {
            ControlItemDefaults[.preferredPosition, autosaveName] = cached
        }
    }

    /// Removes the control item (and any spacers) from the menu bar ahead of
    /// app termination.
    ///
    /// macOS 27 does not reliably drop a status item when its owning process
    /// exits — the icon (and its now-dead menu) linger as a ghost. Removing the
    /// item explicitly while the app is still alive lets MenuBarAgent reclaim it
    /// cleanly. The preferred position is preserved by `removeFromMenuBar()`.
    func tearDownForTermination() {
        removeSpacerItems()
        removeFromMenuBar()
    }

    /// Updates the status item's visibility without clearing its preferred position.
    private func setIceIconDisplayed(_ shouldShow: Bool) {
        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: identifier.rawValue)
        statusItem.isVisible = true
        if shouldShow {
            updateStatusItem()
            return
        }

        hideIceIconCompletely()
    }

    /// Hides the Ice icon without removing the status item or losing autosave data.
    private func hideIceIconCompletely() {
        constraint?.isActive = false
        statusItem.length = 0

        if let window {
            let size = withMutableCopy(of: window.frame.size) { $0.width = 1 }
            window.setContentSize(size)
        }
    }

    /// Reasserts the visible icon's AppKit state after macOS 27 applies a menu bar
    /// visibility restriction. This is intentionally lighter than unregistering and
    /// re-registering the status item: the item remains owned by the main app, but
    /// its visibility bits, length, constraint, and image are refreshed after
    /// MenuBarAgent has reflowed the bar.
    func restoreVisibleIconAfterRestrictionChange() {
        guard #available(macOS 27, *), identifier == .visible else {
            return
        }

        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: identifier.rawValue)
        statusItem.isVisible = true

        guard appState?.settings.general.showIceIcon == true else {
            hideIceIconCompletely()
            return
        }

        constraint?.isActive = true
        statusItem.length = identifier.length(for: state)
        updateStatusItem()
    }

    /// Returns a compact AppKit/status-item state snapshot for diagnostics.
    func diagnosticStateDescription() -> String {
        let autosaveName = statusItem.autosaveName as String
        let button = statusItem.button
        let window = button?.window ?? window
        let frameDescription = window.map { NSStringFromRect($0.frame) } ?? "nil"
        let storedVisible: String = ControlItemDefaults[.visible, autosaveName].map(String.init) ?? "nil"
        let storedVisibleCC: String = ControlItemDefaults[.visibleCC, autosaveName].map(String.init) ?? "nil"
        let storedPosition: String = ControlItemDefaults[.preferredPosition, autosaveName].map(String.init) ?? "nil"

        // Identity fields MenuBarAgent may key the visibility-restriction
        // allowlist on. MenuBarAgent logs "No server elements for status item:
        // nil" for our items, so log everything Thaw exposes to compare against a
        // known-good app's item.
        let buttonIdentifier = button?.identifier?.rawValue ?? "nil"
        let rawA11yID = button?.accessibilityIdentifier()
        let buttonA11yID = (rawA11yID == nil || rawA11yID?.isEmpty == true) ? "nil" : (rawA11yID ?? "nil")
        let windowIdentifier = window?.identifier?.rawValue ?? "nil"
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"

        return [
            "id=\(identifier.rawValue)",
            "autosaveName=\(autosaveName)",
            "buttonID=\(buttonIdentifier)",
            "buttonA11yID=\(buttonA11yID)",
            "windowID=\(windowIdentifier)",
            "bundleID=\(bundleID)",
            "state=\(state)",
            "statusVisible=\(statusItem.isVisible)",
            "length=\(statusItem.length)",
            "buttonExists=\(button != nil)",
            "buttonEnabled=\(button?.isEnabled.description ?? "nil")",
            "buttonAlpha=\(button.map { "\($0.alphaValue)" } ?? "nil")",
            "appearsDisabled=\(button?.appearsDisabled.description ?? "nil")",
            "hasImage=\((button?.image) != nil)",
            "windowNumber=\(window.map { "\($0.windowNumber)" } ?? "nil")",
            "windowFrame=\(frameDescription)",
            "defaultsVisible=\(storedVisible)",
            "defaultsVisibleCC=\(storedVisibleCC)",
            "defaultsPreferredPosition=\(storedPosition)",
        ].joined(separator: " ")
    }

    /// Performs the control item's action.
    @objc private func performAction() {
        guard
            let appState,
            let event = NSApp.currentEvent
        else {
            return
        }
        let menuBarManager = appState.menuBarManager

        // Suppress phantom clicks delivered to the status item button while
        // no menu bar items are rendered on-screen for the active space. This
        // catches fast top-of-screen clicks during the menu bar reveal
        // sequence under a fullscreen app, which would otherwise expand the
        // hidden section offscreen. NSApp.currentSystemPresentationOptions is
        // per-app and does not reflect another app's fullscreen state, so the
        // items-list signal is used directly.
        let screenForCheck = window?.screen ?? NSScreen.main
        if let screen = screenForCheck, !screen.isSystemMenuBarVisible() {
            return
        }

        switch event.type {
        case .leftMouseDown:
            // Capture modifier flags from the event to ensure we have the state
            // at the time of the click, not when the Task executes.
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

    /// The semantic action produced by primary status-button activation.
    enum PrimaryActionIntent: Equatable {
        case toggleSection
        case showAlwaysHidden
        case toggleAlwaysHidden
        case contextMenu
        case none
    }

    /// Resolves primary activation independently of AppKit event delivery.
    static nonisolated func primaryActionIntent(
        identifier: Identifier,
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int,
        usesDoubleClick: Bool,
        usesOptionClick: Bool
    ) -> PrimaryActionIntent {
        if usesDoubleClick, clickCount > 1, identifier == .visible {
            return .showAlwaysHidden
        }
        if modifierFlags.contains(.control) {
            return .contextMenu
        }
        if modifierFlags.contains(.option) {
            return usesOptionClick ? .toggleAlwaysHidden : .none
        }
        return .toggleSection
    }

    /// Resolves macOS 27 semantic primary activation for the visible control item.
    ///
    /// Control-click context menus are routed through ``HIDEventManager`` on
    /// `leftMouseDown`. `primaryActionTriggered` can inherit stale modifier
    /// flags from `NSApp.currentEvent`, so the control bit is ignored here.
    static nonisolated func menuBarAgentPrimaryActionIntent(
        identifier: Identifier,
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int,
        usesDoubleClick: Bool,
        usesOptionClick: Bool,
        diagLog: DiagLog? = nil
    ) -> PrimaryActionIntent {
        let intent: PrimaryActionIntent = if usesDoubleClick, clickCount > 1, identifier == .visible {
            .showAlwaysHidden
        } else if modifierFlags.contains(.option) {
            usesOptionClick ? .toggleAlwaysHidden : .none
        } else {
            .toggleSection
        }
        diagLog?.debug("menuBarAgentPrimaryActionIntent: identifier=\(identifier.rawValue), modifierFlags=\(modifierFlags), clickCount=\(clickCount), usesDoubleClick=\(usesDoubleClick), usesOptionClick=\(usesOptionClick) → \(intent)")
        return intent
    }

    /// Handles macOS 27's semantic primary action for the visible control item.
    /// Control-click and right-click context menus are routed through
    /// `HIDEventManager` because MenuBarAgent does not forward secondary
    /// gestures from the remotely hosted status button.
    @available(macOS 27, *)
    @objc private func performPrimaryAction() {
        guard let appState else {
            return
        }

        let screenForCheck = window?.screen ?? NSScreen.main
        if let screen = screenForCheck, !screen.isSystemMenuBarVisible() {
            return
        }

        let event = NSApp.currentEvent
        let modifierFlags = event?.modifierFlags ?? []
        let effectiveModifierFlags = modifierFlags.isEmpty
            ? NSEvent.modifierFlags
            : modifierFlags
        let intent = Self.menuBarAgentPrimaryActionIntent(
            identifier: identifier,
            modifierFlags: effectiveModifierFlags,
            clickCount: event?.clickCount ?? 0,
            usesDoubleClick: appState.settings.advanced.useDoubleClickToShowAlwaysHiddenSection,
            usesOptionClick: appState.settings.advanced.useOptionClickToShowAlwaysHiddenSection,
            diagLog: diagLog
        )
        let menuBarManager = appState.menuBarManager

        // Run synchronously on the main actor. Deferring through `Task` let
        // rapid clicks queue conflicting show/hide toggles before
        // `revealedSection` settled, which made hide feel like it needed
        // multiple clicks.
        switch intent {
        case .toggleSection:
            if let section = menuBarManager.section(withName: sectionName), section.isEnabled {
                section.toggle()
            }
        case .showAlwaysHidden:
            if let section = menuBarManager.section(withName: .alwaysHidden), section.isEnabled {
                diagLog.debug("performPrimaryAction: showAlwaysHidden → permanent show")
                for s in menuBarManager.sections {
                    s.desiredState = .showSection
                    s.updateControlItemState(for: nil)
                }
                menuBarManager.simpleItemHider?.show(.alwaysHidden)
            } else {
                diagLog.debug("performPrimaryAction: showAlwaysHidden — section found=\(menuBarManager.section(withName: .alwaysHidden) != nil), isEnabled=\(menuBarManager.section(withName: .alwaysHidden)?.isEnabled ?? false)")
            }
        case .toggleAlwaysHidden:
            if let section = menuBarManager.section(withName: .alwaysHidden), section.isEnabled {
                let makeVisible = section.isHidden
                diagLog.debug("performPrimaryAction: toggleAlwaysHidden → permanent toggle, isHidden=\(section.isHidden)")
                for s in menuBarManager.sections {
                    s.desiredState = makeVisible ? .showSection : .hideSection
                    s.updateControlItemState(for: nil)
                }
                if makeVisible {
                    menuBarManager.simpleItemHider?.show(.alwaysHidden)
                } else {
                    menuBarManager.simpleItemHider?.hideRevealedSections()
                    menuBarManager.iceBarPanel.close()
                }
            } else {
                diagLog.debug("performPrimaryAction: toggleAlwaysHidden — section found=\(menuBarManager.section(withName: .alwaysHidden) != nil), isEnabled=\(menuBarManager.section(withName: .alwaysHidden)?.isEnabled ?? false)")
            }
        case .contextMenu, .none:
            break
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            appState.settings.hotkeys.hotkey(withAction: action)
        }

        let menu = NSMenu(title: Bundle.main.displayName)

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

        // Add items to toggle the hidden and always-hidden sections.
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

        // Profiles submenu.
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

        if Constants.supportsSparkleUpdates {
            let checkForUpdatesItem = NSMenuItem(
                title: String(localized: "Check for Updates…"),
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            checkForUpdatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Check for Updates")
            checkForUpdatesItem.target = self
            menu.addItem(checkForUpdatesItem)
        }

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
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
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

    /// Terminates the app, deferred to the next default-mode run loop pass.
    ///
    /// This menu item's action fires inside the status-item menu's
    /// event-tracking run loop. Calling `NSApp.terminate` directly from there
    /// can leave the `.terminateLater` async reply (scheduled by
    /// `applicationShouldTerminate`) unable to drain while the run loop is still
    /// in tracking mode, so the process never finishes — the exact "exit sent
    /// from the wrong run-loop mode" hang. Scheduling in `.default` runs
    /// terminate after menu tracking unwinds; mirrors
    /// `MenuBarManager.quitFromSecondaryContextMenu`. Especially important on
    /// macOS 27, where this menu is the only way to quit.
    @objc private func quitFromMenu() {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func restartFromMenu() {
        appState?.restartSelf()
    }

    /// Shows the control item's menu.
    private func showMenu() {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        statusItem.showMenu(menu)
    }

    /// Shows the Thaw-icon context menu at a global screen location.
    /// Used on macOS 27 because MenuBarAgent does not forward secondary-click
    /// gestures through the remotely hosted status-bar button.
    func showContextMenu(at point: CGPoint) {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        section.toggle()
    }

    /// Opens the menu bar search panel.
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

    /// Opens the donate URL.
    @objc private func openDonateURL() {
        NSWorkspace.shared.open(Constants.donateURL)
    }
}

// MARK: - ControlItemDefaults

/// Proxy getters and setters for a control item's stored
/// UserDefaults values.
enum ControlItemDefaults {
    /// Accesses the value associated with the specified key
    /// and autosave name.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.object(forKey: stringKey) as? Value
        }
        set {
            // Prevent saving preferred position for section divider chevrons
            if key.isPreferredPosition, isSectionDivider(autosaveName: autosaveName) {
                return
            }
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.set(newValue, forKey: stringKey)
        }
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
    fileprivate static func preflightSetup(for controlItem: ControlItem) {
        let autosaveName = controlItem.identifier.rawValue

        if #available(macOS 27, *), controlItem.identifier == .visible {
            restoreVisibilityIfNeeded(autosaveName: autosaveName)
            return
        }

        // Visible and hidden control items should be added before
        // existing items in the status bar.
        if ControlItemDefaults[.preferredPosition, autosaveName] == nil {
            switch controlItem.identifier {
            case .visible:
                ControlItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                ControlItemDefaults[.preferredPosition, autosaveName] = 1
            case .alwaysHidden:
                break
            }
        }

        // Always reset section divider positions to defaults
        // to prevent issues when users move them around
        if isSectionDivider(autosaveName: autosaveName) {
            switch controlItem.identifier {
            case .hidden:
                ControlItemDefaults[.preferredPosition, autosaveName] = 1
            case .alwaysHidden:
                // Don't set a default position for always-hidden
                // It will be positioned dynamically by the system
                break
            case .visible:
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
        restoreVisibilityIfNeeded(autosaveName: autosaveName)
    }

    /// Thaw's visible icon and hidden-section divider must remain registered with
    /// MenuBarAgent on macOS 27. Their presentation is controlled by length and
    /// alpha; persisting `VisibleCC = 0` prevents AppKit from publishing the item
    /// at all, so later appearance updates cannot bring it back.
    static func restoreVisibilityIfNeeded(autosaveName: String) {
        guard #available(macOS 27, *) else {
            return
        }

        switch autosaveName {
        case ControlItem.Identifier.visible.rawValue:
            ControlItemDefaults[.visible, autosaveName] = true
            ControlItemDefaults[.visibleCC, autosaveName] = true
            if let position = ControlItemDefaults[.preferredPosition, autosaveName], position <= 0 {
                ControlItemDefaults[.preferredPosition, autosaveName] = nil
            }
        case ControlItem.Identifier.hidden.rawValue:
            ControlItemDefaults[.visible, autosaveName] = true
            ControlItemDefaults[.visibleCC, autosaveName] = true
        default:
            break
        }
    }

    static func shouldRestorePreferredPositionAfterRemoval(
        autosaveName: String,
        isSectionDivider: Bool
    ) -> Bool {
        guard !isSectionDivider else {
            return false
        }

        if #available(macOS 27, *),
           autosaveName == ControlItem.Identifier.visible.rawValue
        {
            return false
        }

        return true
    }

    /// Resets chevron section divider positions to their defaults.
    static func resetChevronPositions() {
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.hidden.rawValue] = 1
        // Always-hidden position is handled dynamically
    }
}

// MARK: - ControlItemDefaults.Key

extension ControlItemDefaults {
    /// Keys used to look up UserDefaults values for control items.
    struct Key<Value> {
        /// The raw value of the key.
        let rawValue: String

        /// Whether this key represents a preferred position.
        var isPreferredPosition: Bool {
            rawValue == "Preferred Position"
        }

        /// Returns the full string key for the given autosave name.
        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>

extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: "Preferred Position")
}

// MARK: ControlItemDefaults.Key<Bool>

extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
