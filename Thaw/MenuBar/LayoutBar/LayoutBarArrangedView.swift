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
        case opaqueSlot(LayoutOpaqueSlotDescriptor)
        case newItemsBadge
    }

    /// Temporary information retained while dragging between layout containers.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// The container frozen at drag-start, captured so it can always be thawed
    /// when the drag ends. `superview` is unreliable for this (the view is pulled
    /// out of its container mid-drag) and `oldContainerInfo` is only set once the
    /// drag reaches the `.updated` phase, so neither alone guarantees a restore.
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

        session.animatesToStartingPositionsOnCancelOrFail = false

        Task { @MainActor in
            isDraggingPlaceholder = true
        }
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        let sourceContainer = oldContainerInfo?.container
        let frozenContainer = frozenSourceContainer
        defer {
            oldContainerInfo = nil
            frozenSourceContainer = nil
        }

        isDraggingPlaceholder = false

        // Successful drops reset this in `performDragOperation` (or the async
        // move Task it spawns). Cancelled or rejected drags never reach that
        // path, so restore updates here. Thaw every container this drag may have
        // frozen — including `frozenSourceContainer`, the origin captured at
        // willBeginAt — because `superview` is nil once the view is pulled out
        // mid-drag and `oldContainerInfo` is nil if the drag never updated, so
        // relying on either alone can leave the origin container permanently
        // frozen (its bar then stops refreshing and refuses further drags).
        if operation == [] {
            (superview as? LayoutBarContainer)?.canSetArrangedViews = true
            sourceContainer?.canSetArrangedViews = true
            frozenContainer?.canSetArrangedViews = true
        }

        if isNewItemsBadge {
            sourceContainer?.canSetArrangedViews = true
            if let appState = sourceContainer?.appState {
                sourceContainer?.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: sourceContainer?.section ?? .hidden))
            }
        }

        if !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: index)
        }
    }
}

extension LayoutBarArrangedView: @MainActor NSAccessibilityLayoutItem {}
