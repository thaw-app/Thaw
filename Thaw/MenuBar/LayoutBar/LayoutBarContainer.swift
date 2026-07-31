//
//  LayoutBarContainer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import PlatformRuntimeKit

/// A container for the items in the menu bar layout interface.
final class LayoutBarContainer: NSView {
    /// Visual styling for the background drawn behind a same-bundle cluster.
    private enum GroupChrome {
        static let cornerRadius: CGFloat = 7
        static let horizontalPadding: CGFloat = 2
        static let verticalPadding: CGFloat = 1
        static let fillAlpha: CGFloat = 0.10
        static let strokeAlpha: CGFloat = 0.22
        /// Horizontal space reserved to the left of a cluster for its drag handle.
        static let handleReservation: CGFloat = 15
    }

    /// The overlay grip views, one per detected cluster.
    private var groupHandleViews = [MenuBarItemGroupOrigin: LayoutBarGroupHandleView]()
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

    /// The container's arranged views.
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
    private var suppressLittleSnitchUnresolvedSlot = false

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
            Publishers.CombineLatest4(
                appState.itemManager.$itemCache,
                appState.itemManager.$newItemsPlacement,
                appState.settings.advanced.$enableAlwaysHiddenSection,
                appState.settings.advanced.$enableExperimentalSystemItemHiding
            )
            .sink { [weak self] cache, _, _, _ in
                guard let self else {
                    return
                }
                setArrangedViews(items: cache.managedItems(for: section))
            }
            .store(in: &c)

