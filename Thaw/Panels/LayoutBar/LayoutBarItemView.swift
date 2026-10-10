//
//  LayoutBarItemView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import SwiftUI

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: LayoutBarArrangedView {
    private enum Metrics {
        static let minWidth: CGFloat = 14
        static let maxWidth = OverflowFallbackIcon.maximumItemWidth
        /// A tile drawing an icon instead of the item is icon-sized, however
        /// wide the item is on the bar.
        static let fallbackMaxWidth: CGFloat = 32
        static let minHeight: CGFloat = 18
        static let placeholderCornerRadius: CGFloat = 6
        static let placeholderHorizontalInset: CGFloat = 2
        static let placeholderVerticalInset: CGFloat = 2
        static let iconInset: CGFloat = 2
        static let unresponsiveBadgeWidth: CGFloat = 15
        static let defaultSystemItemHorizontalPadding: CGFloat = 16
    }

    private weak var appState: AppState?

    /// Subscription to the visible control item's $state, replaced on each
    /// adopt so a recycled row never keeps more than one alive.
    private var controlItemStateSubscription: AnyCancellable?

    /// Observes only this item's capture slot.
    private var imageObservationTask: Task<Void, Never>?

    /// Task observing the menu bar's average brightness, which decides the
    /// tint used for template images.
    private var brightnessObservationTask: Task<Void, Never>?

    /// Observes the app-icon preference through Observation.
    private var alwaysUseAppIconObservationTask: Task<Void, Never>?

    /// Observes experimental system-item hiding.
    private var systemItemHidingObservationTask: Task<Void, Never>?

    /// Observes the chosen Thaw icon and its template flag.
    private var thawIconObservationTask: Task<Void, Never>?

    isolated deinit {
        imageObservationTask?.cancel()
        brightnessObservationTask?.cancel()
        alwaysUseAppIconObservationTask?.cancel()
        systemItemHidingObservationTask?.cancel()
        thawIconObservationTask?.cancel()
        controlItemStateSubscription?.cancel()
        // Recycling can drop a view with an open popover; close it to avoid an orphaned anchor.
        inspectorPopover?.performClose(nil)
        isInspecting = false
        endSpotlight()
    }

    /// The item that the view represents. Reassigned by adopt(item:appState:)
    /// when the container recycles this view for a refreshed item.
    private(set) var item: MenuBarItem

    private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
    private var tooltipTrackingArea: NSTrackingArea?

    /// Delay hover spotlighting so sweeping across the editor does not strobe the agent with highlight calls.
    private var spotlightTask: Task<Void, Never>?

    /// Whether the agent confirmed a live highlight for this item, so
    /// teardown only releases spotlights that actually landed.
    private var isSpotlighted = false

    /// The click-to-inspect popover, retained while it is up.
    private var inspectorPopover: NSPopover?

    /// Hold spotlight across hover exit so users can reach inspector controls while the real item stays lit.
    /// releaseInspectorHolds() releases the hold.
    private var isInspecting = false

    /// A click is mouse-up without a drag, not a distance threshold, because dragging starts on the first pixel.
    private var isClickCandidate = false

    /// Whether the current gesture has already posted a refusal, so a drag on
    /// an immovable item explains itself once rather than on every pixel.
    private var didRefuseDrag = false

    private var placeholderImage: NSImage?
    /// Refreshed when the visible-section control item's icon or state changes.
    private var livePlaceholderImage: NSImage?

    /// The image displayed inside the view.
    private var cachedImage: MenuBarItemGlyphCapture? {
        didSet {
            let previousSize = frame.size
            cachedDrawImage = cachedImage.map {
                NSImage(cgImage: $0.cgImage, size: $0.pointSize)
            }
            systemItemHorizontalPadding = Self.systemItemHorizontalPadding(
                for: item,
                image: cachedImage,
                desiredPadding: desiredSystemItemHorizontalPadding
            )
            let newSize = preferredSizeForCurrentDisplayMode(cachedImage)
            setFrameSize(newSize)
            if previousSize != newSize {
                (superview as? LayoutBarContainer)?.itemPreferredSizeDidChange(self)
            }
            needsDisplay = true
        }
    }

    /// Rebuild only on capture changes to avoid allocating an NSImage on every draw pass.
    private var cachedDrawImage: NSImage?

    /// Extra transparent width needed to match the system host item's native
    /// menu-bar selection padding. Applied only in the layout editor.
    private var systemItemHorizontalPadding: CGFloat = 0

    /// Container polling shares two window-server round trips per owner PID instead of per-view timers.
    /// Seed in init for an immediate badge, then redraw only on changes.
    var isOwnerUnresponsive = false {
        didSet {
            guard isOwnerUnresponsive != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Set when macOS keeps the icon out of this tile's section.
    var visibilityLimit: LayoutBarVisibilityLimit? {
        didSet {
            guard visibilityLimit != oldValue else { return }
            toolTip = visibilityLimit?.explanation
            setAccessibilityHelp(visibilityLimit?.explanation)
            needsDisplay = true
        }
    }

    /// Cache template variants by source identity and tint; clear when menuBarForegroundColor changes.
    private var tintedImageCache: [ObjectIdentifier: [NSColor: NSImage]] = [:]

    override var kind: Kind {
        .item(item)
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState
        self.placeholderImage = Self.makePlaceholderImage(for: item, appState: appState)
        if item.tag.matchesVisibleControlItem {
            self.livePlaceholderImage = placeholderImage
        }

        let initialImage = appState.imageCache.image(for: item.tag)
        self.cachedImage = initialImage
        self.systemItemHorizontalPadding = Self.systemItemHorizontalPadding(
            for: item,
            image: initialImage,
            desiredPadding: Metrics.defaultSystemItemHorizontalPadding + CGFloat(appState.spacingManager.offset)
        )

        super.init(
            frame: CGRect(
                origin: .zero,
                size: Self.preferredSize(
                    for: item,
                    image: initialImage,
                    additionalHorizontalPadding: systemItemHorizontalPadding
                )
            )
        )
        unregisterDraggedTypes()

        self.isOwnerUnresponsive = Bridging.isProcessUnresponsive(item.ownerPID)

        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        isEnabled = LayoutBarPaddingView.acceptsLayoutDrag(of: item) &&
            item.isMovable(experimentalSystemItemHiding: experimentalSystemItemHiding)

        configureAccessibility()
        configureObservations()
    }

    /// Re-points a recycled view at a refreshed item. A refresh can hand back the
    /// same canonical item under a new uniqueIdentifier, so init's work repeats.
    func adopt(item: MenuBarItem, appState: AppState) {
        // configureObservations() cancels each task inline but only once it holds
        // an appState, so cancel up front in case the rebuild below bails.
        imageObservationTask?.cancel()
        brightnessObservationTask?.cancel()
        alwaysUseAppIconObservationTask?.cancel()
        systemItemHidingObservationTask?.cancel()
        thawIconObservationTask?.cancel()

        self.item = item

        placeholderImage = Self.makePlaceholderImage(for: item, appState: appState)
        if item.tag.matchesVisibleControlItem {
            livePlaceholderImage = placeholderImage
        } else {
            livePlaceholderImage = nil
        }

        cachedImage = appState.imageCache.image(for: item.tag)

        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        isEnabled = LayoutBarPaddingView.acceptsLayoutDrag(of: item) &&
            item.isMovable(experimentalSystemItemHiding: experimentalSystemItemHiding)

        tooltipController.text = tooltipText

        configureAccessibility()
        configureObservations()
    }

    // MARK: - Accessibility

    /// VoiceOver press and Show Menu expose inspector and context actions without a pointer.
    /// Custom section moves provide an alternative to dragging.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // The section is read from the container, so it is only known here.
        configureAccessibility()
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayName)
        // Which section the tile sits in is what the editor is for, and it is
        // otherwise only shown by position.
        if let section = (superview as? LayoutBarContainer)?.section {
            setAccessibilityValue(section.displayString)
        }
        setAccessibilityEnabled(true)
        guard isEnabled, let appState else {
            setAccessibilityCustomActions(nil)
            return
        }
        let item = item
        let current = appState.menuBarManager.sectionController.section(for: item)
        // Left/right nudges are the keyboard's answer to dragging inside a
        // section; the section moves below mirror the menu's own destinations.
        var actions: [NSAccessibilityCustomAction] = [
            NSAccessibilityCustomAction(name: String(localized: "Move left")) { [weak self] in
                guard let self else { return false }
                LayoutBarKeyboard.moveWithinSection(self, direction: .left)
                return true
            },
            NSAccessibilityCustomAction(name: String(localized: "Move right")) { [weak self] in
                guard let self else { return false }
                LayoutBarKeyboard.moveWithinSection(self, direction: .right)
                return true
            },
        ]
        actions.append(contentsOf: MenuBarSearchItemActions.moveDestinations(appState: appState).compactMap { name in
            guard let name, name != current else { return nil }
            return NSAccessibilityCustomAction(
                name: String(localized: "Move to \(MenuBarSearchItemActions.title(for: name))")
            ) { [weak appState] in
                guard let appState else { return false }
                MenuBarSearchItemActions.move(item, to: name, appState: appState)
                return true
            }
        })
        setAccessibilityCustomActions(actions)
    }

    override func accessibilityPerformPress() -> Bool {
        showInspector()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        closeInspector()
        showItemMenu()
        return true
    }

    /// Lets LayoutBarKeyboard activate the inspector without exposing its private implementation.
    func activateFromKeyboard() {
        showInspector()
    }

    /// Keyboard menu activation releases tooltip, inspector, and spotlight just like right-click.
    func showMenuFromKeyboard() {
        tooltipController.cancel()
        closeInspector()
        endSpotlight()
        showItemMenu()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var tooltipDelay: TimeInterval {
        appState?.settings.advanced.tooltipDelay ?? 0.5
    }

    private var desiredSystemItemHorizontalPadding: CGFloat {
        Metrics.defaultSystemItemHorizontalPadding + CGFloat(appState?.spacingManager.offset ?? 0)
    }

    /// Match MenuBarItemContainer's sampled background, including tint, for consistent preview ink.
    private var menuBarForegroundColor: NSColor {
        guard let appState else {
            return .white
        }
        return Self.menuBarForegroundColor(appState: appState)
    }

    static func menuBarForegroundColor(appState: AppState) -> NSColor {
        MenuBarStyleTint.prefersDarkInk(
            appState.menuBarManager.averageColorInfo,
            tintedBy: appState.appearanceManager.configuration.current,
            screen: nil
        ) ? .black : .white
    }

    override func draggingImage() -> NSImage? {
        // Drag start has no mouseExited; close the inspector first, then release its shared spotlight.
        closeInspector()
        endSpotlight()
        if shouldPreferPlaceholderImage {
            return placeholderBitmapImage()
        }
        // Build on drag start because init does not fire didSet, leaving cachedDrawImage nil until the first update.
        let dragImage = cachedImage.map {
            NSImage(cgImage: $0.cgImage, size: $0.pointSize)
        }
        return dragImage ?? placeholderBitmapImage()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tooltipTrackingArea {
            removeTrackingArea(tooltipTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tooltipTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        tooltipController.scheduleShow(delay: tooltipDelay)
        scheduleSpotlight()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        tooltipController.cancel()
        // Keep the real item lit while its inspector is open, the pointer has
        // to leave this view to reach the popover's controls.
        guard !isInspecting else {
            return
        }
        endSpotlight()
    }

    /// Claim mouse-down without forwarding to the unused padding responder.
    /// AppKit still sends drag/up to the hit view, regardless of which responder handled down.
    override func mouseDown(with _: NSEvent) {
        tooltipController.cancel()
        // Focusing on click keeps the keyboard path continuous: having reached
        // a glyph with the pointer, the arrow keys act on that same glyph.
        _ = window?.makeFirstResponder(self)
        isClickCandidate = true
        didRefuseDrag = false
    }

    /// Opens the inspector for a mouse-up that never turned into a drag.
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard isClickCandidate else {
            return
        }
        isClickCandidate = false
        showInspector()
    }

    // MARK: - Item spotlight

    /// The AX-title key the spotlight seam expects, or nil for items the
    /// agent cannot address: untitled windows and Thaw's own control items.
    private var spotlightName: String? {
        guard !item.isControlItem, let title = item.title, !title.isEmpty else {
            return nil
        }
        return title
    }

    /// Asks the platform backend to light up the real item after a short
    /// hover-intent delay. Canceled by endSpotlight().
    private func scheduleSpotlight() {
        guard let name = spotlightName,
              let spotlighting = MenuBarPresentationProvider.itemSpotlighting,
              spotlighting.isSupported
        else {
            return
        }
        spotlightTask?.cancel()
        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let landed = await spotlighting.setItemSpotlighted(true, forItemNamed: name)
            guard let self, !Task.isCancelled else {
                // The pointer left while the agent was answering; pair the
                // true with its false rather than leaving the item lit.
                if landed {
                    Task { await spotlighting.setItemSpotlighted(false, forItemNamed: name) }
                }
                return
            }
            isSpotlighted = landed
        }
    }

    /// Pair each landed spotlight with release on hover exit, drag start, menu opening, or deinit.
    private func endSpotlight() {
        spotlightTask?.cancel()
        spotlightTask = nil
        guard isSpotlighted, let name = spotlightName,
              let spotlighting = MenuBarPresentationProvider.itemSpotlighting
        else {
            return
        }
        isSpotlighted = false
        Task { await spotlighting.setItemSpotlighted(false, forItemNamed: name) }
    }

    // MARK: - Inspector

    /// Anchor to the glyph and hold the real item's spotlight for the inspector's lifetime.
    /// Freeze recycling to protect the anchor during renames; group edits dismiss because the frozen bar cannot reflect them.
    private func showInspector() {
        guard inspectorPopover == nil,
              let container = superview as? LayoutBarContainer,
              let appState = container.appState,
              window != nil
        else {
            return
        }

        let popover = NSPopover()
        // Transient dismissal on any outside click also commits the rename.
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSApp.effectiveAppearance

        let controller = NSHostingController(
            rootView: LayoutBarItemInspector(
                item: item,
                section: container.section,
                orderedItems: container.orderedItemsForMenu(),
                appState: appState,
                onShowAllActions: { [weak self] in
                    // Close first so the popover cannot swallow the menu's dismissal click.
                    self?.closeInspector()
                    self?.showItemMenu()
                }
            )
        )
        // Let SwiftUI size the changing group-action stack to avoid clipping or dead space.
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller

        inspectorPopover = popover
        isInspecting = true
        container.acceptsViewUpdates = false

        // .minY is below this unflipped glyph, keeping the strip and edited item visible above the popover.
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        // The rename field is focused on appear, which only takes effect once
        // the popover's window can accept key input.
        popover.contentViewController?.view.window?.makeKey()

        // Hover already scheduled a spotlight in the common case; re-arm only
        // when none landed, so the agent still receives one true per false.
        if !isSpotlighted {
            scheduleSpotlight()
        }
    }

    /// Closes the inspector and releases everything it was holding: the frozen
    /// container, the spotlight, and the popover itself.
    private func closeInspector() {
        guard let popover = inspectorPopover else {
            return
        }
        inspectorPopover = nil
        popover.performClose(nil)
        releaseInspectorHolds()
    }

    /// Release holds from both programmatic and transient dismissal, which bypasses closeInspector().
    private func releaseInspectorHolds() {
        guard isInspecting else {
            return
        }
        isInspecting = false
        endSpotlight()
        // Thawing the container rebuilds its arranged views, which may
        // deallocate this very view; hop off the current call stack first.
        let container = superview as? LayoutBarContainer
        Task { @MainActor in
            container?.acceptsViewUpdates = true
        }
    }

    /// Right-click group editing avoids interfering with drag detection; the inspector's "All Actions…" routes here too.
    override func rightMouseDown(with event: NSEvent) {
        tooltipController.cancel()
        closeInspector()
        endSpotlight()
        showItemMenu(fallbackEvent: event)
    }

    /// Container-supplied section concealing this Visible item along with an app sibling; drives the tooltip.
    var hiddenWithAppSection: MenuBarSection.Name? {
        didSet {
            guard oldValue != hiddenWithAppSection else { return }
            tooltipController.text = tooltipText
        }
    }

    private var tooltipText: String {
        guard hiddenWithAppSection != nil else { return item.displayName }
        return String(localized: "\(item.displayName) is not in the menu bar. macOS hides this app as a whole, and another of its items is hidden. Right-click to move them together.")
    }

    private func showItemMenu(fallbackEvent: NSEvent? = nil) {
        guard let container = superview as? LayoutBarContainer,
              let appState = container.appState,
              let menu = LayoutBarItemMenu.menu(
                  subject: .item(item),
                  section: container.section,
                  orderedItems: container.orderedItemsForMenu(),
                  appState: appState,
                  // The inspector focuses its name field when it opens.
                  onRename: { [weak self] in self?.showInspector() }
              )
        else {
            if let fallbackEvent {
                super.rightMouseDown(with: fallbackEvent)
            }
            return
        }
        // Retain the anchor during popUp's nested loop because deferred container thaw can recycle this view.
        _ = withExtendedLifetime(self) {
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.maxY), in: self)
        }
    }

    private func configureObservations() {
        if let appState {
            // Hold this item's slot so one animated glyph does not wake every editor tile.
            imageObservationTask?.cancel()
            imageObservationTask = Task { @MainActor [weak self, slot = appState.imageCache.glyphSlot(for: item.tag)] in
                let changes = Observations { slot.capture }
                for await image in changes {
                    guard let self else { return }
                    cachedImage = image
                }
            }

            // Observations emits the current preference first; manually deduplicate subsequent values.
            let advancedSettings = appState.settings.advanced
            alwaysUseAppIconObservationTask?.cancel()
            alwaysUseAppIconObservationTask = Task { @MainActor [weak self] in
                var previous: Bool?
                let changes = Observations { advancedSettings.alwaysUseAppIconForMenuBarItems }
                for await alwaysUseAppIcon in changes {
                    guard let self else { return }
                    guard previous != alwaysUseAppIcon else { continue }
                    previous = alwaysUseAppIcon
                    let oldSize = frame.size
                    let newSize = preferredSizeForCurrentDisplayMode(cachedImage)
                    setFrameSize(newSize)
                    if oldSize != newSize {
                        (superview as? LayoutBarContainer)?.itemPreferredSizeDidChange(self)
                    }
                    needsDisplay = true
                }
            }

            // Observe system-item hiding so draggability follows setting changes and corrects init before preferences load.
            systemItemHidingObservationTask?.cancel()
            systemItemHidingObservationTask = Task { @MainActor [weak self] in
                var previous: Bool?
                let changes = Observations { advancedSettings.enableExperimentalSystemItemHiding }
                for await enabled in changes {
                    guard let self else { return }
                    guard previous != enabled else { continue }
                    previous = enabled
                    self.isEnabled = LayoutBarPaddingView.acceptsLayoutDrag(of: self.item) &&
                        self.item.isMovable(experimentalSystemItemHiding: enabled)
                    self.configureAccessibility()
                    self.needsDisplay = true
                }
            }

            // MenuBarManager is @Observable; only brightness flips matter,
            // so the derived flag is deduped by hand.
            brightnessObservationTask?.cancel()
            brightnessObservationTask = Task { @MainActor [weak self, menuBarManager = appState.menuBarManager, appearanceManager = appState.appearanceManager] in
                // Tint can change ink preference even when the sampled background is unchanged.
                let changes = Observations {
                    MenuBarStyleTint.prefersDarkInk(
                        menuBarManager.averageColorInfo,
                        tintedBy: appearanceManager.configuration.current,
                        screen: nil
                    )
                }
                var previous: Bool?
                for await isBright in changes {
                    guard let self else { return }
                    guard isBright != previous else { continue }
                    previous = isBright
                    tintedImageCache.removeAll()
                    needsDisplay = true
                }
            }

            if item.tag.matchesVisibleControlItem,
               let controlItem = appState.menuBarManager.section(withName: .visible)?.controlItem
            {
                // Observe GeneralSettings separately from the control item's Combine state.
                controlItemStateSubscription?.cancel()
                controlItemStateSubscription = controlItem.$state
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else { return }
                        refreshLivePlaceholderImage()
                        needsDisplay = true
                    }

                let generalSettings = appState.settings.general
                thawIconObservationTask?.cancel()
                thawIconObservationTask = Task { @MainActor [weak self] in
                    let changes = Observations {
                        (generalSettings.thawIcon, generalSettings.customThawIconIsTemplate)
                    }
                    for await _ in changes {
                        guard let self else { return }
                        refreshLivePlaceholderImage()
                        needsDisplay = true
                    }
                }
            }
        }
    }

    override func draw(_: NSRect) {
        guard !isDraggingPlaceholder else {
            return
        }
        if shouldPreferPlaceholderImage {
            drawOverflowFallback()
        } else if let capturedImage = cachedDrawImage {
            capturedImage.draw(
                in: capturedImageDrawRect(for: capturedImage),
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : 0.67
            )
        } else {
            drawPlaceholder()
        }
        if isOwnerUnresponsive {
            drawWarningBadge(atLeadingEdge: false)
        }
        if visibilityLimit != nil {
            drawWarningBadge(atLeadingEdge: true)
        }
    }

    /// Draws the warning badge into the view's bottom-right corner (bottom-left
    /// for a visibility limit), scaled to Metrics.unresponsiveBadgeWidth.
    private func drawWarningBadge(atLeadingEdge: Bool) {
        let badge = NSImage.warning
        let badgeWidth = Metrics.unresponsiveBadgeWidth
        let badgeSize = CGSize(width: badgeWidth, height: badge.size.height * (badgeWidth / badge.size.width))
        let originX = atLeadingEdge ? bounds.minX : bounds.maxX - badgeSize.width
        badge.draw(in: CGRect(x: originX, y: bounds.minY, width: badgeSize.width, height: badgeSize.height))
    }

    private var shouldPreferPlaceholderImage: Bool {
        guard let appState, let section = (superview as? LayoutBarContainer)?.section else {
            return false
        }
        return Self.prefersFallback(
            for: item,
            in: section,
            appState: appState,
            capture: appState.imageCache.image(for: item.tag)
        )
    }

    /// Oversized or transparent captures use an app icon while replaced, avoiding stretched Finder menus or empty tiles.
    static func prefersFallback(
        for item: MenuBarItem,
        in section: MenuBarSection.Name,
        appState: AppState,
        capture: MenuBarItemGlyphCapture?
    ) -> Bool {
        OverflowFallbackIcon.shouldPreferAppIcon(
            for: item,
            in: section,
            appState: appState,
            hasUsableCapture: OverflowFallbackIcon.isUsableCapture(capture, for: item)
        )
    }

    /// macOS 27 native hiding or incomplete crops may need an app icon, then a box if no icon resolves; see OverflowFallbackIcon.
    private func drawOverflowFallback() {
        guard
            let appState,
            let icon = OverflowFallbackIcon.preferredImage(for: item, appState: appState)
        else {
            drawPlaceholder()
            return
        }
        let iconRect = Self.overflowFallbackDrawRect(
            for: item,
            imageSize: icon.size,
            bounds: bounds
        )
        guard !iconRect.isEmpty else { return }
        draw(
            icon,
            in: iconRect,
            fraction: isEnabled ? 1.0 : 0.5,
            templateTint: menuBarForegroundColor
        )
    }

    /// App icons fill the available square, but Thaw's own control-item image
    /// must match the native size used by its real status-item button.
    static func overflowFallbackDrawRect(
        for item: MenuBarItem,
        imageSize: CGSize,
        bounds: CGRect
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        if item.tag.matchesVisibleControlItem, imageSize.width > 0, imageSize.height > 0 {
            let scale = min(
                1,
                bounds.width / imageSize.width,
                bounds.height / imageSize.height
            )
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(
                x: bounds.midX - (size.width / 2),
                y: bounds.midY - (size.height / 2),
                width: size.width,
                height: size.height
            )
        }

        let side = min(bounds.width, bounds.height)
        return CGRect(
            x: bounds.midX - (side / 2),
            y: bounds.midY - (side / 2),
            width: side,
            height: side
        )
    }

    /// Shares capture, fallback, and system-padding rules with external previews to avoid a drifting second pipeline.
    /// Captures retain their colors; template fallbacks use editor tint.
    static func renderedTile(
        for item: MenuBarItem,
        in section: MenuBarSection.Name,
        appState: AppState
    ) -> NSImage {
        let capture = appState.imageCache.image(for: item.tag)
        let prefersFallback = prefersFallback(
            for: item,
            in: section,
            appState: appState,
            capture: capture
        )
        let tileCapture = prefersFallback ? nil : capture
        let padding = systemItemHorizontalPadding(
            for: item,
            image: tileCapture,
            desiredPadding: Metrics.defaultSystemItemHorizontalPadding + CGFloat(appState.spacingManager.offset)
        )
        let size = preferredSize(for: item, image: tileCapture, additionalHorizontalPadding: padding)
        let fallbackIcon = tileCapture == nil
            ? OverflowFallbackIcon.preferredImage(for: item, appState: appState)
            : nil

        // Rendered to a bitmap at the capture's own scale, so the tile keeps
        // every pixel of the capture wherever it is shown.
        let scale = tileCapture?.scale ?? NSScreen.main?.backingScaleFactor ?? 2
        let tile = NSImage(size: size)
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded(.up)),
            pixelsHigh: Int((size.height * scale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            // Set point size before context creation, which reads the rep's scale; pixel sizing would draw half-size icons.
            rep.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return tile }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            let bounds = CGRect(origin: .zero, size: size)
            if let tileCapture {
                let image = NSImage(cgImage: tileCapture.cgImage, size: tileCapture.pointSize)
                image.draw(
                    in: capturedImageDrawRect(imageSize: image.size, in: bounds),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            } else if let fallbackIcon {
                let rect = overflowFallbackDrawRect(for: item, imageSize: fallbackIcon.size, bounds: bounds)
                let drawn = fallbackIcon.isTemplate
                    ? fallbackIcon.tinted(with: menuBarForegroundColor(appState: appState))
                    : fallbackIcon
                drawn.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
            tile.addRepresentation(rep)
        }
        return tile
    }

    private func refuseDrag(_ refusal: LayoutBarFeedbackCenter.Refusal) {
        guard !didRefuseDrag else {
            return
        }
        didRefuseDrag = true
        appState?.layoutFeedback.post(refusal)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        tooltipController.cancel()
        // Any movement disqualifies the gesture from being a click, including
        // the movement that ends in one of the refusals below.
        isClickCandidate = false

        guard isEnabled else {
            refuseDrag(LayoutBarFeedbackCenter.itemNotMovable(itemName: item.displayName))
            return
        }

        // Accept one poll interval of staleness rather than paying process IPC on every dragged pixel.
        guard !isOwnerUnresponsive else {
            refuseDrag(LayoutBarFeedbackCenter.ownerUnresponsive(itemName: item.displayName))
            return
        }

        // The pasteboard payload is an empty marker; the drag is tracked
        // entirely in-process through its type alone.
        let marker = NSPasteboardItem()
        marker.setData(Data(), forType: .layoutBarItem)

        let drag = NSDraggingItem(pasteboardWriter: marker)
        drag.setDraggingFrame(bounds, contents: draggingImage())

        beginDraggingSession(with: [drag], event: event, source: self)
    }

    private func preferredSize(for image: MenuBarItemGlyphCapture?) -> CGSize {
        Self.preferredSize(
            for: item,
            image: image,
            additionalHorizontalPadding: systemItemHorizontalPadding
        )
    }

    private func preferredSizeForCurrentDisplayMode(_ image: MenuBarItemGlyphCapture?) -> CGSize {
        preferredSize(for: shouldPreferPlaceholderImage ? nil : image)
    }

    private static func preferredSize(
        for item: MenuBarItem,
        image: MenuBarItemGlyphCapture?,
        additionalHorizontalPadding: CGFloat = 0
    ) -> CGSize {
        if let image {
            // Clamp so a poisoned near-full-bar crop cannot dominate the
            // Visible layout strip (Finder menu chrome spanning the row).
            let width = image.pointSize.width.clamped(to: Metrics.minWidth ... Metrics.maxWidth)
            let height = max(image.pointSize.height, Metrics.minHeight)
            return CGSize(width: width + additionalHorizontalPadding, height: height)
        }

        let width = item.bounds.width.clamped(to: Metrics.minWidth ... Metrics.fallbackMaxWidth)
        let height = max(item.bounds.height, Metrics.minHeight)
        return CGSize(width: width, height: height)
    }

    /// Add only missing system-host padding in the editor; cached captures remain exact menu bar crops.
    static func systemItemHorizontalPadding(
        for item: MenuBarItem,
        image: MenuBarItemGlyphCapture?,
        desiredPadding: CGFloat
    ) -> CGFloat {
        guard OverflowFallbackIcon.usesCapturedSystemPreview(item),
              let image,
              desiredPadding > 0,
              let trimmed = image.cgImage.trimmingTransparency(
                  around: [.minXEdge, .maxXEdge],
                  alphaThreshold: 0.05
              )
        else {
            return 0
        }

        let contentWidth = CGFloat(trimmed.width) / image.scale
        let capturedPadding = max(0, image.pointSize.width - contentWidth)
        return max(0, desiredPadding - capturedPadding)
    }

    /// Centers a capture at its natural size inside the padded tile instead of
    /// stretching the glyph and its existing transparent margins edge-to-edge.
    private func capturedImageDrawRect(for image: NSImage) -> CGRect {
        Self.capturedImageDrawRect(imageSize: image.size, in: bounds)
    }

    private static func capturedImageDrawRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(
            1,
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - (size.width / 2),
            y: bounds.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private static func makePlaceholderImage(for item: MenuBarItem, appState: AppState) -> NSImage? {
        if let icon = OverflowFallbackIcon.selectedThawIcon(for: item, appState: appState) {
            return icon
        }
        return NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: item.displayName
        )
    }

    private func drawPlaceholder() {
        let placeholderRect = bounds.insetBy(
            dx: Metrics.placeholderHorizontalInset,
            dy: Metrics.placeholderVerticalInset
        )
        let backgroundPath = NSBezierPath(
            roundedRect: placeholderRect,
            xRadius: Metrics.placeholderCornerRadius,
            yRadius: Metrics.placeholderCornerRadius
        )
        NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
        backgroundPath.fill()

        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        guard let image = resolvedPlaceholderImage() else {
            return
        }

        let iconBounds = placeholderRect.insetBy(
            dx: Metrics.iconInset,
            dy: Metrics.iconInset
        )
        let iconSide = min(iconBounds.width, iconBounds.height)
        guard iconSide > 0 else {
            return
        }

        let iconRect = CGRect(
            x: placeholderRect.midX - (iconSide / 2),
            y: placeholderRect.midY - (iconSide / 2),
            width: iconSide,
            height: iconSide
        )

        draw(
            image,
            in: iconRect,
            fraction: isEnabled ? (image.isTemplate ? 0.8 : 0.9) : 0.5,
            templateTint: item.tag.matchesVisibleControlItem ? menuBarForegroundColor : .secondaryLabelColor
        )
    }

    private func draw(
        _ image: NSImage,
        in rect: CGRect,
        fraction: CGFloat,
        templateTint: NSColor
    ) {
        let displayImage = image.isTemplate ? tintedImage(for: image, tint: templateTint) : image
        displayImage.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: fraction
        )
    }

    private func tintedImage(for image: NSImage, tint: NSColor) -> NSImage {
        let key = ObjectIdentifier(image)
        if let cached = tintedImageCache[key]?[tint] {
            return cached
        }
        let tinted = image.tinted(with: tint)
        tintedImageCache[key, default: [:]][tint] = tinted
        return tinted
    }

    private func refreshLivePlaceholderImage() {
        guard item.tag.matchesVisibleControlItem, let appState else { return }
        livePlaceholderImage = Self.makePlaceholderImage(for: item, appState: appState)
    }

    private func resolvedPlaceholderImage() -> NSImage? {
        if item.tag.matchesVisibleControlItem {
            return livePlaceholderImage ?? placeholderImage
        }
        return placeholderImage
    }

    private func placeholderBitmapImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: LayoutBarItemView: NSPopoverDelegate

extension LayoutBarItemView: NSPopoverDelegate {
    /// Transient dismissal bypasses closeInspector(), so release spotlight and container holds here too; both paths are idempotent.
    func popoverDidClose(_: Notification) {
        inspectorPopover = nil
        releaseInspectorHolds()
    }
}

// MARK: Layout Bar Item Pasteboard Type

extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}

private extension NSImage {
    /// Resolves a template image into a concrete color for direct AppKit
    /// drawing, matching the automatic tinting performed by an NSStatusItem.
    func tinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
