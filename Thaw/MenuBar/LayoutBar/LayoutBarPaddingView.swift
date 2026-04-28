//
//  LayoutBarPaddingView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

/// A Cocoa view that manages the menu bar layout interface.
final class LayoutBarPaddingView: NSView {
    private static let diagLog = DiagLog(category: "LayoutBarPaddingView")

    private let container: LayoutBarContainer
    private var isStabilizing = false

    private var notchView: NotchIndicatorView?
    private var notchWidthConstraint: NSLayoutConstraint?
    private var notchTrailingConstraint: NSLayoutConstraint?
    private var minWidthConstraint: NSLayoutConstraint?
    private var containerLeadingAfterNotchConstraint: NSLayoutConstraint?
    private var notchObservers = Set<AnyCancellable>()

    private func layoutWatchdogDuration() -> Duration? {
        switch MenuBarItemManager.layoutWatchdogTimeout {
        case let .seconds(s):
            return .seconds(s)
        case let .milliseconds(ms):
            return .milliseconds(ms)
        default:
            return nil
        }
    }

    /// The layout view's arranged views.
    var arrangedViews: [LayoutBarArrangedView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

    /// Creates a layout bar view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.container = LayoutBarContainer(appState: appState, section: section)

        super.init(frame: .zero)

        addSubview(container)
        self.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 7.5),
            leadingAnchor.constraint(lessThanOrEqualTo: container.leadingAnchor, constant: -7.5),
        ])

        registerForDraggedTypes([.layoutBarItem])

        configureNotchObservers(appState: appState)
        updateNotchPresentation()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing else { return [] }
        return container.updateArrangedViewsForDrag(with: sender, phase: .entered)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard !isStabilizing else { return }
        if let sender {
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isStabilizing else { return [] }
        return container.updateArrangedViewsForDrag(with: sender, phase: .updated)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard !isStabilizing else { return }
        container.updateArrangedViewsForDrag(with: sender, phase: .ended)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggingSource = sender.draggingSource as? LayoutBarArrangedView else {
            container.canSetArrangedViews = true
            return false
        }

        if case let .item(draggingItem) = draggingSource.kind,
           draggingItem.tag == .visibleControlItem,
           container.section != .visible
        {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Cannot move \(Constants.displayName) icon.")
            alert.informativeText = String(localized: "The \(Constants.displayName) icon must always remain in the visible section.")

            if let window = window {
                alert.beginSheetModal(for: window)
            }

            // Revert the visual state: remove the item from the container it was dropped into
            // and set hasContainer to false so it snaps back to its original container.
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
            draggingSource.hasContainer = false

            container.canSetArrangedViews = true
            return false
        }

        if draggingSource.isNewItemsBadge {
            let sourceContainer = draggingSource.oldContainerInfo?.container
            container.appState?.itemManager.updateNewItemsPlacement(
                section: container.section,
                arrangedViews: arrangedViews
            )
            draggingSource.oldContainerInfo = nil
            container.canSetArrangedViews = true
            sourceContainer?.canSetArrangedViews = true
            if let appState = container.appState {
                sourceContainer?.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: sourceContainer?.section ?? container.section))
                if sourceContainer !== container {
                    container.setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: container.section))
                }
            }
            return true
        }

        var willMove = false

        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                willMove = true
                Task {
                    guard case let .item(item) = draggingSource.kind else {
                        self.container.canSetArrangedViews = true
                        return
                    }
                    if let destination = await self.liveFallbackDestinationForDraggedItem() {
                        self.move(item: item, to: destination)
                    } else {
                        Self.diagLog.error("No target item for layout bar drag")
                        self.container.canSetArrangedViews = true
                    }
                }
            } else if case let .item(item) = draggingSource.kind {
                if let targetItem = nearestItem(toRightOf: index) {
                    willMove = true
                    move(item: item, to: .leftOfItem(targetItem))
                } else if let targetItem = nearestItem(toLeftOf: index) {
                    willMove = true
                    move(item: item, to: .rightOfItem(targetItem))
                } else if !arrangedViews.isEmpty {
                    willMove = true
                    Task {
                        if let destination = await self.liveFallbackDestinationForDraggedItem() {
                            self.move(item: item, to: destination)
                        } else {
                            Self.diagLog.error("No target item for layout bar drag")
                            self.container.canSetArrangedViews = true
                        }
                    }
                }
            }
        }

        // Only re-enable view updates here if no move was initiated.
        // When a move IS initiated, the move() Task re-enables after stabilization.
        if !willMove {
            container.canSetArrangedViews = true
        }

        return true
    }

    private func move(item: MenuBarItem, to destination: MenuBarItemManager.MoveDestination) {
        guard let appState = container.appState else {
            return
        }
        Task {
            guard !isStabilizing else { return }
            isStabilizing = true
            await MainActor.run { self.showOverlay(true) }
            // Increased delay to allow macOS to settle after operations like Reset Layout.
            // Prevents transient errors when dragging items immediately after reset.
            try await Task.sleep(for: .milliseconds(150))

            let watchdogTask = Task { [weak self, weak appState] in
                guard let duration = self?.layoutWatchdogDuration() else { return }
                try? await Task.sleep(for: duration + .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.resetStabilizingStateIfNeeded()
                guard let appState else { return }
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            }
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                )
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                await stabilizePlacement(of: item, to: destination, expectedSection: container.section, appState: appState)
            } catch {
                Self.diagLog.error("Error moving menu bar item: \(error)")
                let alert = NSAlert(error: error)
                alert.runModal()
            }
            watchdogTask.cancel()
            if let appState = container.appState {
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
            await MainActor.run {
                self.isStabilizing = false
                self.showOverlay(false)
                // Update the badge anchor BEFORE re-enabling view updates, using
                // the current visual arrangement from the drag. This ensures the
                // didSet refresh uses the correct anchor position.
                // Only update if this section actually contains the badge.
                if let appState = self.container.appState,
                   self.containsNewItemsBadge()
                {
                    appState.itemManager.updateNewItemsPlacement(
                        section: self.container.section,
                        arrangedViews: self.container.arrangedViews
                    )
                }
                // Re-enable view updates. The didSet will automatically refresh
                // from the current cache with the updated badge anchor.
                self.container.canSetArrangedViews = true
            }
        }
    }

    @MainActor
    private func resetStabilizingStateIfNeeded() async {
        if isStabilizing {
            isStabilizing = false
            showOverlay(false)
            container.canSetArrangedViews = true
        }
    }

    private func showOverlay(_ visible: Bool) {
        container.alphaValue = visible ? 0.6 : 1.0
    }

    private func containsNewItemsBadge() -> Bool {
        for arrangedView in container.arrangedViews where arrangedView.isNewItemsBadge {
            return true
        }
        return false
    }

    private func nearestItem(toRightOf index: Int) -> MenuBarItem? {
        guard arrangedViews.indices.contains(index + 1) else {
            return nil
        }
        for candidateIndex in (index + 1) ..< arrangedViews.count {
            if case let .item(item) = arrangedViews[candidateIndex].kind {
                return item
            }
        }
        return nil
    }

    private func nearestItem(toLeftOf index: Int) -> MenuBarItem? {
        guard arrangedViews.indices.contains(index - 1) else {
            return nil
        }
        for candidateIndex in stride(from: index - 1, through: 0, by: -1) {
            if case let .item(item) = arrangedViews[candidateIndex].kind {
                return item
            }
        }
        return nil
    }

    private func liveFallbackDestinationForDraggedItem() async -> MenuBarItemManager.MoveDestination? {
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        return switch container.section {
        case .visible:
            nil
        case .hidden:
            items.first(matching: .hiddenControlItem).map { .leftOfItem($0) }
        case .alwaysHidden:
            items.first(matching: .alwaysHiddenControlItem).map { .leftOfItem($0) }
        }
    }

    /// Ensures the dragged item remains in the intended section and its icon appears.
    private func stabilizePlacement(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        expectedSection: MenuBarSection.Name,
        appState: AppState
    ) async {
        // First refresh caches and verify placement.
        await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)

        func isInExpectedSection() -> Bool {
            appState.itemManager.itemCache[expectedSection].contains { $0.tag == item.tag }
        }

        if !isInExpectedSection() {
            // Allow macOS a brief moment to settle, then retry once.
            try? await Task.sleep(for: .milliseconds(120))
            do {
                try await appState.itemManager.move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: MenuBarItemManager.layoutWatchdogTimeout
                )
                await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            } catch {
                Self.diagLog.error("Stabilize move failed: \(error)")
            }
        }

        // Refresh images so icons show immediately in the UI without clearing to avoid temporary gaps.
        await MainActor.run {
            appState.imageCache.performCacheCleanup()
        }
        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateNotchPresentation()
        }
    }

    private func configureNotchObservers(appState: AppState) {
        guard container.section == .visible else {
            return
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNotchPresentation()
            }
            .store(in: &notchObservers)

        NotificationCenter.default
            .publisher(for: NSWindow.didChangeScreenNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let notifyingWindow = notification.object as? NSWindow,
                      notifyingWindow === self.window
                else { return }
                self.updateNotchPresentation()
            }
            .store(in: &notchObservers)

        appState.menuBarManager.$averageColorInfo
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] colorInfo in
                self?.notchView?.averageColorInfo = colorInfo
            }
            .store(in: &notchObservers)
    }

    private func updateNotchPresentation() {
        guard
            container.section == .visible,
            let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main,
            screen.hasNotch,
            let notch = screen.frameOfNotch
        else {
            tearDownNotchPresentation()
            return
        }

        let notchIndicatorWidth = notch.width + MenuBarSection.notchGap
        // Distance from the bar's trailing edge to the notch indicator's
        // trailing edge — equals the real-world items area (everything
        // right of `notch.maxX + notchGap` in the menu bar) plus the 7.5pt
        // cosmetic inset that sits between items and the rounded edge.
        let notchTrailingOffset = max(0, screen.frame.maxX - notch.maxX - MenuBarSection.notchGap) + 7.5
        // Bar must always be wide enough to represent the real-world span
        // from `notch.minX` to `screen.maxX`, plus 7.5pt cosmetic inset on
        // each side. When the Settings pane is wider, the bar grows past
        // this and the empty area is shown to the LEFT of the notch.
        let barMinWidth = max(0, screen.frame.maxX - notch.minX) + 15
        let colorInfo = container.appState?.menuBarManager.averageColorInfo

        if let notchView {
            notchView.isHidden = false
            notchView.averageColorInfo = colorInfo
            notchWidthConstraint?.constant = notchIndicatorWidth
            notchTrailingConstraint?.constant = -notchTrailingOffset
            minWidthConstraint?.constant = barMinWidth
            return
        }

        let view = NotchIndicatorView(averageColorInfo: colorInfo)
        addSubview(view, positioned: .below, relativeTo: container)
        self.notchView = view

        let widthConstraint = view.widthAnchor.constraint(equalToConstant: notchIndicatorWidth)
        let trailingConstraint = view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -notchTrailingOffset)
        let containerLeading = container.leadingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor)
        let minWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: barMinWidth)

        NSLayoutConstraint.activate([
            trailingConstraint,
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,
            containerLeading,
            minWidth,
        ])

        notchWidthConstraint = widthConstraint
        notchTrailingConstraint = trailingConstraint
        containerLeadingAfterNotchConstraint = containerLeading
        minWidthConstraint = minWidth
    }

    private func tearDownNotchPresentation() {
        notchWidthConstraint?.isActive = false
        notchTrailingConstraint?.isActive = false
        containerLeadingAfterNotchConstraint?.isActive = false
        minWidthConstraint?.isActive = false
        notchWidthConstraint = nil
        notchTrailingConstraint = nil
        containerLeadingAfterNotchConstraint = nil
        minWidthConstraint = nil
        notchView?.removeFromSuperview()
        notchView = nil
    }
}
