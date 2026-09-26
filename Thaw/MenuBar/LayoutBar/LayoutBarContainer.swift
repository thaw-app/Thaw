//
//  LayoutBarContainer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Observation

/// A container for the items in the menu bar layout interface.
final class LayoutBarContainer: NSView {
    enum DraggingPhase {
        case entered, exited, updated, ended
    }

    private lazy var widthConstraint: NSLayoutConstraint = {
        let constraint = widthAnchor.constraint(equalToConstant: 0)
        constraint.isActive = true
        return constraint
    }()

    private lazy var heightConstraint: NSLayoutConstraint = {
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.isActive = true
        return constraint
    }()

    private(set) weak var appState: AppState?

    let section: MenuBarSection.Name

    /// Reset to `true` after each layout pass.
    var shouldAnimateNextLayoutPass = false

    /// Going from `false` to `true` refreshes from the item cache, so updates
    /// that arrived meanwhile aren't lost.
    var canSetArrangedViews = true {
        didSet {
            guard canSetArrangedViews, !oldValue, let appState else {
                return
            }
            let items = appState.itemManager.itemCache.managedItems(for: section)
            setArrangedViews(items: items)
        }
    }

    /// Resumes cache-driven updates after a drag without animating. The
    /// container is trailing-aligned, so animating while its width changes
    /// makes children fly across the row.
    func resumeArrangedViewUpdatesWithoutAnimation() {
        guard !canSetArrangedViews else { return }
        shouldAnimateNextLayoutPass = false
        canSetArrangedViews = true
    }

