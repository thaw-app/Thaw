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
        if let container = superview as? LayoutBarContainer {
            container.canSetArrangedViews = false
        }

        session.animatesToStartingPositionsOnCancelOrFail = false

        Task { @MainActor in
            isDraggingPlaceholder = true
        }
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        let sourceContainer = oldContainerInfo?.container
        defer {
            oldContainerInfo = nil
        }

        isDraggingPlaceholder = false

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

extension LayoutBarArrangedView: @preconcurrency NSAccessibilityLayoutItem {}
