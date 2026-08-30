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
    /// Phases for a dragging session.
    enum DraggingPhase {
        case entered, exited, updated, ended
    }

    /// Cached width constraint for the container view.
    private lazy var widthConstraint: NSLayoutConstraint = {
        let constraint = widthAnchor.constraint(equalToConstant: 0)
        constraint.isActive = true
        return constraint
    }()

    /// Cached height constraint for the container view.
    private lazy var heightConstraint: NSLayoutConstraint = {
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.isActive = true
        return constraint
    }()

    /// The shared app state instance.
    private(set) weak var appState: AppState?

    /// The section whose items are represented.
    let section: MenuBarSection.Name

    /// A Boolean value that indicates whether the container should
    /// animate its next layout pass.
    ///
    /// After each layout pass, this value is reset to `true`.
    var shouldAnimateNextLayoutPass = false

    /// A Boolean value that indicates whether the container can
    /// set its arranged views.
    ///
    /// When this transitions from `false` to `true`, the container
    /// automatically refreshes its arranged views from the current
    /// item cache. This ensures updates that arrived while the flag
    /// was `false` are not lost.
    var canSetArrangedViews = true {
        didSet {
            guard canSetArrangedViews, !oldValue, let appState else {
                return
            }
            // Flag transitioned from false to true. Refresh from
            // current cache to pick up any updates that were missed.
            let items = appState.itemManager.itemCache.managedItems(for: section)
            setArrangedViews(items: items)
        }
    }

    /// Resumes cache-driven updates after a drag without animating from the
    /// editor's temporary arrangement to the settled system snapshot.
    ///
    /// The container is trailing-aligned. Animating child origins while its
    /// width changes makes those children appear to fly across the row, even
    /// though both layouts are valid. Commit the first reconciled layout as a
    /// single frame instead.
    func resumeArrangedViewUpdatesWithoutAnimation() {
        guard !canSetArrangedViews else { return }
        shouldAnimateNextLayoutPass = false
        canSetArrangedViews = true
    }

    /// The contaner's arranged views.
    ///
    /// The views are laid out from left to right in the order that they
    /// appear in the array. The ``spacing`` property determines the amount
    /// of space between each view.
    var arrangedViews = [LayoutBarArrangedView]() {
        didSet {
            layoutArrangedViews(oldViews: oldValue)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Task observing `AdvancedSettings.enableAlwaysHiddenSection`, which is
    /// `@Observable` rather than a Combine `ObservableObject`, so it can no
    /// longer take part in the `Publishers.CombineLatest3` below.
    private var enableAlwaysHiddenSectionObservationTask: Task<Void, Never>?

    /// Task observing `menuBarManager.averageColorInfo` (wave 3), replacing
    /// the old `$averageColorInfo` sink.
    private var averageColorInfoObservationTask: Task<Void, Never>?

    /// Task observing `itemManager.itemCache` and `itemManager.newItemsPlacement`
    /// (wave 4), which are `@Observable` rather than Combine `@Published`
    /// properties, so they can no longer take part in `Publishers.CombineLatest`.
    /// Replaces the old `CombineLatest($itemCache, $newItemsPlacement).sink`.
    private var itemCacheObservationTask: Task<Void, Never>?

    deinit {
        enableAlwaysHiddenSectionObservationTask?.cancel()
        averageColorInfoObservationTask?.cancel()
        itemCacheObservationTask?.cancel()
    }

    /// Creates a container view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
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

            // `AdvancedSettings.enableAlwaysHiddenSection` is `@Observable`
            // rather than a Combine `ObservableObject`, so it can no longer
            // take part in the `CombineLatest` above — observed separately,
            // re-running the same re-arrangement using the current item cache.
            let advancedSettings = appState.settings.advanced
            enableAlwaysHiddenSectionObservationTask = Task { [weak self] in
                let changes = Observations { advancedSettings.enableAlwaysHiddenSection }
                for await _ in changes {
                    guard let self else { return }
                    setArrangedViews(items: itemManager.itemCache.managedItems(for: section))
                }
            }

            // Observe average color changes to update badge appearance.
            // `menuBarManager` is now `@Observable` (wave 3), so it no
            // longer has an `$averageColorInfo` publisher.
            averageColorInfoObservationTask = Task { [weak self, weak appState] in
                var previous: MenuBarAverageColorInfo?
                let changes = Observations { appState?.menuBarManager.averageColorInfo }
                for await colorInfo in changes {
                    guard let self else { return }
                    guard colorInfo != previous else { continue }
                    previous = colorInfo
                    // Update the color info on the badge view
                    if let badgeView = self.arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = colorInfo
                    }
                }
            }

            // Observe screen parameter changes (moving between displays) to update badge
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .sink { [weak self] _ in
                    guard let self else { return }
                    // Force update badge's color info and redraw when screen changes
                    if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = appState.menuBarManager.averageColorInfo
                    }
                }
                .store(in: &c)

            // Detect when the Settings window is dragged to a display with a
            // different notch state. NSApplication.didChangeScreenParametersNotification
            // does not fire for window movement between screens, but
            // NSWindow.didChangeScreenNotification does.
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

    /// Relayouts the container after one arranged view changed size.
    ///
    /// This avoids subscribing the whole container to every image cache update.
    func itemPreferredSizeDidChange(_ itemView: LayoutBarArrangedView) {
        guard arrangedViews.contains(itemView) else {
            return
        }
        shouldAnimateNextLayoutPass = false
        layoutArrangedViews()
    }

    /// Performs layout of the container's arranged views.
    ///
    /// The container removes from its subviews the views that are included
    /// in the `oldViews` array but not in the the current ``arrangedViews``
    /// array. Views that are found in both arrays, but at different indices
    /// are animated from their old index to their new index.
    ///
    /// - Parameter oldViews: The old value of the container's arranged views.
    ///   Pass `nil` to use the current ``arrangedViews`` array.
    private func layoutArrangedViews(oldViews: [LayoutBarArrangedView]? = nil) {
        defer {
            shouldAnimateNextLayoutPass = true
        }

        let oldViews = oldViews ?? arrangedViews

        // remove views that are no longer part of the arranged views
        for view in oldViews where !arrangedViews.contains(view) {
            // A cross-row drag transfers the same NSView instance to the
            // destination. A stale source snapshot must never detach a view
            // that is already owned by another container.
            guard view.superview === self else { continue }
            view.removeFromSuperview()
            view.hasContainer = false
        }

        // retain the previous view on each iteration; use its frame
        // to calculate the x coordinate of the next view's origin
        var previous: NSView?

        // get the max height of all arranged views to calculate the
        // y coordinate of each view's origin
        let maxHeight = arrangedViews.lazy
            .map(\.bounds.height)
            .max() ?? 0

        for var view in arrangedViews {
            if subviews.contains(view) {
                // view already exists inside the layout view, but may
                // have moved from its previous location;
                if shouldAnimateNextLayoutPass {
                    // replace the view with its animator proxy
                    view = view.animator()
                }
            } else {
                // view does not already exist inside the layout view;
                // add it as a subview
                addSubview(view)
                view.hasContainer = true
            }

            // set the view's origin; if the view is an animator proxy,
            // it will animate to the new position; otherwise, it must
            // be a newly added view
            view.setFrameOrigin(
                CGPoint(
                    x: previous.map(\.frame.maxX) ?? 0,
                    y: (maxHeight / 2) - view.bounds.midY
                )
            )

            previous = view // retain the view
        }

        // update the width and height constraints using the information
        // collected while iterating
        widthConstraint.constant = previous?.frame.maxX ?? 0
        heightConstraint.constant = maxHeight
    }

    /// Sets the container's arranged views with the given items.
    ///
    /// - Note: If the value of the container's ``canSetArrangedViews``
    ///   property is `false`, this function returns early.
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
        // Thumbnail refreshes below can trigger an immediate size-only layout,
        // which normally resets this flag. Preserve the caller's animation
        // choice for the actual ordered reconciliation that follows.
        let shouldAnimateReconciledLayout = shouldAnimateNextLayoutPass
        var newViews = [LayoutBarArrangedView]()
        let itemIdentifiers = items.map(\.uniqueIdentifier)
        let badgeIndex = appState.itemManager.newItemsBadgeIndex(in: section, itemIdentifiers: itemIdentifiers)
        for item in items {
            if let existingView = arrangedViews.lazy
                .compactMap({ $0 as? LayoutBarItemView })
                .first(where: { Self.canReuseItemView(representing: $0.item, for: item) })
            {
                // Keep the view's last stable thumbnail through reconciliation.
                // A capture that completed while this row was frozen may still
                // be a transient crop from the physical system move; the fresh
                // post-thaw image-cache pass will publish the settled image.
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

        // Observation can publish the same ordered cache more than once while
        // a move settles. Avoid re-targeting animator proxies for a no-op.
        guard !arrangedViews.elementsEqual(newViews, by: { $0 === $1 }) else {
            // Before this no-op guard existed, assigning the identical array
            // still completed a layout pass and reset this flag.
            shouldAnimateNextLayoutPass = true
            return
        }
        shouldAnimateNextLayoutPass = shouldAnimateReconciledLayout
        arrangedViews = newViews
    }

    /// Whether an existing view still represents the same live status-item
    /// window after a cache refresh.
    ///
    /// Full `MenuBarItem` equality includes origin and on-screen state, both of
    /// which necessarily change during a move. Ignore only those transient
    /// fields; every value retained by `LayoutBarItemView` must still match.
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
    /// - Parameters:
    ///   - draggingInfo: The dragging information to use to update the
    ///     container's arranged views.
    ///   - phase: The current dragging phase of the container.
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
            // convert dragging location from window coordinates
            let draggingLocation = convert(draggingInfo.draggingLocation, from: nil)
            // When dragging a regular item (not the badge), exclude the badge
            // from being a swap destination. The badge position should only
            // change when the user explicitly drags the badge itself.
            let excludeBadge = !sourceView.isNewItemsBadge
            // Updating normally relies on the presence of other arranged
            // views. A section containing only the New Items badge should
            // still accept regular item drops; otherwise the badge becomes a
            // dead zone that prevents moving the first icon into the section.
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
                // don't rearrange if destination is disabled
                destinationView.isEnabled,
                // don't rearrange if in the middle of an animation
                destinationView.layer?.animationKeys() == nil,
                let destinationIndex = arrangedViews.firstIndex(of: destinationView)
            else {
                return .move
            }
            // drag must be near the horizontal center of the destination
            // view to trigger a swap
            let midX = destinationView.frame.midX
            let offset = destinationView.frame.width / 2
            if !((midX - offset) ... (midX + offset)).contains(draggingLocation.x),
               sourceView.oldContainerInfo?.container === self
            {
                return .move
            }
            if let sourceIndex = arrangedViews.firstIndex(of: sourceView) {
                // source view is already inside this container, so move
                // it from its old index to the new one
                var targetIndex = destinationIndex
                if destinationIndex > sourceIndex {
                    targetIndex += 1
                }
                arrangedViews.move(fromOffsets: [sourceIndex], toOffset: targetIndex)
            } else {
                // source view is being dragged from another container,
                // so transfer array ownership before adopting the NSView.
                // NSView.addSubview moves the view between superviews, but it
                // cannot remove the stale reference from the source's
                // arrangedViews; leaving that reference lets the source
                // detach the icon from this destination during reconciliation.
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

    /// Returns a cancelled drag's original view to this container before
    /// cache-driven updates resume. Restoring the existing instance first is
    /// important: thawing this row while the view still belongs to another
    /// row makes the old cache construct a replacement, briefly duplicating
    /// the icon when the detached drag view is inserted afterward.
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

    /// Returns the nearest arranged view to the given X position within
    /// the coordinate system of the container view.
    ///
    /// The nearest arranged view is defined as the arranged view whose
    /// horizontal center is closest to `xPosition`.
    ///
    /// - Parameters:
    ///   - xPosition: A floating point value representing an X position
    ///     within the coordinate system of the container view.
    ///   - excludingBadge: If `true`, the New Items badge is excluded from
    ///     consideration. Use this when dragging regular items to prevent
    ///     them from swapping with the badge.
    func arrangedView(nearestTo xPosition: CGFloat, excludingBadge: Bool = false) -> LayoutBarArrangedView? {
        let candidates = excludingBadge ? arrangedViews.filter { !$0.isNewItemsBadge } : arrangedViews
        return candidates.min { view1, view2 in
            let distance1 = abs(view1.frame.midX - xPosition)
            let distance2 = abs(view2.frame.midX - xPosition)
            return distance1 < distance2
        }
    }
}
