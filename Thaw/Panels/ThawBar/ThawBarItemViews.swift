//
//  ThawBarItemViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - ThawBarItemView

struct ThawBarItemView: View {
    private static let diagLog = DiagLog(category: "ThawBar.ItemView")

    let itemManager: MenuBarItemManager
    let menuBarManager: MenuBarManager

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let displayID: CGDirectDisplayID
    let maxHeight: CGFloat?
    let tooltipDelay: TimeInterval
    let displayImage: MenuBarItemDisplayImage?
    /// Whether the keyboard has highlighted this item.
    var isKeyboardFocused = false
    /// Changes when Return or Space asks the highlighted item to click.
    var activationRequest = 0
    /// Told when the pointer enters this item, so the keyboard highlight can
    /// give way to it.
    var onPointerEntered: () -> Void = {}

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hover and keyboard highlight look the same: both say "this one".
    private var isHighlighted: Bool {
        isHovered || isKeyboardFocused
    }

    private var leftClickAction: () -> Void {
        clickAction(with: .left)
    }

    private var rightClickAction: () -> Void {
        clickAction(with: .right)
    }

    /// Thaw's own menu for the item, on Option-right-click. The same menu the
    /// Layout editor and search offer, plus a way into Layout.
    private var thawMenuProvider: () -> NSMenu? {
        let item = self.item
        return { [weak itemManager] in
            guard let appState = itemManager?.appState else { return nil }
            return MenuBarSearchItemActions.menu(for: item, appState: appState) {
                appState.menuBarManager.thawBarPanel.close()
                MenuBarSearchItemActions.openSettings(appState: appState)
            }
        }
    }

    private func clickAction(with button: CGMouseButton) -> () -> Void {
        // Bind the values out of self before the closure: reading self.item
        // inside it would retain the view and defeat the weak manager captures.
        let item = self.item
        let section = self.section
        let displayID = self.displayID
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            ThawBarItemView.diagLog.debug("click(\(button == .left ? "left" : "right")): user clicked \(item.logString)")
            let panel = menuBarManager.thawBarPanel
            menuBarManager.section(withName: section)?.hide()
            Task {
                // Wait for the panel to close (KVO on isVisible) before
                // checking item visibility.
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                await itemManager.clickConcealedItem(item: item, with: button, on: displayID)
                let duration = Date.now.timeIntervalSince(clickStartTime)
                ThawBarItemView.diagLog.debug("click(\(button == .left ? "left" : "right")): completed in \(Int(duration * 1000))ms (macOS 27 concealed-item path)")
            }
        }
    }

    var body: some View {
        if let image = displayImage {
            // Colour icons keep their own colours so they stay recognizable;
            // single-ink captures take the bar's ink, since the bar they were
            // cropped from can be the opposite brightness of this one.
            MenuBarItemGlyph(
                image: image,
                fittingHeight: maxHeight,
                reinksCaptures: true
            )
            .contentShape(Rectangle())
            .background {
                if isHighlighted {
                    Color.clear.thawGlass(
                        .selection(.accentColor, strength: .hover),
                        in: RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
                    )
                }
            }
            // Stronger lift than the 1.02 row token for the small glyph. Reduce
            // Motion drops the lift and leaves the hover wash.
            .scaleEffect(isHighlighted && !reduceMotion ? 1.12 : 1.0)
            .thawAnimation(ThawMotion.interactive, value: isHighlighted)
            .onChange(of: activationRequest) {
                if isKeyboardFocused {
                    leftClickAction()
                }
            }
            .overlay {
                ThawBarItemClickView(
                    item: item,
                    tooltipDelay: tooltipDelay,
                    leftClickAction: leftClickAction,
                    rightClickAction: rightClickAction,
                    onHover: { hovering in
                        isHovered = hovering
                        if hovering {
                            onPointerEntered()
                        }
                    },
                    thawMenuProvider: thawMenuProvider
                )
            }
            // displayName mints an NSRunningApplication per call, faster than
            // the autorelease pool drains here; MenuBarItemDisplayName caches.
            .accessibilityLabel(MenuBarItemDisplayName.displayName(for: item))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, leftClickAction)
            .accessibilityAction(named: "Click", leftClickAction)
            .accessibilityAction(named: "Right-click", rightClickAction)
        }
    }
}

// MARK: - ThawBarItemClickView

struct ThawBarItemClickView: NSViewRepresentable {
    /// A click must be quick and short; anything else is a drag of the panel,
    /// which is movable by its background.
    private struct PressTracker {
        private var startDate = Date.distantPast
        private var startLocation = CGPoint.zero

        mutating func pressBegan() {
            startDate = .now
            startLocation = NSEvent.mouseLocation
        }

        var releaseIsClick: Bool {
            Date.now.timeIntervalSince(startDate) < 0.5
                && startLocation.distance(to: NSEvent.mouseLocation) < 5
        }
    }

    final class Represented: NSView {
        var item: MenuBarItem
        var tooltipDelay: TimeInterval

        var leftClickAction: () -> Void
        var rightClickAction: () -> Void
        var onHover: (Bool) -> Void

        private var leftPress = PressTracker()
        private var rightPress = PressTracker()

        /// Resolved through MenuBarItemDisplayName so the continuous
        /// updateNSView calls do not leak an NSRunningApplication per tick.
        private lazy var tooltipController = CustomTooltipController(
            text: MenuBarItemDisplayName.displayName(for: item),
            view: self
        )
        private var tooltipTrackingArea: NSTrackingArea?

        init(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            super.init(frame: .zero)
        }

        func update(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            tooltipController.text = MenuBarItemDisplayName.displayName(for: item)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            tooltipController.cancel()
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            tooltipController.cancel()
            leftPress.pressBegan()
        }

        override func rightMouseDown(with event: NSEvent) {
            // Option-right-click is Thaw's own menu for the item; a plain
            // right-click still goes to the app's secondary menu.
            if event.modifierFlags.contains(.option), let menu = thawMenu() {
                tooltipController.cancel()
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
            super.rightMouseDown(with: event)
            tooltipController.cancel()
            rightPress.pressBegan()
        }

        /// The item menu every Thaw surface offers. See LayoutBarItemMenu.
        var thawMenuProvider: (() -> NSMenu?)?

        private func thawMenu() -> NSMenu? {
            thawMenuProvider?()
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            if leftPress.releaseIsClick {
                leftClickAction()
            }
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            if rightPress.releaseIsClick {
                rightClickAction()
            }
        }
    }

    let item: MenuBarItem
    let tooltipDelay: TimeInterval

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void
    let onHover: (Bool) -> Void

    /// Builds Thaw's item menu on demand. Nil where no app state is at hand.
    var thawMenuProvider: (() -> NSMenu?)?

    func makeNSView(context _: Context) -> Represented {
        let view = Represented(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
        view.thawMenuProvider = thawMenuProvider
        return view
    }

    func updateNSView(_ nsView: Represented, context _: Context) {
        // Keep the backing NSView in sync with SwiftUI updates; tooltip text,
        // tooltip timing, and click handlers can all change after creation.
        nsView.update(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
        nsView.thawMenuProvider = thawMenuProvider
    }
}
