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
    /// Kept separately because a drag cancelled before `oldContainerInfo` is
    /// set would leave the source frozen forever.
    private weak var frozenSourceContainer: LayoutBarContainer?

    /// A Boolean value that indicates whether the view is currently inside a container.
    var hasContainer = false

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

    /// The original row must stay frozen, or a cache refresh inserts a
    /// duplicate view behind the drag.
    func beganDragging(in container: LayoutBarContainer) -> Bool {
        frozenSourceContainer === container
    }

    /// A row stays frozen while a move is verified; a new drag from it would
    /// be reconciled underneath.
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
            // A quick cross-row drag can land before draggingUpdated sets
            // this, leaving the source frozen.
            oldContainerInfo = (container, sourceIndex)
        }

        session.animatesToStartingPositionsOnCancelOrFail = false

        // Synchronous, so a short drag can't end before a queued task sets it.
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

        // Cancelled drops start no move. Put the view back before thawing, or
        // the source rebuilds a replacement and the drag view lands beside it.
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
