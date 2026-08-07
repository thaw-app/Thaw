//
//  LayoutBarItemView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: LayoutBarArrangedView {
    private enum Metrics {
        static let minWidth: CGFloat = 14
        static let maxWidth: CGFloat = 240
        static let minHeight: CGFloat = 18
        static let placeholderCornerRadius: CGFloat = 6
        static let placeholderHorizontalInset: CGFloat = 2
        static let placeholderVerticalInset: CGFloat = 2
        static let iconInset: CGFloat = 2
        static let fallbackSymbolPointSize: CGFloat = 11
        static let unresponsiveBadgeWidth: CGFloat = 15
        static let defaultSystemItemHorizontalPadding: CGFloat = 16
    }

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// The item that the view represents.
    let item: MenuBarItem

    private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
    private var tooltipTrackingArea: NSTrackingArea?
    private let placeholderImage: NSImage?
    /// Refreshed when the visible-section control item's icon or state changes.
    private var livePlaceholderImage: NSImage?

    /// The image displayed inside the view.
    private var cachedImage: MenuBarItemImageCache.CapturedImage? {
        didSet {
            let previousSize = frame.size
            cachedDrawImage = cachedImage.map {
                NSImage(cgImage: $0.cgImage, size: $0.scaledSize)
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

    /// Stable `NSImage` wrapper for the current capture, rebuilt only when the
    /// cache entry changes. Avoids allocating a new AppKit image on every
    /// `draw(_:)` pass.
    private var cachedDrawImage: NSImage?

    /// Extra transparent width needed to match the system host item's native
    /// menu-bar selection padding. Applied only in the layout editor.
    private var systemItemHorizontalPadding: CGFloat = 0

    /// Cached result of `Bridging.isProcessUnresponsive(item.ownerPID)`,
    /// refreshed on a timer rather than on every `draw(_:)` pass, which can
    /// run at up to display refresh rate.
    private var isOwnerUnresponsive = false

    /// Tinted variants of template images passed to `draw(_:in:fraction:templateTint:)`,
    /// keyed by source image identity and tint color. Cleared whenever
    /// `menuBarForegroundColor` changes.
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

        configureCancellables()
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

    /// Matches the foreground selected by ``MenuBarItemContainer`` for the
    /// layout preview's sampled menu-bar background.
    private var menuBarForegroundColor: NSColor {
        appState?.menuBarManager.averageColorInfo?.isBright(for: nil) == true ? .black : .white
    }

    override func draggingImage() -> NSImage? {
        if shouldPreferPlaceholderImage {
            return placeholderBitmapImage()
        }
        return cachedImage?.nsImage ?? placeholderBitmapImage()
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
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        tooltipController.cancel()
    }

    /// Group editing lives on right-click: the view already owns `mouseDragged`
    /// and never handles `mouseDown`, so this is the one gesture available that
    /// cannot interfere with dragging.
    override func rightMouseDown(with event: NSEvent) {
        tooltipController.cancel()
        guard let container = superview as? LayoutBarContainer,
              let appState = container.appState,
              let menu = LayoutBarItemMenu.menu(
                  subject: .item(item),
                  section: container.section,
                  orderedItems: container.orderedItemsForMenu(),
                  appState: appState
              )
        else {
            super.rightMouseDown(with: event)
            return
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.maxY), in: self)
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            let tag = item.tag
            let imageForTag = appState.imageCache.$images
                .map { [weak appState] _ -> MenuBarItemImageCache.CapturedImage? in
                    appState?.imageCache.image(for: tag)
                }

            imageForTag
                .removeDuplicates(by: MenuBarItemImageCache.CapturedImage.isVisuallyEqual)
                .sink { [weak self] image in
                    guard let self else {
                        return
                    }
                    self.cachedImage = image
                }
                .store(in: &c)

            appState.settings.advanced.$alwaysUseAppIconForMenuBarItems
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }
                    let oldSize = frame.size
                    let newSize = preferredSizeForCurrentDisplayMode(cachedImage)
                    setFrameSize(newSize)
                    if oldSize != newSize {
                        (superview as? LayoutBarContainer)?.itemPreferredSizeDidChange(self)
                    }
                    needsDisplay = true
                }
                .store(in: &c)

            // Draggability of forced-visible system items (Clock, Control
            // Center, Siri, …) depends on this toggle, but `isEnabled` is read
            // once in init — so without this the view stays latched to whatever
            // the flag was when it was built (e.g. still off if the persisted
            // value hadn't loaded yet, or unchanged after the user flips it),
            // and the items can't be dragged even though the setting is on.
            // `@Published` re-emits the current value on subscribe, so this also
            // corrects the init-time latch.
            appState.settings.advanced.$enableExperimentalSystemItemHiding
                .removeDuplicates()
                .sink { [weak self] enabled in
                    guard let self else { return }
                    self.isEnabled = LayoutBarPaddingView.acceptsLayoutDrag(of: self.item) &&
                        self.item.isMovable(experimentalSystemItemHiding: enabled)
                    self.needsDisplay = true
                }
                .store(in: &c)

            appState.menuBarManager.$averageColorInfo
                .map { $0?.isBright(for: nil) == true }
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }
                    tintedImageCache.removeAll()
                    needsDisplay = true
                }
                .store(in: &c)

            Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    let unresponsive = Bridging.isProcessUnresponsive(item.ownerPID)
                    guard unresponsive != isOwnerUnresponsive else { return }
                    isOwnerUnresponsive = unresponsive
                    needsDisplay = true
                }
                .store(in: &c)

            if item.tag.matchesVisibleControlItem,
               let controlItem = appState.menuBarManager.section(withName: .visible)?.controlItem
            {
                controlItem.$state
                    .combineLatest(
                        appState.settings.general.$iceIcon,
                        appState.settings.general.$customIceIconIsTemplate
                    )
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.refreshLivePlaceholderImage()
                        self?.needsDisplay = true
                    }
                    .store(in: &c)
            }
        }

        cancellables = c
    }

    /// Provides an alert to display when the item view is disabled.
    func provideAlertForDisabledItem() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar item is not movable.")
        alert.informativeText = String(localized: "macOS prohibits \"\(item.displayName)\" from being moved.")
        return alert
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = provideAlertForDisabledItem()
        alert.informativeText = String(localized: "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved.")
        return alert
    }

    override func draw(_: NSRect) {
        if !isDraggingPlaceholder {
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
                let warningImage = NSImage.warning
                let width = Metrics.unresponsiveBadgeWidth
                let scale = width / warningImage.size.width
                let size = CGSize(
                    width: width,
                    height: warningImage.size.height * scale
                )
                warningImage.draw(
                    in: CGRect(
                        x: bounds.maxX - size.width,
                        y: bounds.minY,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    private var shouldPreferPlaceholderImage: Bool {
        guard let appState, let section = (superview as? LayoutBarContainer)?.section else {
            return false
        }
        // Oversized captures are almost always poisoned (near-full-bar / menu-chrome
        // crops). Prefer the app icon instead of stretching Finder menus across
        // the layout row while the image cache invalidates them.
        if let cachedDrawImage, cachedDrawImage.size.width > Metrics.maxWidth {
            return OverflowFallbackIcon.shouldPreferAppIcon(
                for: item,
                in: section,
                appState: appState,
                cachedImage: nil
            )
        }
        return OverflowFallbackIcon.shouldPreferAppIcon(
            for: item,
            in: section,
            appState: appState,
            cachedImage: cachedDrawImage
        )
    }

    /// Draws the owning app's icon when no usable capture exists (macOS 27
    /// incomplete hosting-window crops / native hide). Falls back to the
    /// generic box placeholder when no icon resolves. See
    /// ``OverflowFallbackIcon``.
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

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        tooltipController.cancel()

        guard isEnabled else {
            let alert = provideAlertForDisabledItem()
            alert.runModal()
            return
        }

        guard !Bridging.isProcessUnresponsive(item.ownerPID) else {
            let alert = provideAlertForUnresponsiveItem()
            alert.runModal()
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func preferredSize(for image: MenuBarItemImageCache.CapturedImage?) -> CGSize {
        Self.preferredSize(
            for: item,
            image: image,
            additionalHorizontalPadding: systemItemHorizontalPadding
        )
    }

    private func preferredSizeForCurrentDisplayMode(_ image: MenuBarItemImageCache.CapturedImage?) -> CGSize {
        preferredSize(for: shouldPreferPlaceholderImage ? nil : image)
    }

    private static func preferredSize(
        for item: MenuBarItem,
        image: MenuBarItemImageCache.CapturedImage?,
        additionalHorizontalPadding: CGFloat = 0
    ) -> CGSize {
        if let image {
            // Clamp so a poisoned near-full-bar crop cannot dominate the
            // Visible layout strip (Finder menu chrome spanning the row).
            let width = image.scaledSize.width.clamped(to: Metrics.minWidth ... Metrics.maxWidth)
            let height = max(image.scaledSize.height, Metrics.minHeight)
            return CGSize(width: width + additionalHorizontalPadding, height: height)
        }

        let width = item.bounds.width.clamped(to: Metrics.minWidth ... Metrics.maxWidth)
        let height = max(item.bounds.height, Metrics.minHeight)
        return CGSize(width: width, height: height)
    }

    /// Supplies only padding that is absent from a system-host capture. The
    /// image cache remains an exact crop of the real menu bar; this correction
    /// is presentation-only for the layout editor.
    static func systemItemHorizontalPadding(
        for item: MenuBarItem,
        image: MenuBarItemImageCache.CapturedImage?,
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
        let capturedPadding = max(0, image.scaledSize.width - contentWidth)
        return max(0, desiredPadding - capturedPadding)
    }

    /// Centers a capture at its natural size inside the padded tile instead of
    /// stretching the glyph and its existing transparent margins edge-to-edge.
    private func capturedImageDrawRect(for image: NSImage) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return bounds }
        let scale = min(
            1,
            bounds.width / image.size.width,
            bounds.height / image.size.height
        )
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
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

// MARK: Layout Bar Item Pasteboard Type

extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}

private extension NSImage {
    /// Resolves a template image into a concrete color for direct AppKit
    /// drawing, matching the automatic tinting performed by an NSStatusItem.
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        return image
    }
}