    /// Laid out left to right, separated by ``spacing``.
    var arrangedViews = [LayoutBarArrangedView]() {
        didSet {
            layoutArrangedViews(oldViews: oldValue)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private var enableAlwaysHiddenSectionObservationTask: Task<Void, Never>?

    private var averageColorInfoObservationTask: Task<Void, Never>?

    private var itemCacheObservationTask: Task<Void, Never>?

    deinit {
        enableAlwaysHiddenSectionObservationTask?.cancel()
        averageColorInfoObservationTask?.cancel()
        itemCacheObservationTask?.cancel()
    }

    init(appState: AppState, section: MenuBarSection.Name) {
        self.appState = appState
        self.section = section
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Tracks the last known notch state to avoid redundant badge updates.
    private var lastScreenHasNotch: Bool?

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            let itemManager = appState.itemManager
            itemCacheObservationTask = Task { [weak self] in
                let changes = Observations {
                    (itemManager.itemCache, itemManager.newItemsPlacement)
                }
                for await (cache, _) in changes {
                    guard let self else {
                        return
                    }
                    setArrangedViews(items: cache.managedItems(for: section))
                }
            }

            // `@Observable`, so observed separately from the Combine chain.
            let advancedSettings = appState.settings.advanced
            enableAlwaysHiddenSectionObservationTask = Task { [weak self] in
                let changes = Observations { advancedSettings.enableAlwaysHiddenSection }
                for await _ in changes {
                    guard let self else { return }
                    setArrangedViews(items: itemManager.itemCache.managedItems(for: section))
                }
            }

            averageColorInfoObservationTask = Task { [weak self, weak appState] in
                var previous: MenuBarAverageColorInfo?
                let changes = Observations { appState?.menuBarManager.averageColorInfo }
                for await colorInfo in changes {
                    guard let self else { return }
                    guard colorInfo != previous else { continue }
                    previous = colorInfo
                    if let badgeView = self.arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = colorInfo
                    }
                }
            }

            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .sink { [weak self] _ in
                    guard let self else { return }
                    if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = appState.menuBarManager.averageColorInfo
                    }
                }
                .store(in: &c)

            // Screen-parameter changes don't fire when the Settings window
            // moves between screens; didChangeScreenNotification does.
            NotificationCenter.default
                .publisher(for: NSWindow.didChangeScreenNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self,
                          let notifyingWindow = notification.object as? NSWindow,
                          notifyingWindow === self.window
                    else { return }
                    updateBadgeForScreenChange()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Updates the badge view's color info when the screen changes (notch detection)
    private func updateBadgeForScreenChange() {
        let currentHasNotch = NSScreen.screenWithActiveMenuBar?.hasNotch ?? false
        if lastScreenHasNotch != currentHasNotch {
            lastScreenHasNotch = currentHasNotch
            if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                badgeView.averageColorInfo = appState?.menuBarManager.averageColorInfo
            }
        }
    }

    /// Avoids subscribing the whole container to every image cache update.
    func itemPreferredSizeDidChange(_ itemView: LayoutBarArrangedView) {
        guard arrangedViews.contains(itemView) else {
            return
        }
        shouldAnimateNextLayoutPass = false
        layoutArrangedViews()
    }

    /// Performs layout of the container's arranged views.
    ///
    /// Removes views no longer arranged and animates moved ones.
    ///
    /// - Parameter oldViews: Pass `nil` to use the current ``arrangedViews``.
    private func layoutArrangedViews(oldViews: [LayoutBarArrangedView]? = nil) {
        defer {
            shouldAnimateNextLayoutPass = true
        }

        let oldViews = oldViews ?? arrangedViews

        for view in oldViews where !arrangedViews.contains(view) {
            // Never detach a view another container now owns.
            guard view.superview === self else { continue }
            view.removeFromSuperview()
            view.hasContainer = false
        }

        var previous: NSView?

        let maxHeight = arrangedViews.lazy
            .map(\.bounds.height)
            .max() ?? 0

        for var view in arrangedViews {
            if subviews.contains(view) {
                if shouldAnimateNextLayoutPass {
                    view = view.animator()
                }
            } else {
                addSubview(view)
                view.hasContainer = true
            }

            view.setFrameOrigin(
                CGPoint(
                    x: previous.map(\.frame.maxX) ?? 0,
                    y: (maxHeight / 2) - view.bounds.midY
                )
            )

            previous = view // retain the view
        }

        widthConstraint.constant = previous?.frame.maxX ?? 0
        heightConstraint.constant = maxHeight
    }

    /// Does nothing while ``canSetArrangedViews`` is `false`.
    func setArrangedViews(items: [MenuBarItem]?) {
        guard
            let appState,
            canSetArrangedViews
        else {
            return
        }
        guard let items else {
            arrangedViews.removeAll()
            return
        }
        // Thumbnail refreshes below can reset this flag via a size-only
        // layout.
        let shouldAnimateReconciledLayout = shouldAnimateNextLayoutPass
        var newViews = [LayoutBarArrangedView]()
        let itemIdentifiers = items.map(\.uniqueIdentifier)
        let badgeIndex = appState.itemManager.newItemsBadgeIndex(in: section, itemIdentifiers: itemIdentifiers)
        for item in items {
            if let existingView = arrangedViews.lazy
                .compactMap({ $0 as? LayoutBarItemView })
                .first(where: { Self.canReuseItemView(representing: $0.item, for: item) })
            {
                // Keep the last stable thumbnail; a capture taken while frozen
                // may be a transient crop from the system move.
                newViews.append(existingView)
            } else {
                let view = LayoutBarItemView(appState: appState, item: item)
                newViews.append(view)
            }
        }
        if let badgeIndex {
            let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) ?? LayoutBarNewItemsBadgeView()
            badgeView.averageColorInfo = appState.menuBarManager.averageColorInfo
            let insertionIndex = badgeIndex.clamped(to: newViews.startIndex ... newViews.endIndex)
            newViews.insert(badgeView, at: insertionIndex)
        }

        // The same cache can publish repeatedly while a move settles.
        guard !arrangedViews.elementsEqual(newViews, by: { $0 === $1 }) else {
            // Keep the reset a layout pass would have done.
            shouldAnimateNextLayoutPass = true
            return
        }
        shouldAnimateNextLayoutPass = shouldAnimateReconciledLayout
        arrangedViews = newViews
    }

    /// Whether an existing view still represents the same live status-item
    /// window after a cache refresh.
    ///
    /// Ignores origin and on-screen state, which change during a move.
    static nonisolated func canReuseItemView(
        representing existingItem: MenuBarItem,
        for refreshedItem: MenuBarItem
    ) -> Bool {
        existingItem.windowID == refreshedItem.windowID &&
            existingItem.tag == refreshedItem.tag &&
            existingItem.ownerPID == refreshedItem.ownerPID &&
            existingItem.sourcePID == refreshedItem.sourcePID &&
            existingItem.bounds.size == refreshedItem.bounds.size &&
            existingItem.title == refreshedItem.title
    }

