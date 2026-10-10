//
//  LayoutBarArrangedView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Shared base class for draggable views inside the layout bar editor.
class LayoutBarArrangedView: NSView {
    enum Kind {
        case item(MenuBarItem)
        case opaqueSlot(LayoutOpaqueSlotDescriptor)
        case newItemsBadge
        /// Expand collapsed groups before persistence; index translation and layoutItemsForPersistence assume one view per item.
        case collapsedGroup(members: [MenuBarItem])
    }

    /// Temporary information retained while dragging between layout containers.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// Capture the frozen source at drag start: superview disappears mid-drag and oldContainerInfo may never be set.
    private weak var frozenSourceContainer: LayoutBarContainer?

    /// Record block size each updated phase so rejected group drags restore every member, not just self.
    var dragUnitCount = 1

    var hasContainer = false

    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

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
        container?.acceptsViewUpdates = false
        frozenSourceContainer = container

        session.animatesToStartingPositionsOnCancelOrFail = false

        Task { @MainActor in
            isDraggingPlaceholder = true
        }
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        let sourceContainer = oldContainerInfo?.container
        let frozenContainer = frozenSourceContainer
        let wasGroupDrag = dragUnitCount > 1
        defer {
            oldContainerInfo = nil
            frozenSourceContainer = nil
            dragUnitCount = 1
        }

        isDraggingPlaceholder = false

        // Failed drops never reach performDragOperation's thaw path; restore every potentially frozen container here.
        // The captured origin covers missing superview and oldContainerInfo, preventing permanently frozen layout bars.
        if operation == [] {
            (superview as? LayoutBarContainer)?.acceptsViewUpdates = true
            sourceContainer?.acceptsViewUpdates = true
            frozenContainer?.acceptsViewUpdates = true
        }

        if isNewItemsBadge {
            sourceContainer?.acceptsViewUpdates = true
            sourceContainer?.rebuildViews()
        }

        if !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.animatesNextLayoutPass = false
            if wasGroupDrag {
                // Only self carries oldContainerInfo; rebuild from the unchanged cache to restore all removed group members.
                if container.appState != nil {
                    container.rebuildViews()
                    return
                }
            }
            container.arrangedViews.insert(self, at: index)
        }
    }
}

extension LayoutBarArrangedView: @MainActor NSAccessibilityLayoutItem {}
