//
//  LayoutBarScrollView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Cocoa

final class LayoutBarScrollView: NSScrollView {
    private let paddingView: LayoutBarPaddingView

    /// The pane's selection, shared by every section's bar.
    let selection: LayoutSelectionModel?

    private(set) var selectionInteraction: LayoutSelectionInteraction?

    /// Whether this section takes the selection being dragged over it, read once as the drag enters.
    private var takesDraggedSelection = false

    /// Redraws the bar's items when the selection changes.
    private var selectionObservation: Task<Void, Never>?

    /// Laid out left to right in array order.
    var arrangedViews: [LayoutBarArrangedView] {
        get { paddingView.arrangedViews }
        set { paddingView.arrangedViews = newValue }
    }

    /// The bar's item container, which the padding view wraps.
    private var container: LayoutBarContainer? {
        paddingView.subviews.firstNonNil { $0 as? LayoutBarContainer }
    }

    /// Creates a layout bar scroll view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    ///   - selection: The pane's selection, shared by every section's bar.
    ///   - wrapsRows: Whether items wrap onto as many rows as the width needs, rather than scroll.
    init(
        appState: AppState,
        section: MenuBarSection.Name,
        selection: LayoutSelectionModel? = nil,
        wrapsRows: Bool = false
    ) {
        self.paddingView = LayoutBarPaddingView(appState: appState, section: section, wrapsRows: wrapsRows)
        self.selection = selection

        super.init(frame: .zero)

        self.documentView = paddingView
        self.hasHorizontalScroller = !wrapsRows
        self.hasVerticalScroller = false
        self.verticalScrollElasticity = .none
        self.autohidesScrollers = true
        self.drawsBackground = false
        self.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paddingView.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            wrapsRows
                ? paddingView.widthAnchor.constraint(equalTo: contentView.widthAnchor)
                : paddingView.widthAnchor.constraint(greaterThanOrEqualTo: contentView.widthAnchor),
            paddingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        if wrapsRows {
            // Narrow until the first layout, so the items' single row never sets the bar's width.
            paddingView.container.rowWidth = 1
            setContentHuggingPriority(.required, for: .vertical)
            setContentCompressionResistancePriority(.required, for: .vertical)
        }

        if let selection {
            selectionInteraction = LayoutSelectionInteraction(scrollView: self, selection: selection)
            registerForDraggedTypes([.layoutBarSelection])
            selectionObservation = Task { @MainActor [weak self] in
                for await _ in Observations({ selection.selection }) {
                    self?.showSelection()
                }
            }
        }
    }

    isolated deinit {
        selectionObservation?.cancel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The clip view takes its width here, before the bar's items lay out, so rows follow it in the same pass.
    override func tile() {
        super.tile()
        paddingView.wrapRows(toWidth: contentView.frame.width)
    }

    /// A bar that wraps is as tall as its rows; one that scrolls takes the height it is given.
    override var intrinsicContentSize: NSSize {
        guard paddingView.wrapsRows else { return super.intrinsicContentSize }
        return NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    /// The single-row bar's height, which a wrapped bar of one row keeps.
    static let barHeight: CGFloat = 48

    /// The bar's height at a width, from its items before it lays out there.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard paddingView.wrapsRows else { return Self.barHeight }
        let items = paddingView.wrappedItemsHeight(width: width)
        // One row keeps the single-row bar's 12pt above and below its items.
        return max(Self.barHeight, items + (Self.barHeight - Self.rowItemHeight))
    }

    /// An item's height on the bar, which barHeight frames.
    private static let rowItemHeight: CGFloat = 24

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        selectionInteraction?.windowDidChange(window)
    }

    private func showSelection() {
        for case let view as LayoutBarItemView in arrangedViews {
            view.needsDisplay = true
            NSAccessibility.post(element: view, notification: .valueChanged)
        }
        revealAnchor()
    }

    /// Room left beside a revealed item, so its neighbours show which way the bar continues.
    static let revealMargin: CGFloat = 24

    /// Scrolls the item the selection works from into view when this bar holds it,
    /// so an item picked in the list or reached by the keyboard is never off screen.
    func revealAnchor() {
        guard let anchorID = selection?.anchorItemID, let documentView, let view = arrangedViews.lazy
            .compactMap({ $0 as? LayoutBarItemView })
            .first(where: { $0.item.uniqueIdentifier == anchorID })
        else { return }
        guard !paddingView.wrapsRows else {
            // Every row shows, so only the pane around the bars may need to scroll, down to the item's row.
            view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -Self.revealMargin / 2))
            return
        }
        // In the clip view's space, where its bounds are what shows and the document's frame is what can.
        let target = contentView.convert(view.bounds, from: view)
        guard let originX = Self.revealOriginX(
            for: target.insetBy(dx: -Self.revealMargin, dy: 0),
            visible: contentView.bounds,
            document: documentView.frame
        ) else { return }
        // Only this bar scrolls; scrollToVisible would also scroll the page around it.
        contentView.scroll(to: CGPoint(x: originX, y: contentView.bounds.minY))
        reflectScrolledClipView(contentView)
    }

    /// The clip origin that shows target, or nil when it already shows. Kept inside the document.
    static nonisolated func revealOriginX(for target: CGRect, visible: CGRect, document: CGRect) -> CGFloat? {
        let originX: CGFloat
        if target.width >= visible.width || target.minX < visible.minX {
            originX = target.minX
        } else if target.maxX > visible.maxX {
            originX = target.maxX - visible.width
        } else {
            return nil
        }
        let clamped = min(max(originX, document.minX), max(document.minX, document.maxX - visible.width))
        return clamped == visible.minX ? nil : clamped
    }
}

extension LayoutBarScrollView {
    override func accessibilityChildren() -> [Any]? {
        return arrangedViews
    }
}

extension LayoutBarScrollView: NSDraggingSource {
    /// Starts a drag that carries every selected item in this bar, each image where its item sits.
    func beginSelectionDrag(from view: LayoutBarItemView, event: NSEvent) {
        let selected = arrangedViews.compactMap { $0 as? LayoutBarItemView }.filter(\.isLayoutSelected)
        let items = selected.map { member in
            let marker = NSPasteboardItem()
            marker.setData(Data(), forType: .layoutBarSelection)
            let item = NSDraggingItem(pasteboardWriter: marker)
            item.setDraggingFrame(view.convert(member.bounds, from: member), contents: member.draggingImage())
            return item
        }
        guard !items.isEmpty else { return }
        view.beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        takesDraggedSelection = sender.draggingSource is LayoutBarScrollView && container?.acceptsSelection() == true
        return selectionDragOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        selectionDragOperation(sender)
    }

    override func draggingExited(_: NSDraggingInfo?) {
        container?.groupDropMarkerX = nil
    }

    override func draggingEnded(_: NSDraggingInfo) {
        container?.groupDropMarkerX = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard takesDraggedSelection, let container else { return false }
        container.groupDropMarkerX = nil
        container.dropSelection(at: sender.draggingLocation)
        return true
    }

    /// Shows where the selection would land, or the no-drop cursor when this section cannot take all of it.
    private func selectionDragOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard takesDraggedSelection, let container else {
            container?.groupDropMarkerX = nil
            return []
        }
        container.showGroupDropMarker(at: sender.draggingLocation)
        return .move
    }
}

extension NSPasteboard.PasteboardType {
    /// A drag of the Layout pane's selection, tracked in-process through its type alone.
    static let layoutBarSelection = Self("\(Constants.bundleIdentifier).layout-bar-selection")
}
