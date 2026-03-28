//
//  LayoutBarItemView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: NSView {
    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// The item that the view represents.
    let item: MenuBarItem

    private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
    private var tooltipTrackingArea: NSTrackingArea?

    /// Temporary information that the item view retains when it is moved outside
    /// of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this property is set
    /// to hold the layout view's container view, as well as the index of the item
    /// view in relation to the container's other items. Upon being inserted into a
    /// new layout view, these values are removed. If the item is dropped outside of
    /// a layout view, these values are used to reinsert the item view in its original
    /// layout view.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// A Boolean value that indicates whether the item view is currently inside a container.
    var hasContainer = false

    /// The image displayed inside the view.
    private var cachedImage: MenuBarItemImageCache.CapturedImage? {
        didSet {
            if let image = cachedImage {
                setFrameSize(image.scaledSize)
            }
            // When nil, keep the current frame size (from item.bounds in init)
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the item view is a dragging placeholder.
    ///
    /// If this value is `true`, the item view does not draw its image.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the view is enabled.
    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState

        // set the frame to the full item frame size; the image will be centered when displayed
        super.init(frame: CGRect(origin: .zero, size: item.bounds.size))
        unregisterDraggedTypes()

        self.isEnabled = item.isMovable

        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var tooltipDelay: TimeInterval {
        appState?.settings.advanced.tooltipDelay ?? 0.5
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

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            let tag = item.tag
            let imageForTag = appState.imageCache.$images
                .map { images -> MenuBarItemImageCache.CapturedImage? in images[tag] }

            imageForTag
                .removeDuplicates(by: MenuBarItemImageCache.CapturedImage.isVisuallyEqual)
                .sink { [weak self] image in
                    guard let self else {
                        return
                    }
                    self.cachedImage = image
                }
                .store(in: &c)
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
            if let image = cachedImage?.nsImage {
                image.draw(
                    in: bounds,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: isEnabled ? 1.0 : 0.67
                )
            } else {
                drawPlaceholder()
            }
            if Bridging.isProcessUnresponsive(item.ownerPID) {
                let warningImage = NSImage.warning
                let width: CGFloat = 15
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

    private func drawPlaceholder() {
        let fraction: CGFloat = isEnabled ? 0.6 : 0.4
        NSColor.secondaryLabelColor.withAlphaComponent(fraction).setFill()
        let bgRect = bounds.insetBy(dx: 1, dy: bounds.height * 0.2)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3)
        path.fill()

        let name = item.displayName
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(fraction),
        ]
        let size = (name as NSString).size(withAttributes: attrs)
        let maxWidth = bgRect.width - 4
        let drawRect = CGRect(
            x: bgRect.midX - min(size.width, maxWidth) / 2,
            y: bgRect.midY - size.height / 2,
            width: min(size.width, maxWidth),
            height: size.height
        )
        (name as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
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

        // Data doesn't matter, but we do need to set the type.
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: cachedImage?.nsImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarItemView: NSDraggingSource

extension LayoutBarItemView: NSDraggingSource {
    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt _: NSPoint) {
        // make sure the container doesn't update its arranged views and that items
        // aren't arranged during a dragging session
        if let container = superview as? LayoutBarContainer {
            container.canSetArrangedViews = false
        }

        // prevent the dragging image from animating back to its original location
        session.animatesToStartingPositionsOnCancelOrFail = false

        // async to prevent the view from disappearing before the dragging image appears
        DispatchQueue.main.async {
            self.isDraggingPlaceholder = true
        }
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        defer {
            // always remove container info at the end of a session
            oldContainerInfo = nil
        }

        // since the session's `animatesToStartingPositionsOnCancelOrFail` property was
        // set to false when the session began (above), there is no delay between the user
        // releasing the dragging item and this method being called; thus, `isDraggingPlaceholder`
        // only needs to be updated here; if we ever decide we want animation, it may also
        // need to be updated inside `performDragOperation(_:)` on `LayoutBarPaddingView`
        isDraggingPlaceholder = false

        // if the drop occurs outside of a container, reinsert the view into its original
        // container at its original index
        if !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: index)
        }
    }
}

extension LayoutBarItemView: NSAccessibilityLayoutItem {}

// MARK: Layout Bar Item Pasteboard Type

extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}
