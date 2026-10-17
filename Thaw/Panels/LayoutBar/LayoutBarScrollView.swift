//
//  LayoutBarScrollView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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
        paddingView.subviews.lazy.compactMap { $0 as? LayoutBarContainer }.first
    }

    /// Creates a layout bar scroll view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    ///   - selection: The pane's selection, shared by every section's bar.
    init(appState: AppState, section: MenuBarSection.Name, selection: LayoutSelectionModel? = nil) {
        self.paddingView = LayoutBarPaddingView(appState: appState, section: section)
        self.selection = selection

        super.init(frame: .zero)

        self.documentView = paddingView
        self.hasHorizontalScroller = true
        self.hasVerticalScroller = false
        self.verticalScrollElasticity = .none
        self.autohidesScrollers = true
        self.drawsBackground = false
        self.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paddingView.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            paddingView.widthAnchor.constraint(greaterThanOrEqualTo: contentView.widthAnchor),
            paddingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        selectionInteraction?.windowDidChange(window)
    }

    private func showSelection() {
        for case let view as LayoutBarItemView in arrangedViews {
            view.needsDisplay = true
            NSAccessibility.post(element: view, notification: .valueChanged)
        }
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
