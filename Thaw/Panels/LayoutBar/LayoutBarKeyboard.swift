//
//  LayoutBarKeyboard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Keyboard moves share the drop/sort order-commit path and mirror VoiceOver custom actions.
@MainActor
enum LayoutBarKeyboard {
    enum MoveDirection: Equatable {
        case left
        case right
        case up
        case down
    }

    // MARK: Key handling

    /// Returns whether the key was consumed; callers pass unhandled keys to super to preserve AppKit behavior.
    static func handleKeyDown(_ event: NSEvent, in view: LayoutBarItemView) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = KeyCode(rawValue: Int(event.keyCode))
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let control = flags.contains(.control)

        if !command, !option, !control, key == .space || key == .returnKey {
            view.activateFromKeyboard()
            return true
        }
        if (key == .f10 && shift && !command && !option && !control)
            || (key == .returnKey && control && !command && !option && !shift)
        {
            view.showMenuFromKeyboard()
            return true
        }
        if key == .tab, !command, !control {
            if shift {
                view.window?.selectPreviousKeyView(nil)
            } else {
                view.window?.selectNextKeyView(nil)
            }
            return true
        }
        if command, !option, !control {
            return handleCommandKey(key, shift: shift, in: view)
        }
        if option, !command, !control {
            if key == .leftArrow {
                moveWithinSection(view, direction: .left)
                return true
            }
            if key == .rightArrow {
                moveWithinSection(view, direction: .right)
                return true
            }
            if key == .upArrow {
                moveAcrossSection(view, direction: .up)
                return true
            }
            if key == .downArrow {
                moveAcrossSection(view, direction: .down)
                return true
            }
        }
        if !command, !option, !control {
            if key == .leftArrow {
                moveFocus(view, direction: .left)
                return true
            }
            if key == .rightArrow {
                moveFocus(view, direction: .right)
                return true
            }
            if key == .upArrow {
                moveFocusAcrossSections(view, direction: .up)
                return true
            }
            if key == .downArrow {
                moveFocusAcrossSections(view, direction: .down)
                return true
            }
            if key == .home {
                moveFocusToEdge(view, first: true)
                return true
            }
            if key == .end {
                moveFocusToEdge(view, first: false)
                return true
            }
        }
        return false
    }

    /// Separate from keyDown because AppKit may deliver command keys through performKeyEquivalent.
    static func handleKeyEquivalent(_ event: NSEvent, in view: LayoutBarItemView) -> Bool {
        // Key equivalents reach the whole hierarchy; only the focused item may consume them.
        // Otherwise this would steal text fields' command-Z and command-arrow bindings.
        guard let window = view.window, window.firstResponder === view else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
            return false
        }
        let key = KeyCode(rawValue: Int(event.keyCode))
        return handleCommandKey(key, shift: flags.contains(.shift), in: view)
    }

    private static func handleCommandKey(_ key: KeyCode, shift: Bool, in view: LayoutBarItemView) -> Bool {
        // Editor and Settings windows have no Undo menu item; route command-Z to their undo manager.
        if key == .z {
            guard let undoManager = view.window?.undoManager else { return false }
            if shift {
                undoManager.redo()
            } else {
                undoManager.undo()
            }
            return true
        }
        if key == .leftArrow {
            moveFocusToEdge(view, first: true)
            return true
        }
        if key == .rightArrow {
            moveFocusToEdge(view, first: false)
            return true
        }
        if key == .one {
            moveToSectionNumber(1, in: view)
            return true
        }
        if key == .two {
            moveToSectionNumber(2, in: view)
            return true
        }
        if key == .three {
            moveToSectionNumber(3, in: view)
            return true
        }
        return false
    }

    // MARK: Focus navigation

    private static func moveFocus(_ view: LayoutBarItemView, direction: MoveDirection) {
        guard let container = view.superview as? LayoutBarContainer else { return }
        let itemViews = container.arrangedViews.compactMap { $0 as? LayoutBarItemView }
        guard let index = itemViews.firstIndex(where: { $0 === view }) else { return }
        let target = direction == .left ? index - 1 : index + 1
        guard itemViews.indices.contains(target) else { return }
        focus(itemViews[target], in: view.window)
    }

    private static func moveFocusToEdge(_ view: LayoutBarItemView, first: Bool) {
        guard let container = view.superview as? LayoutBarContainer else { return }
        let itemViews = container.arrangedViews.compactMap { $0 as? LayoutBarItemView }
        guard let target = first ? itemViews.first : itemViews.last else { return }
        focus(target, in: view.window)
    }

    /// Match horizontal position in the adjacent section to keep glyphs aligned.
    /// Separate view trees share only a window, so frames determine vertical order.
    private static func moveFocusAcrossSections(_ view: LayoutBarItemView, direction: MoveDirection) {
        guard let window = view.window,
              let container = view.superview as? LayoutBarContainer
        else {
            return
        }
        let currentMidY = container.convert(container.bounds, to: nil).midY
        let candidates = containers(in: window).filter { other in
            guard other !== container else { return false }
            let midY = other.convert(other.bounds, to: nil).midY
            return direction == .up ? midY > currentMidY : midY < currentMidY
        }
        guard let targetContainer = candidates.min(by: {
            verticalDistance(inWindow: $0, from: currentMidY) < verticalDistance(inWindow: $1, from: currentMidY)
        }) else {
            return
        }
        let currentX = view.convert(view.bounds, to: nil).midX
        let targetViews = targetContainer.arrangedViews.compactMap { $0 as? LayoutBarItemView }
        guard let target = targetViews.min(by: {
            horizontalDistance(inWindow: $0, from: currentX) < horizontalDistance(inWindow: $1, from: currentX)
        }) else {
            return
        }
        focus(target, in: window)
    }

    private static func horizontalDistance(inWindow view: NSView, from x: CGFloat) -> CGFloat {
        abs(view.convert(view.bounds, to: nil).midX - x)
    }

    private static func verticalDistance(inWindow view: NSView, from y: CGFloat) -> CGFloat {
        abs(view.convert(view.bounds, to: nil).midY - y)
    }

    private static func focus(_ view: LayoutBarItemView, in window: NSWindow?) {
        guard let window else { return }
        _ = window.makeFirstResponder(view)
        view.scrollToVisible(view.bounds)
    }

    // MARK: Reordering

    /// Commit the whole section order like drop and sort; move groups as blocks so nudges cannot split them.
    static func moveWithinSection(_ view: LayoutBarItemView, direction: MoveDirection) {
        guard let container = view.superview as? LayoutBarContainer,
              let appState = container.appState
        else {
            return
        }
        guard view.isEnabled else {
            appState.layoutFeedback.post(LayoutBarFeedbackCenter.itemNotMovable(itemName: view.item.displayName))
            return
        }
        let section = container.section
        let items = LayoutBarPaddingView.layoutItemsForPersistence(from: container.arrangedViews)
        guard let index = items.firstIndex(where: { $0.tag == view.item.tag }) else { return }
        let groups = appState.itemGroupManager.resolvedGroups(for: items)
        let memberIndices = MenuBarItemGroupResolver.dragUnitIndices(forIndex: index, in: groups)
        guard let low = memberIndices.min(), let high = memberIndices.max() else { return }
        let destination: Int
        switch direction {
        case .left:
            guard low > 0 else { return }
            destination = low - 1
        case .right:
            guard high + 1 < items.count else { return }
            destination = high + 2
        case .up, .down:
            return
        }
        let newOrder = MenuBarItemGroupResolver.placeBlock(
            items,
            memberIndices: memberIndices,
            toIndexInOriginal: destination
        )
        guard newOrder.map(\.tag) != items.map(\.tag) else { return }
        applySectionOrder(
            newOrder,
            previousOrder: items,
            section: section,
            appState: appState,
            undoManager: view.window?.undoManager,
            actionName: moveActionName(view.item)
        )
        announce(
            direction == .left
                ? String(localized: "Moved \(view.item.displayName) left")
                : String(localized: "Moved \(view.item.displayName) right")
        )
        refocusAfterRebuild(tag: view.item.tag, in: section, window: view.window)
    }

    static func moveAcrossSection(_ view: LayoutBarItemView, direction: MoveDirection) {
        guard let container = view.superview as? LayoutBarContainer,
              let appState = container.appState
        else {
            return
        }
        let sections = MenuBarSearchItemActions.moveDestinations(appState: appState).compactMap(\.self)
        guard let current = sections.firstIndex(of: container.section) else { return }
        let target = direction == .up ? current - 1 : current + 1
        guard sections.indices.contains(target) else { return }
        moveToSection(view, target: sections[target], appState: appState)
    }

    /// Matches the item menu's advertised ⌘-number section slots.
    static func moveToSectionNumber(_ number: Int, in view: LayoutBarItemView) {
        guard let container = view.superview as? LayoutBarContainer,
              let appState = container.appState
        else {
            return
        }
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState)
        guard destinations.indices.contains(number - 1),
              let target = destinations[number - 1]
        else {
            return
        }
        moveToSection(view, target: target, appState: appState)
    }

    private static func moveToSection(
        _ view: LayoutBarItemView,
        target: MenuBarSection.Name,
        appState: AppState
    ) {
        guard let container = view.superview as? LayoutBarContainer else { return }
        guard view.isEnabled else {
            appState.layoutFeedback.post(LayoutBarFeedbackCenter.itemNotMovable(itemName: view.item.displayName))
            return
        }
        let source = container.section
        guard source != target else { return }
        let item = view.item
        // Gate like drop and VoiceOver before registering undo to avoid phantom entries.
        // The shared move path still reports group refusals.
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        guard MenuBarBackendProvider.current.canAssign(
            item,
            to: target,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) else {
            MenuBarSearchItemActions.move(item, to: target, appState: appState)
            return
        }
        performSectionMove(
            tag: item.tag,
            from: source,
            to: target,
            appState: appState,
            undoManager: view.window?.undoManager,
            actionName: moveActionName(item)
        )
        announce(
            String(
                localized: "Moved \(item.displayName) to \(MenuBarSearchItemActions.title(for: target))"
            )
        )
        refocusAfterRebuild(tag: item.tag, in: target, window: view.window)
    }

    /// Register reverse-move undo before using VoiceOver's shared refusal-aware move path.
    private static func performSectionMove(
        tag: MenuBarItemTag,
        from source: MenuBarSection.Name,
        to target: MenuBarSection.Name,
        appState: AppState,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let item = appState.itemManager.managedItem(withTag: tag) else { return }
        if let undoManager {
            let undoTarget = LayoutBarUndoTarget(appState: appState, undoManager: undoManager)
            undoManager.registerUndo(withTarget: undoTarget) { undoTarget in
                guard let appState = undoTarget.appState,
                      let undoManager = undoTarget.undoManager
                else {
                    return
                }
                performSectionMove(
                    tag: tag,
                    from: target,
                    to: source,
                    appState: appState,
                    undoManager: undoManager,
                    actionName: actionName
                )
            }
            undoManager.setActionName(actionName)
        }
        // A keyboard move in the layout bar is the user's own edit, so Manual lets it through like a drop.
        ExplicitLayoutEdit.perform {
            MenuBarSearchItemActions.move(item, to: target, appState: appState)
        }
    }

    // MARK: Order commit

    /// Share the pane's sort sequence: record, schedule apply, and immediately apply revealed hidden sections.
    private static func applySectionOrder(
        _ order: [MenuBarItem],
        previousOrder: [MenuBarItem],
        section: MenuBarSection.Name,
        appState: AppState,
        undoManager: UndoManager?,
        actionName: String
    ) {
        if let undoManager {
            let undoTarget = LayoutBarUndoTarget(appState: appState, undoManager: undoManager)
            undoManager.registerUndo(withTarget: undoTarget) { undoTarget in
                guard let appState = undoTarget.appState,
                      let undoManager = undoTarget.undoManager
                else {
                    return
                }
                applySectionOrder(
                    previousOrder,
                    previousOrder: order,
                    section: section,
                    appState: appState,
                    undoManager: undoManager,
                    actionName: actionName
                )
            }
            undoManager.setActionName(actionName)
        }
        let controller = appState.menuBarManager.sectionController
        controller.setSectionOrder(from: order, for: section)
        // Marked here rather than at the key handler so undo and redo are explicit edits too.
        ExplicitLayoutEdit.perform {
            appState.itemManager.scheduleSectionOrderApply(for: section)
            Task { @MainActor in
                if section != .visible,
                   let revealed = controller.revealedSection,
                   revealed == section || (section == .hidden && revealed == .alwaysHidden)
                {
                    await appState.itemManager.applySectionItemOrder(
                        sections: [section],
                        controller: controller,
                        whileRevealing: revealed,
                        reason: .userReorder
                    )
                }
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
        }
    }

    // MARK: Focus restoration

    /// Recycled item views can lose focus before a move lands; retry by tag after the cache refresh rebuilds them.
    private static func refocusAfterRebuild(
        tag: MenuBarItemTag,
        in section: MenuBarSection.Name,
        window: NSWindow?
    ) {
        guard let window else { return }
        Task { @MainActor in
            for _ in 0 ..< 12 {
                if let target = itemView(forTag: tag, in: section, window: window), target.window != nil {
                    // Restore only dropped or unchanged focus; never steal it from a user-selected responder.
                    let responder = window.firstResponder
                    if responder === target || responder === window || responder == nil {
                        _ = window.makeFirstResponder(target)
                        target.scrollToVisible(target.bounds)
                    }
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(60))
                } catch {
                    return
                }
            }
        }
    }

    private static func itemView(
        forTag tag: MenuBarItemTag,
        in section: MenuBarSection.Name,
        window: NSWindow
    ) -> LayoutBarItemView? {
        containers(in: window)
            .first(where: { $0.section == section })?
            .arrangedViews
            .compactMap { $0 as? LayoutBarItemView }
            .first(where: { $0.item.tag == tag })
    }

    private static func containers(in window: NSWindow) -> [LayoutBarContainer] {
        var result = [LayoutBarContainer]()
        func walk(_ view: NSView) {
            if let container = view as? LayoutBarContainer {
                result.append(container)
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        if let content = window.contentView {
            walk(content)
        }
        return result
    }

    // MARK: Helpers

    private static func moveActionName(_ item: MenuBarItem) -> String {
        String(localized: "Move \(item.displayName)")
    }

    private static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// Undo retains its target across both stacks; keep app state here without retaining recycled item views.
@MainActor
private final class LayoutBarUndoTarget: NSObject {
    weak var appState: AppState?
    /// Weak to avoid a handler cycle; the manager stays alive through the undo operation.
    weak var undoManager: UndoManager?

    init(appState: AppState, undoManager: UndoManager) {
        self.appState = appState
        self.undoManager = undoManager
    }
}

// MARK: - LayoutBarItemView keyboard surface

extension LayoutBarItemView {
    /// Even immovable items join the key view loop for inspection and announcements.
    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if LayoutBarKeyboard.handleKeyDown(event, in: self) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if LayoutBarKeyboard.handleKeyEquivalent(event, in: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Use tile bounds so the standard focus ring hugs the glyph, not the bar row.
    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 4,
            yRadius: 4
        ).fill()
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            needsDisplay = true
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            needsDisplay = true
        }
        return resigned
    }
}