            // Group membership is an input to layout (the handle gap) and to
            // drawing (the cluster chrome), and it changes independently of the
            // item cache — creating or dissolving a group touches no item.
            // Without this, an edit would not show until something else forced
            // a pass. Skipped while a drag has frozen updates, exactly like the
            // cache observer above.
            appState.itemGroupManager.$groupSet
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self, canSetArrangedViews else {
                        return
                    }
                    needsLayout = true
                    needsDisplay = true
                }
                .store(in: &c)

            // Observe average color changes to update badge appearance
            appState.menuBarManager.$averageColorInfo
                .removeDuplicates()
                .sink { [weak self] colorInfo in
                    guard let self else {
                        return
                    }
                    // Update the color info on the badge view
                    if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = colorInfo
                    }
                }
                .store(in: &c)

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

            Publishers.Merge(
                NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification),
                NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: section))
            }
            .store(in: &c)

            NotificationCenter.default
                .publisher(for: .menuBarAgentPositionsDidChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    setArrangedViews(items: appState.itemManager.itemCache.managedItems(for: section))
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

    /// Re-runs layout for the container after one arranged view changed size.
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
            view.removeFromSuperview()
            view.hasContainer = false
        }

        // track the running x coordinate for the next view's origin
        var previousMaxX: CGFloat = 0

        // get the max height of all arranged views to calculate the
        // y coordinate of each view's origin
        let maxHeight = arrangedViews.lazy
            .map(\.bounds.height)
            .max() ?? 0

        // Reserve a leading gap before the first member of each cluster so its
        // drag handle has room to sit without overlapping any item.
        let resolved = resolvedGroups()
        let groups = Dictionary(
            resolved.map { ($0.origin, $0.memberIndices) },
            uniquingKeysWith: { first, _ in first }
        )
        let groupStarts = Set(resolved.compactMap(\.memberIndices.first))

        for (index, entry) in arrangedViews.enumerated() {
            var view: NSView = entry
            if subviews.contains(entry) {
                // view already exists inside the layout view, but may
                // have moved from its previous location;
                if shouldAnimateNextLayoutPass {
                    // replace the view with its animator proxy
                    view = entry.animator()
                }
            } else {
                // view does not already exist inside the layout view;
                // add it as a subview
                addSubview(entry)
                entry.hasContainer = true
            }

            let originX = previousMaxX + (groupStarts.contains(index) ? GroupChrome.handleReservation : 0)

            // set the view's origin; if the view is an animator proxy,
            // it will animate to the new position; otherwise, it must
            // be a newly added view
            view.setFrameOrigin(
                CGPoint(
                    x: originX,
                    y: (maxHeight / 2) - entry.bounds.midY
                )
            )

            previousMaxX = originX + entry.bounds.width
        }

        // update the width and height constraints using the information
        // collected while iterating
        widthConstraint.constant = previousMaxX
        heightConstraint.constant = maxHeight

        // Position the cluster drag handles in their reserved gaps, and refresh
        // the cluster backgrounds (both are derived from the view frames just set).
        updateGroupHandles(groups: groups)
        needsDisplay = true
    }

    /// Rebuilds the cluster drag-handle overlays to match the current groups.
    ///
    /// Handles are cheap and stateless, so they are recreated each layout pass
    /// rather than diffed; a handle drag freezes `canSetArrangedViews`, so this
    /// never runs mid-drag to invalidate the active dragging source.
    ///
    /// `groups` are member-index lists (a bundle's members may not be adjacent).
    /// One handle serves the whole bundle and carries every member's identifier,
    /// so dragging it gathers all members — not just a contiguous subset.
    /// Positions one drag handle per group, reusing the existing handle for a
    /// group that is still present.
    ///
    /// Reuse rather than teardown-and-rebuild: a handle destroyed and recreated
    /// every layout pass cannot hold per-group state (hover, and later collapse),
    /// and rebuilding mid-interaction would drop the handle out from under a
    /// cursor that is already on it.
    private func updateGroupHandles(groups: [MenuBarItemGroupOrigin: [Int]]) {
        var reusable = groupHandleViews
        var live = [MenuBarItemGroupOrigin: LayoutBarGroupHandleView]()

        for (origin, memberIndices) in groups {
            let views = memberIndices.compactMap { arrangedViews.indices.contains($0) ? arrangedViews[$0] : nil }
            guard let first = views.first else {
                continue
            }
            let memberIdentifiers = views.compactMap { view -> String? in
                if case let .item(item) = view.kind {
                    return item.uniqueIdentifier
                }
                return nil
            }
            guard memberIdentifiers.count >= 2 else {
                continue
            }

            let handle: LayoutBarGroupHandleView
            if let existing = reusable.removeValue(forKey: origin) {
                handle = existing
                handle.memberIdentifiers = memberIdentifiers
            } else {
                handle = LayoutBarGroupHandleView(
                    sourceContainer: self,
                    sourceSection: section,
                    memberIdentifiers: memberIdentifiers
                )
                addSubview(handle)
            }

            let size = LayoutBarGroupHandleView.preferredSize(height: first.frame.height)
            handle.setFrameSize(size)
            handle.setFrameOrigin(
                CGPoint(
                    x: first.frame.minX - GroupChrome.handleReservation + ((GroupChrome.handleReservation - size.width) / 2),
                    y: first.frame.midY - (size.height / 2)
                )
            )
            live[origin] = handle
        }

        // Whatever was not claimed above belongs to a group that no longer exists.
        for (_, stale) in reusable {
            stale.removeFromSuperview()
        }
        groupHandleViews = live
    }

    /// Snapshots the member views of a cluster into a single drag image.
    ///
    /// Composites each member's own rendering left-to-right rather than caching
    /// the union rect. A group's members need not be adjacent, and caching the
    /// union would pull whatever sits *between* them into the drag image — so a
    /// scattered group appeared to be dragging its neighbours along.
    ///
    /// Returns the image plus the union rect (in this container's coordinates)
    /// so the caller can align the drag image under the cursor.
    func snapshotCluster(memberIdentifiers: [String]) -> (image: NSImage, rect: NSRect)? {
        let views = arrangedViews.filter { view in
            if case let .item(item) = view.kind {
                return memberIdentifiers.contains(item.uniqueIdentifier)
            }
            return false
        }
        guard let first = views.first else {
            return nil
        }
        let rect = views.dropFirst()
            .reduce(first.frame) { $0.union($1.frame) }
            .insetBy(dx: -GroupChrome.horizontalPadding, dy: -GroupChrome.verticalPadding)
            .intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else {
            return nil
        }

        let image = NSImage(size: rect.size)
        image.lockFocusFlipped(isFlipped)
        defer { image.unlockFocus() }

        for view in views {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                continue
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            // Position each member relative to the union rect's origin so the
            // composite lines up with where the cluster actually sits.
            let origin = CGPoint(x: view.frame.minX - rect.minX, y: view.frame.minY - rect.minY)
            rep.draw(in: CGRect(origin: origin, size: view.bounds.size))
        }
        return (image, rect)
    }

    /// The groups present among the arranged views: the user's authored groups
    /// first, then automatic same-bundle clusters over whatever is left.
    ///
    /// The single authority every part of this view asks — chrome, handles, and
    /// (later) collapse all read this, so there is exactly one answer to "what
    /// group is this item in".
    ///
    /// Only item views carry a bundle tag; the badge and opaque slots are mapped
    /// to a non-groupable placeholder so they are never members.
    ///
    /// Returns nothing on the legacy backend. Grouping is a macOS 27 feature —
    /// there `sectionController` is nil, so every group commit optional-chains
    /// into a no-op. Drawing chrome and a draggable handle that silently do
    /// nothing is worse than showing no affordance at all.
    func resolvedGroups() -> [ResolvedGroup] {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding,
              let appState
        else {
            return []
        }
        let tags: [MenuBarItemTag] = arrangedViews.map { view in
            if case let .item(item) = view.kind {
                return item.tag
            }
            return .visibleControlItem
        }
        return MenuBarItemGroupResolver.resolve(tags: tags, groupSet: appState.itemGroupManager.groupSet)
    }

    /// The member-index lists of each group. A group's members may not be
    /// adjacent, so each entry is the full set of member indices rather than a
    /// contiguous range.
    private func groupedMemberIndices() -> [[Int]] {
        resolvedGroups().map(\.memberIndices)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for memberIndices in groupedMemberIndices() {
            // A bundle's members may be scattered; draw one rounded background
            // per contiguous sub-run so the chrome never encloses foreign items
            // that happen to sit between members. One handle still moves them all.
            for run in Self.contiguousRuns(of: memberIndices) {
                let views = run.compactMap { arrangedViews.indices.contains($0) ? arrangedViews[$0] : nil }
                guard let first = views.first else {
                    continue
                }
                let union = views.dropFirst().reduce(first.frame) { $0.union($1.frame) }
                let rect = union
                    .insetBy(dx: -GroupChrome.horizontalPadding, dy: -GroupChrome.verticalPadding)
                    .intersection(bounds)
                guard !rect.isNull, !rect.isEmpty else {
                    continue
                }
                let path = NSBezierPath(
                    roundedRect: rect,
                    xRadius: GroupChrome.cornerRadius,
                    yRadius: GroupChrome.cornerRadius
                )
                NSColor.secondaryLabelColor.withAlphaComponent(GroupChrome.fillAlpha).setFill()
                path.fill()
                NSColor.separatorColor.withAlphaComponent(GroupChrome.strokeAlpha).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    /// Splits an ascending index list into its maximal contiguous runs.
    private static func contiguousRuns(of indices: [Int]) -> [[Int]] {
        var runs = [[Int]]()
        for index in indices {
            if var last = runs.last, let tail = last.last, index == tail + 1 {
                last.append(index)
                runs[runs.count - 1] = last
            } else {
                runs.append([index])
            }
        }
        return runs
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
        let runningApplications = NSWorkspace.shared.runningApplications
        let runningBundleIdentifiers = Set(runningApplications.compactMap(\.bundleIdentifier))
        let littleSnitchRunning = runningBundleIdentifiers.contains(
            LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier
        )
        suppressLittleSnitchUnresolvedSlot = LayoutOpaqueSlotDescriptor.shouldSuppressUnresolvedSlot(
            in: items,
            littleSnitchRunning: littleSnitchRunning,
            wasSuppressed: suppressLittleSnitchUnresolvedSlot
        )
        let positions: [String: Int]
        let opaqueSlot: LayoutOpaqueSlotDescriptor?
        if #available(macOS 27, *), section == .visible {
            positions = RuntimePositionStore.currentPositions()
            opaqueSlot = LayoutOpaqueSlotDescriptor.littleSnitch(
                runningBundleIdentifiers: runningBundleIdentifiers,
                positions: positions
            )
        } else {
            positions = [:]
            opaqueSlot = nil
        }
        let displayedItems = LayoutOpaqueSlotDescriptor.itemsForLayout(
            items,
            suppressUnresolvedSlot: suppressLittleSnitchUnresolvedSlot
        )

        var newViews = [LayoutBarArrangedView]()
        let itemIdentifiers = displayedItems.map(\.uniqueIdentifier)
        let badgeIndex = appState.itemManager.newItemsBadgeIndex(in: section, itemIdentifiers: itemIdentifiers)
        for item in displayedItems {
            if let existingView = arrangedViews.first(where: {
                if case let .item(existingItem) = $0.kind {
                    return existingItem == item
                }
                return false
            }) {
                newViews.append(existingView)
            } else {
                let view = LayoutBarItemView(appState: appState, item: item)
                newViews.append(view)
            }
        }

        if #available(macOS 27, *), let opaqueSlot {
            let opaqueView = arrangedViews.first(where: {
                if case let .opaqueSlot(existing) = $0.kind {
                    return existing == opaqueSlot
                }
                return false
            }) ?? LayoutOpaqueSlotView(
                descriptor: opaqueSlot,
                runningApplications: runningApplications
            )
            let insertionIndex = opaqueSlot
                .insertionIndex(in: displayedItems, positions: positions)
                .clamped(to: newViews.startIndex ... newViews.endIndex)
            newViews.insert(opaqueView, at: insertionIndex)
        }
        var newlyCreatedBadgeView: LayoutBarNewItemsBadgeView?
        if let badgeIndex {
            let existingBadgeView = arrangedViews.first(where: { $0.isNewItemsBadge })
            let badgeView = existingBadgeView as? LayoutBarNewItemsBadgeView ?? LayoutBarNewItemsBadgeView()
            if existingBadgeView == nil {
                newlyCreatedBadgeView = badgeView
            }
            badgeView.averageColorInfo = appState.menuBarManager.averageColorInfo
            let opaqueIndex = newViews.firstIndex {
                if case .opaqueSlot = $0.kind {
                    return true
                }
                return false
            }
            let adjustedBadgeIndex = if let opaqueIndex, opaqueIndex < badgeIndex {
                badgeIndex + 1
            } else {
                badgeIndex
            }
            let insertionIndex = adjustedBadgeIndex.clamped(to: newViews.startIndex ... newViews.endIndex)
            newViews.insert(badgeView, at: insertionIndex)
        }
        arrangedViews = newViews
        newlyCreatedBadgeView?.animateAppearance()
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
        // Refuse a drag of a reorderable-but-not-hideable denylisted item into
        // a non-visible section: show the no-drop cursor instead of letting it
        // settle, mirroring the rejection in performDragOperation. Visible-section
        // drops (reorders) are always allowed.
        if case let .item(item) = sourceView.kind {
            let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
            if item.tag.isLayoutAnchoredSystemItem,
               sourceView.oldContainerInfo?.container === self,
               !LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: appState)
            {
                return []
            }
            // A member drag carries its whole group, so every member has to be
            // assignable here — not just the one under the cursor. Otherwise the
            // cursor promises a drop that `setSection(_:items:atomically:)` will
            // refuse on release.
            let members = dragUnitViews(for: sourceView).compactMap { view -> MenuBarItem? in
                if case let .item(member) = view.kind {
                    member
                } else {
                    nil
                }
            }
            let assignable = members.isEmpty ? [item] : members
            if !assignable.allSatisfy({
                MenuBarSectionController.canAssign(
                    $0,
                    to: section,
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
            }) {
                return []
            }
        }
        switch phase {
        case .entered:
            if !arrangedViews.contains(sourceView) {
                shouldAnimateNextLayoutPass = false
            }
            return updateArrangedViewsForDrag(with: draggingInfo, phase: .updated)
        case .exited:
            if arrangedViews.contains(sourceView) {
                shouldAnimateNextLayoutPass = false
                // Pull the whole unit out, not just the dragged view — leaving
                // its siblings behind would split the cluster on screen while
                // the drop relocates all of them.
                let unit = Set(dragUnitViews(for: sourceView).map(ObjectIdentifier.init))
                arrangedViews.removeAll { unit.contains(ObjectIdentifier($0)) }
            }
            return .move
        case .updated:
            if
                sourceView.oldContainerInfo == nil,
                let sourceIndex = arrangedViews.firstIndex(of: sourceView)
            {
                sourceView.oldContainerInfo = (self, sourceIndex)
            }
            // updating normally relies on the presence of other arranged views,
            // but if the container is empty, it needs to be handled separately
            guard !arrangedViews.filter(\.isEnabled).isEmpty else {
                arrangedViews.insert(sourceView, at: 0)
                return .move
            }
            // convert dragging location from window coordinates
            let draggingLocation = convert(draggingInfo.draggingLocation, from: nil)
            // When dragging a regular item (not the badge), exclude the badge
            // from being a swap destination. The badge position should only
            // change when the user explicitly drags the badge itself.
            let excludeBadge = !sourceView.isNewItemsBadge
            // The whole group travels together, so a drop onto any of its own
            // members is a no-op rather than a reorder.
            let unitViews = dragUnitViews(for: sourceView)
            sourceView.dragUnitCount = unitViews.count
            let unitIdentities = Set(unitViews.map(ObjectIdentifier.init))
            guard
                let destinationView = arrangedView(nearestTo: draggingLocation.x, excludingBadge: excludeBadge),
                !unitIdentities.contains(ObjectIdentifier(destinationView)),
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
                // `placeBlock` gathers the unit's members — which may be
                // scattered — and reinserts them contiguously at the drop
                // cursor. For a one-view unit it reduces exactly to the
                // `move(fromOffsets:toOffset:)` this replaced.
                let memberIndices = unitViews.compactMap { arrangedViews.firstIndex(of: $0) }
                arrangedViews = MenuBarItemGroupResolver.placeBlock(
                    arrangedViews,
                    memberIndices: memberIndices,
                    toIndexInOriginal: targetIndex
                )
            } else {
                // source view is being dragged from another container,
                // so just insert it
                arrangedViews.insert(contentsOf: unitViews, at: destinationIndex)
            }
            return .move
        case .ended:
            return .move
        }
    }

    /// The items currently arranged here, in display order, for menu building.
    ///
    /// Taken from `arrangedViews` rather than the cache so the menu reasons
    /// about exactly what the user is looking at, including any mid-drag state.
    func orderedItemsForMenu() -> [MenuBarItem] {
        arrangedViews.compactMap { view in
            if case let .item(item) = view.kind { item } else { nil }
        }
    }

    /// The arranged views a single drag moves as one block: every member of the
    /// group containing `view`, in current left-to-right order, or just `view`
    /// when it belongs to no group.
    ///
    /// Dragging any member moves the whole group, so the mid-drag preview has to
    /// move the whole block too. If it moved only the dragged view, the cluster
    /// would visibly split while the drop relocates all of it — the preview
    /// would be lying about what is going to happen.
    func dragUnitViews(for view: LayoutBarArrangedView) -> [LayoutBarArrangedView] {
        guard let index = arrangedViews.firstIndex(of: view) else {
            return [view]
        }
        let indices = MenuBarItemGroupResolver.dragUnitIndices(
            forIndex: index,
            in: resolvedGroups()
        )
        let views = indices.compactMap { arrangedViews.indices.contains($0) ? arrangedViews[$0] : nil }
        return views.isEmpty ? [view] : views
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
