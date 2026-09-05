//
//  LayoutBarArrangedView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Shared base class for draggable views inside the layout bar editor.
class LayoutBarArrangedView: NSView {
    enum Kind {
        case item(MenuBarItem)
        case newItemsBadge
    }

    /// Temporary information retained while dragging between layout containers.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// The container frozen when the drag began.
    ///
    /// `oldContainerInfo` is populated only after a destination receives an
    /// update. A drag cancelled before that point would otherwise leave its
    /// source container frozen indefinitely, so retain the source separately
    /// for the lifetime of the dragging session.
    private weak var frozenSourceContainer: LayoutBarContainer?

    /// A Boolean value that indicates whether the view is currently inside a container.
    var hasContainer = false

    /// A Boolean value that indicates whether the view is enabled.
    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the view is acting as the drag placeholder.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// The average color info of the menu bar, used for adaptive coloring.
    var averageColorInfo: MenuBarAverageColorInfo? {
        didSet {
            needsDisplay = true
        }
    }

    var kind: Kind {
        fatalError("Subclasses must override kind")
    }

    var isNewItemsBadge: Bool {
        if case .newItemsBadge = kind {
            return true
        }
        return false
    }

    func draggingImage() -> NSImage? {
        nil
    }

    /// Whether this container is the row where the current drag began.
    /// Intermediate rows may thaw as soon as the pointer exits, but the
    /// original row must stay frozen so a cache refresh does not insert a
    /// duplicate view behind the drag.
    func beganDragging(in container: LayoutBarContainer) -> Bool {
        frozenSourceContainer === container
    }

    /// A row stays frozen while an asynchronous system move is being
    /// verified. Starting another drag from that row would let the older move
    /// thaw and reconcile it underneath the newer drag.
    var canBeginDraggingFromCurrentContainer: Bool {
        (superview as? LayoutBarContainer)?.canSetArrangedViews == true
    }
}

// MARK: LayoutBarArrangedView: NSDraggingSource

extension LayoutBarArrangedView: NSDraggingSource {
    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt _: NSPoint) {
        let container = superview as? LayoutBarContainer
        container?.canSetArrangedViews = false
        frozenSourceContainer = container
        if let container,
           let sourceIndex = container.arrangedViews.firstIndex(of: self)
        {
            // Record the source synchronously. A quick cross-row drag can
            // reach its destination before draggingUpdated gets a chance to
            // populate this, which otherwise leaves the real source frozen
            // and unavailable for final reconciliation.
            oldContainerInfo = (container, sourceIndex)
        }

        session.animatesToStartingPositionsOnCancelOrFail = false

        // This callback is already delivered on the main thread. Set the
        // placeholder synchronously so a short drag cannot end before a queued
        // task turns the placeholder back on.
        isDraggingPlaceholder = true
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        let sourceContainer = oldContainerInfo?.container
        let frozenContainer = frozenSourceContainer
        let currentContainer = superview as? LayoutBarContainer
        defer {
            oldContainerInfo = nil
            frozenSourceContainer = nil
        }

        isDraggingPlaceholder = false

        // Successful item drops keep both rows frozen until the asynchronous
        // system move settles. Cancelled and rejected drops never start that
        // task. Transfer the original view back before thawing either row;
        // otherwise the source rebuilds a replacement from the old cache and
        // the detached drag view is inserted beside it a moment later.
        if operation == [] {
            if let (container, index) = oldContainerInfo {
                container.restoreArrangedViewAfterCancelledDrag(
                    self,
                    from: currentContainer,
                    at: index
                )
            }

            // `frozenContainer` covers a cancellation that happened before
            // `oldContainerInfo` was populated.
            currentContainer?.resumeArrangedViewUpdatesWithoutAnimation()
            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
            frozenContainer?.resumeArrangedViewUpdatesWithoutAnimation()
        }

        if isNewItemsBadge {
            sourceContainer?.resumeArrangedViewUpdatesWithoutAnimation()
            if let appState = sourceContainer?.appState {
                sourceContainer?.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: sourceContainer?.section ?? .hidden))
            }
        }

        if operation != [], !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: index)
        }
    }
}

extension LayoutBarArrangedView: @MainActor NSAccessibilityLayoutItem {}