    /// Updates the positions of the container's arranged views using the
    /// specified dragging information and phase.
    ///
    /// - Returns: A dragging operation.
    @discardableResult
    func updateArrangedViewsForDrag(with draggingInfo: NSDraggingInfo, phase: DraggingPhase) -> NSDragOperation {
        guard let sourceView = draggingInfo.draggingSource as? LayoutBarArrangedView else {
            return []
        }
        switch phase {
        case .entered:
            if !arrangedViews.contains(sourceView) {
                shouldAnimateNextLayoutPass = false
            }
            return updateArrangedViewsForDrag(with: draggingInfo, phase: .updated)
        case .exited:
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                shouldAnimateNextLayoutPass = false
                arrangedViews.remove(at: sourceIndex)
            }
            return .move
        case .updated:
            if
                sourceView.oldContainerInfo == nil,
                let sourceIndex = arrangedViews.firstIndex(of: sourceView)
            {
                sourceView.oldContainerInfo = (self, sourceIndex)
            }
            let draggingLocation = convert(draggingInfo.draggingLocation, from: nil)
            // Only dragging the badge itself moves the badge.
            let excludeBadge = !sourceView.isNewItemsBadge
            // A section with only the badge must still accept drops.
            guard !Self.enabledDropTargets(in: arrangedViews, excludingBadge: excludeBadge).isEmpty else {
                if !arrangedViews.contains(sourceView) {
                    let insertionIndex = Self.emptyTargetInsertionIndex(
                        for: draggingLocation.x,
                        in: arrangedViews,
                        excludingBadge: excludeBadge
                    )
                    transferArrangedViewFromSourceIfNeeded(sourceView)
                    arrangedViews.insert(sourceView, at: insertionIndex)
                }
                return .move
            }
            guard
                let destinationView = arrangedView(nearestTo: draggingLocation.x, excludingBadge: excludeBadge),
                destinationView !== sourceView,
                destinationView.isEnabled,
                destinationView.layer?.animationKeys() == nil,
                let destinationIndex = arrangedViews.firstIndex(of: destinationView)
            else {
                return .move
            }
            let midX = destinationView.frame.midX
            let offset = destinationView.frame.width / 2
            if !((midX - offset) ... (midX + offset)).contains(draggingLocation.x),
               sourceView.oldContainerInfo?.container === self
            {
                return .move
            }
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                var targetIndex = destinationIndex
                if destinationIndex > sourceIndex {
                    targetIndex += 1
                }
                arrangedViews.move(fromOffsets: [sourceIndex], toOffset: targetIndex)
            } else {
                // addSubview doesn't clear the source's arrangedViews, and a
                // stale reference lets the source detach the icon later.
                transferArrangedViewFromSourceIfNeeded(sourceView)
                arrangedViews.insert(sourceView, at: destinationIndex)
            }
            return .move
        case .ended:
            return .move
        }
    }

    private func transferArrangedViewFromSourceIfNeeded(_ view: LayoutBarArrangedView) {
        guard let sourceContainer = view.oldContainerInfo?.container,
              sourceContainer !== self
        else {
            return
        }
        sourceContainer.removeArrangedViewForTransfer(view)
    }

    private func removeArrangedViewForTransfer(_ view: LayoutBarArrangedView) {
        guard let index = arrangedViews.firstIndex(of: view) else { return }
        shouldAnimateNextLayoutPass = false
        arrangedViews.remove(at: index)
    }

    /// Returns a cancelled drag's view before updates resume, or the old
    /// cache builds a replacement and the icon briefly duplicates.
    func restoreArrangedViewAfterCancelledDrag(
        _ view: LayoutBarArrangedView,
        from currentContainer: LayoutBarContainer?,
        at originalIndex: Int
    ) {
        if let currentContainer, currentContainer !== self {
            currentContainer.removeArrangedViewForTransfer(view)
        }

        shouldAnimateNextLayoutPass = false
        var restoredViews = arrangedViews.filter { $0 !== view }
        let insertionIndex = originalIndex.clamped(to: restoredViews.startIndex ... restoredViews.endIndex)
        restoredViews.insert(view, at: insertionIndex)
        arrangedViews = restoredViews
    }

    static func enabledDropTargets(
        in arrangedViews: [LayoutBarArrangedView],
        excludingBadge: Bool
    ) -> [LayoutBarArrangedView] {
        arrangedViews.filter { view in
            view.isEnabled && (!excludingBadge || !view.isNewItemsBadge)
        }
    }

    static func emptyTargetInsertionIndex(
        for xPosition: CGFloat,
        in arrangedViews: [LayoutBarArrangedView],
        excludingBadge: Bool
    ) -> Int {
        guard excludingBadge,
              let badgeIndex = arrangedViews.firstIndex(where: { $0.isNewItemsBadge })
        else {
            return arrangedViews.startIndex
        }
        let badgeView = arrangedViews[badgeIndex]
        return xPosition > badgeView.frame.midX ? badgeIndex + 1 : badgeIndex
    }

    /// Returns the arranged view whose horizontal center is closest to
    /// `xPosition`, in container coordinates.
    func arrangedView(nearestTo xPosition: CGFloat, excludingBadge: Bool = false) -> LayoutBarArrangedView? {
        let candidates = excludingBadge ? arrangedViews.filter { !$0.isNewItemsBadge } : arrangedViews
        return candidates.min { view1, view2 in
            let distance1 = abs(view1.frame.midX - xPosition)
            let distance2 = abs(view2.frame.midX - xPosition)
            return distance1 < distance2
        }
    }
}
