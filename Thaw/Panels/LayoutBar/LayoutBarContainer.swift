//
//  LayoutBarContainer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

/// The view that arranges one section's item views inside the layout editor.
///
/// Places subviews by frame in one left-to-right sweep and publishes the extent
/// through two size pins, so reorders animate per view while the stack still
/// sees a defined size.
final class LayoutBarContainer: NSView {
    private static let diagLog = DiagLog(category: "LayoutBarContainer")
    /// Simple Mode's card radius, mirrored here because this AppKit view does
    /// not import ThawUI (single-source value; see ThawGlass.swift).
    private static let cardRadius: CGFloat = 16
    /// Styling for the background behind a same-bundle cluster, matching
    /// the Thaw Bar's card radius and half-opacity hairline border.
    private enum GroupChrome {
        static let cornerRadius: CGFloat = LayoutBarContainer.cardRadius
        static let horizontalPadding: CGFloat = 2
        static let verticalPadding: CGFloat = 1
        static let fillAlpha: CGFloat = 0.10
        static let strokeAlpha: CGFloat = 0.5
        static let strokeWidth: CGFloat = 0.5
        /// Horizontal space reserved to the left of a cluster for its drag handle.
        static let handleReservation: CGFloat = 15
    }

    /// The overlay grip views, one per detected cluster.
    private var groupHandleViews = [MenuBarItemGroupOrigin: LayoutBarGroupHandleView]()
    /// The step of a drag session that a call to handleDrag(_:phase:)
    /// stands for.
    ///
    /// Mirrors the NSDraggingDestination callbacks the padding view replays,
    /// so a drag across sections stays one gesture.
    enum DragPhase {
        case entered, exited, updated, ended
    }

    /// The pair of constraints whose constants are rewritten at the end of each
    /// layout pass to publish how much room this section currently needs.
    ///
    /// The container's only statement of its size. Lazy because the anchors
    /// need self; kept so a pass mutates a constant, not the constraint graph.
    private lazy var sizePins: (width: NSLayoutConstraint, height: NSLayoutConstraint) = {
        let width = widthAnchor.constraint(equalToConstant: 0)
        let height = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([width, height])
        return (width, height)
    }()

    /// Weak: the app state outlives the settings window that owns this view.
    private(set) weak var appState: AppState?

    /// The menu bar section this container stands for. Every item view it holds
    /// is currently assigned to that section.
    let section: MenuBarSection.Name

    /// Whether the next layout pass moves already-parented views through their
    /// animator proxies instead of snapping them to their new frames.
    ///
    /// One-shot: every pass resets it to true, so clear it right before a pass
    /// that must not animate, as drag bookkeeping does.
    var animatesNextLayoutPass = false

    /// Whether model-driven refreshes are allowed to replace arrangedViews.
    ///
    /// A drag clears this so a refresh cannot discard the preview. Refreshes
    /// are dropped, not queued, so restoring it re-reads the cache.
    var acceptsViewUpdates = true {
        didSet {
            guard acceptsViewUpdates, !oldValue else { return }
            rebuildViews()
        }
    }

    /// The item views this container positions, in the order they are drawn.
    ///
    /// Index zero is leftmost. Each assignment reflows against the previous
    /// contents, detaching dropped views and animating moved ones.
    var arrangedViews = [LayoutBarArrangedView]() {
        didSet {
            // The membership of the views is one of the two inputs to group
            // resolution, so the memo is stale before the reflow reads it.
            cachedResolvedGroups = nil
            reflowViews(replacing: oldValue)
        }
    }

    /// The last answer from resolvedGroups() and the group set it was
    /// computed against.
    ///
    /// Asked for on every draw and drag update but only invalidated by an
    /// arrangement swap or group edit. The stored set covers the gap before
    /// the group observer fires.
    private var cachedResolvedGroups: (groupSet: MenuBarItemGroupSet, groups: [ResolvedGroup])?

    /// The shared poll for hung owner processes, live only while the container
    /// is in a window. Each tick asks the window server once per distinct owner
    /// PID and pushes the answer into every item view that PID owns.
    private var unresponsiveOwnerPoller: AnyCancellable?

    private var cancellables = Set<AnyCancellable>()

    /// Observes enableAlwaysHiddenSection and enableExperimentalSystemItemHiding,
    /// which are @Observable and so cannot join the Combine pipeline.
    private var advancedSettingsObservationTask: Task<Void, Never>?

    isolated deinit {
        advancedSettingsObservationTask?.cancel()
        unresponsiveOwnerPoller?.cancel()
    }

    /// Creates an empty container bound to one section of the layout editor.
    ///
    /// Not registered for dragging: the wrapping padding view receives drops
    /// and decides which container the cursor is over.
    ///
    /// - Parameters:
    ///   - appState: State container the item cache and settings are read from.
    ///   - section: The section this container represents.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.appState = appState
        self.section = section
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()
        subscribeToModelUpdates()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Tracks the last known notch state to avoid redundant badge updates.
    private var lastScreenHasNotch: Bool?

    /// Wires up everything that can invalidate the arrangement: the item cache,
    /// group membership, the badge's backdrop color, and the app and screen
    /// changes that none of those publishers observe on their own.
    private func subscribeToModelUpdates() {
        var subscriptions = Set<AnyCancellable>()

        if let appState {
            // MenuBarItemManager is @Observable; one Observations sequence
            // covers the pair.
            let rebuildTask = Task { @MainActor [weak self, itemManager = appState.itemManager] in
                let changes = Observations {
                    (itemManager.itemCache, itemManager.newItemsPlacement, itemManager.thawBarOnlyIdentifiers,
                     MenuBarItemIconChoices.shared.revision)
                }
                for await _ in changes {
                    guard let self else { return }
                    rebuildViews()
                }
            }
            AnyCancellable { rebuildTask.cancel() }
                .store(in: &subscriptions)

            // @Published emits before the property changes. Rebuild on the
            // next run-loop turn, using the committed assignment and order.
            appState.menuBarManager.sectionLayoutChanges
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    rebuildViews()
                }
                .store(in: &subscriptions)

            // These settings are @Observable, so they are observed separately
            // and rerun the same re-arrangement.
            let advancedSettings = appState.settings.advanced
            advancedSettingsObservationTask?.cancel()
            advancedSettingsObservationTask = Task { @MainActor [weak self] in
                let changes = Observations {
                    (advancedSettings.enableAlwaysHiddenSection, advancedSettings.enableExperimentalSystemItemHiding)
                }
                for await _ in changes {
                    guard let self else { return }
                    rebuildViews()
                }
            }

            // Group edits touch no item, so the cache observer misses them.
            // Skipped while a drag has frozen updates. Dedupe by hand, since
            // MenuBarItemGroupManager is @Observable.
            let groupSetTask = Task { @MainActor [weak self, itemGroupManager = appState.itemGroupManager] in
                let changes = Observations { itemGroupManager.groupSet }
                var previous: MenuBarItemGroupSet?
                var isFirst = true
                for await groupSet in changes {
                    guard let self else { return }
                    defer { isFirst = false }
                    guard !isFirst, groupSet != previous else {
                        previous = groupSet
                        continue
                    }
                    previous = groupSet
                    // Dropped even while frozen: the deferred thaw rebuilds the
                    // arrangement, but nothing in between may serve the old
                    // groups either.
                    cachedResolvedGroups = nil
                    guard acceptsViewUpdates else { continue }
                    needsLayout = true
                    needsDisplay = true
                }
            }
            AnyCancellable { groupSetTask.cancel() }
                .store(in: &subscriptions)

            // Switching the Thaw icon off or on changes no position and no
            // inventory, so nothing else here would rebuild for it.
            let showThawIconTask = Task { @MainActor [weak self, generalSettings = appState.settings.general] in
                let changes = Observations { generalSettings.showThawIcon }
                var previous: Bool?
                for await showThawIcon in changes {
                    guard let self else { return }
                    let changed = previous.map { $0 != showThawIcon } ?? false
                    previous = showThawIcon
                    if changed {
                        rebuildViews()
                    }
                }
            }
            AnyCancellable { showThawIconTask.cancel() }
                .store(in: &subscriptions)

            // The badge is inked against the tinted bar like its neighbours.
            // MenuBarManager is @Observable; dedupe by hand.
            let badgeColorTask = Task { @MainActor [weak self, menuBarManager = appState.menuBarManager, appearanceManager = appState.appearanceManager] in
                let changes = Observations {
                    MenuBarStyleTint.background(
                        menuBarManager.averageColorInfo,
                        tintedBy: appearanceManager.configuration.current
                    )
                }
                var previous: MenuBarAverageColorInfo??
                for await colorInfo in changes {
                    guard let self else { return }
                    guard colorInfo != previous else { continue }
                    previous = colorInfo
                    if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = colorInfo
                    }
                }
            }
            AnyCancellable { badgeColorTask.cancel() }
                .store(in: &subscriptions)

            // Observe screen parameter changes (moving between displays) to update badge
            DisplayTopology.shared.screenParametersChanged
                .sink { [weak self] in
                    guard let self else { return }
                    // Force update badge's color info and redraw when screen changes
                    if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                        badgeView.averageColorInfo = MenuBarStyleTint.currentBackground(appState: appState)
                    }
                }
                .store(in: &subscriptions)

            Publishers.Merge(
                NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification),
                NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                rebuildViews()
            }
            .store(in: &subscriptions)

            NotificationCenter.default
                .publisher(for: .menuBarAgentPositionsDidChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    rebuildViews()
                }
                .store(in: &subscriptions)

            // Moving the window between screens fires only
            // NSWindow.didChangeScreenNotification, not the screen-parameters one.
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
                .store(in: &subscriptions)
        }

        cancellables = subscriptions
    }

    /// Runs the hung-owner poll only while there is a window to draw into.
    ///
    /// A closed but retained editor must not keep the window server busy.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            unresponsiveOwnerPoller = nil
            return
        }
        guard unresponsiveOwnerPoller == nil else {
            return
        }
        unresponsiveOwnerPoller = Timer.publish(every: 2, tolerance: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollUnresponsiveOwners()
            }
    }

    /// Asks the window server about each distinct owner once and fans the
    /// answer out to that owner's item views.
    ///
    /// IPC is bounded by distinct owners, not views; a view redraws only when
    /// its flag flips.
    private func pollUnresponsiveOwners() {
        let itemViews = arrangedViews.compactMap { $0 as? LayoutBarItemView }
        guard !itemViews.isEmpty else {
            return
        }
        let unresponsivePIDs = Set(itemViews.map(\.item.ownerPID))
            .filter { Bridging.isProcessUnresponsive($0) }
        for view in itemViews {
            view.isOwnerUnresponsive = unresponsivePIDs.contains(view.item.ownerPID)
            view.visibilityLimit = appState.flatMap {
                LayoutBarVisibilityLimit.limit(for: view.item, in: section, appState: $0)
            }
        }
    }

    /// Updates the badge view's color info when the screen changes (notch detection)
    private func updateBadgeForScreenChange() {
        let currentHasNotch = NSScreen.screenWithActiveMenuBar?.hasNotch ?? false
        if lastScreenHasNotch != currentHasNotch {
            lastScreenHasNotch = currentHasNotch
            if let badgeView = arrangedViews.first(where: { $0.isNewItemsBadge }) {
                badgeView.averageColorInfo = appState.flatMap { MenuBarStyleTint.currentBackground(appState: $0) }
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
        animatesNextLayoutPass = false
        reflowViews()
    }

    /// Places every arranged view and republishes the container's size.
    ///
    /// Detaches dropped views, lays the rest end to end centered on the
    /// tallest, and animates moves when animatesNextLayoutPass allows.
    ///
    /// - Parameter previous: The arrangement being replaced. Defaults to the
    ///   current one, for a same-contents pass such as an item changing size.
    private func reflowViews(replacing previous: [LayoutBarArrangedView]? = nil) {
        defer {
            // Honor Reduce Motion: reorder slides are decorative.
            animatesNextLayoutPass = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        detachViews(missingFrom: previous ?? arrangedViews)

        let rowHeight = arrangedViews.map(\.bounds.height).max() ?? 0

        // A cluster's grip lives in an empty strip ahead of its first member,
        // so the sweep has to widen there before placing that member.
        let clusters = resolvedGroups()
        let membership = Dictionary(
            clusters.map { ($0.origin, $0.memberIndices) },
            uniquingKeysWith: { first, _ in first }
        )
        let clusterLeaders = Set(clusters.compactMap(\.memberIndices.first))

        var sweepX: CGFloat = 0
        for (index, arranged) in arrangedViews.enumerated() {
            let placed: NSView
            if subviews.contains(arranged) {
                placed = animatesNextLayoutPass ? arranged.animator() : arranged
            } else {
                addSubview(arranged)
                arranged.hasContainer = true
                placed = arranged
            }

            if clusterLeaders.contains(index) {
                sweepX += GroupChrome.handleReservation
            }
            placed.setFrameOrigin(
                CGPoint(
                    x: sweepX,
                    y: (rowHeight / 2) - arranged.bounds.midY
                )
            )
            sweepX += arranged.bounds.width
        }

        sizePins.width.constant = sweepX
        sizePins.height.constant = rowHeight

        // Grips and cluster chrome are both read off the frames the sweep just
        // assigned, so neither can be brought up to date any earlier.
        updateGroupHandles(groups: membership)
        needsDisplay = true
    }

    /// Detaches the views previous held that the current arrangement no longer
    /// wants, and tells each of them it is homeless so a cancelled drag knows to
    /// put it back.
    private func detachViews(missingFrom previous: [LayoutBarArrangedView]) {
        for view in previous where !arrangedViews.contains(view) {
            view.removeFromSuperview()
            view.hasContainer = false
        }
    }

    /// Positions one drag handle per group, reusing the existing handle for a
    /// group that is still present.
    ///
    /// Reused so hover and collapse state survive. One handle carries every
    /// member, adjacent or not, so dragging it gathers them all.
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
    /// Composites each member rather than the union rect, which would pull in
    /// non-member neighbours. Also returns the union rect for alignment.
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
    /// The single authority for group membership. The badge and opaque slots
    /// are never members. Memoized; the group set is compared here rather than
    /// trusted to the observer alone.
    func resolvedGroups() -> [ResolvedGroup] {
        guard let appState else {
            return []
        }
        let groupSet = appState.itemGroupManager.groupSet
        if let cached = cachedResolvedGroups, cached.groupSet == groupSet {
            return cached.groups
        }
        let tags: [MenuBarItemTag] = arrangedViews.map { view in
            if case let .item(item) = view.kind {
                return item.tag
            }
            return .visibleControlItem
        }
        let groups = MenuBarItemGroupResolver.resolve(tags: tags, groupSet: groupSet)
        cachedResolvedGroups = (groupSet, groups)
        return groups
    }

    /// Member indices per group; members need not be contiguous.
    private func groupedMemberIndices() -> [[Int]] {
        resolvedGroups().map(\.memberIndices)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isDropTarget {
            // Drop-target highlight: an accent band along the container's
            // leading edge, aligned with the gutter title it lights up.
            let band = NSRect(x: bounds.minX, y: bounds.minY, width: 3, height: bounds.height)
            NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(rect: band).fill()
        }
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
                path.lineWidth = GroupChrome.strokeWidth
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

    /// Projects current assignments onto cached items, reusing existing views.
    /// Updates are deferred while dragging so a refresh cannot overwrite the drag.
    func rebuildViews() {
        guard
            let appState,
            acceptsViewUpdates
        else {
            return
        }
        let runningApplications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        // Section membership is authored state, not evidence of a physical move:
        // project the inventory without publishing stale geometry to the manager.
        let displayedItems = MenuBarBackendProvider.current.rebucket(
            appState.itemManager.itemCache,
            hider: appState.menuBarManager.sectionController,
            allowsAlwaysHidden: appState.settings.advanced.enableAlwaysHiddenSection
        ).retainingRunningOwners(
            processIDs: Set(runningApplications.map(\.processIdentifier)),
            bundleIdentifiers: Set(runningApplications.compactMap(\.bundleIdentifier))
        ).managedItems(for: section)
            // Thaw Bar Only items have their own row.
            .filter { !appState.itemManager.isThawBarOnly($0) }
            // A switched-off Thaw icon stays registered at zero width so it can
            // return in place, but it is not on the bar, so it gets no slot.
            .filter { appState.settings.general.showThawIcon || !$0.tag.matchesVisibleControlItem }

        refreshArrangedViews(for: displayedItems, runningApplications: runningApplications)
    }

    /// Rebuilds the section's arranged views from the fresh identifier list, keyed
    /// by canonical identifier: macOS 27's synthetic window IDs churn per refresh.
    private func refreshArrangedViews(
        for displayedItems: [MenuBarItem],
        runningApplications: [NSRunningApplication]
    ) {
        guard let appState else { return }
        let itemIdentifiers = displayedItems.map(\.uniqueIdentifier)
        let badgeIndex = appState.itemManager.newItemsBadgeIndex(in: section, itemIdentifiers: itemIdentifiers)

        // Index what is on screen first: a staying item keeps its view, its captured
        // image and any running animation. Duplicates resolve to the leftmost view.
        var recyclable = [String: LayoutBarArrangedView]()
        for view in arrangedViews {
            guard case let .item(shown) = view.kind else { continue }
            let identifier = MenuBarItemTag.canonicalPersistentIdentifier(shown.uniqueIdentifier)
            if recyclable[identifier] == nil {
                recyclable[identifier] = view
            }
        }
        var seenIdentifiers = Set<String>()
        var newViews = [LayoutBarArrangedView]()
        for item in displayedItems {
            let identifier = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
            guard seenIdentifiers.insert(identifier).inserted else { continue }
            // A recycled view is only valid for the same live item: its canonical
            // identifier can survive a refresh that mints a new synthetic window ID.
            if let recycled = recyclable[identifier] as? LayoutBarItemView,
               recycled.item.uniqueIdentifier == item.uniqueIdentifier
            {
                recycled.adopt(item: item, appState: appState)
                newViews.append(recycled)
            } else {
                newViews.append(LayoutBarItemView(appState: appState, item: item))
            }
        }

        // A pref-removed governable extra has no live AX element and would silently
        // vanish from the bar, so stand in a placeholder slot to keep it visible.
        if section != .visible {
            let sectionController = appState.menuBarManager.sectionController
            let liveIdentifiers = Set(
                displayedItems.map { MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) }
            )
            let placeholders = sectionController.sectionAssignment
                .filter { $0.value == section }
                .keys
                .compactMap { identifier -> LayoutOpaqueSlotDescriptor? in
                    let canonical = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
                    guard !liveIdentifiers.contains(canonical),
                          let title = MenuBarModuleDirectoryProvider.current.governableMenuExtraTitle(
                              forItemIdentifier: canonical
                          )
                    else { return nil }
                    return .governableExtra(
                        menuExtraTitle: title,
                        displayName: LayoutOpaqueSlotDescriptor.governableExtraDisplayName(
                            forMenuExtraTitle: title
                        )
                    )
                }
                .sorted { $0.title < $1.title }
            let assignedHere = sectionController.sectionAssignment.filter { $0.value == section }
            LayoutBarContainer.diagLog.debug(
                "governable placeholders (\(section.logString)): assigned=\(assignedHere.count) " +
                    "live=\(liveIdentifiers.count) placeholders=\(placeholders.count) " +
                    "[\(placeholders.map(\.title).joined(separator: ", "))]"
            )
            for descriptor in placeholders {
                let view = arrangedViews.first(where: {
                    if case let .opaqueSlot(existing) = $0.kind {
                        return existing == descriptor
                    }
                    return false
                }) ?? LayoutOpaqueSlotView(
                    descriptor: descriptor,
                    runningApplications: runningApplications,
                    capturedImage: descriptor.captureTag.flatMap { tag -> NSImage? in
                        appState.imageCache.image(for: tag).map {
                            NSImage(cgImage: $0.cgImage, size: $0.pointSize)
                        }
                    }
                )
                newViews.append(view)
            }
        }

        var newlyCreatedBadgeView: LayoutBarNewItemsBadgeView?
        if let badgeIndex {
            let existingBadgeView = arrangedViews.first(where: { $0.isNewItemsBadge })
            let badgeView = existingBadgeView as? LayoutBarNewItemsBadgeView ?? LayoutBarNewItemsBadgeView()
            if existingBadgeView == nil {
                newlyCreatedBadgeView = badgeView
            }
            badgeView.averageColorInfo = MenuBarStyleTint.currentBackground(appState: appState)
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
        // A Visible item hidden because another item of its app is concealed
        // is not on the bar; dim it so Layout does not claim otherwise.
        if section == .visible {
            for view in newViews {
                guard let itemView = view as? LayoutBarItemView else { continue }
                let hidingSection = appState.itemManager.sectionHidingItemWithItsApp(itemView.item, appState: appState)
                itemView.alphaValue = hidingSection == nil ? 1 : 0.4
                itemView.hiddenWithAppSection = hidingSection
            }
        }
        arrangedViews = newViews
        newlyCreatedBadgeView?.animateAppearance()
    }

    /// Advances the preview arrangement for one step of an in-flight drag.
    ///
    /// Preview only; nothing is written back to the model until the drop.
    ///
    /// - Parameters:
    ///   - draggingInfo: The live drag. Its source is the view being moved,
    ///     which may stand for a whole cluster.
    ///   - phase: Which of the drag callbacks this call stands for.
    /// - Returns: .move once the block is welcome here, or an empty operation
    ///   to refuse it, which the user sees as the no-drop cursor.
    @discardableResult
    func handleDrag(_ draggingInfo: NSDraggingInfo, phase: DragPhase) -> NSDragOperation {
        guard
            let sourceView = draggingInfo.draggingSource as? LayoutBarArrangedView,
            admitsDrag(of: sourceView)
        else {
            return []
        }
        switch phase {
        case .entered:
            // Arriving from elsewhere, the block has no frame in this container
            // to animate from, so its first placement has to be a hard cut.
            if !arrangedViews.contains(sourceView) {
                animatesNextLayoutPass = false
            }
            setIsDropTarget(true)
            return handleDrag(draggingInfo, phase: .updated)
        case .exited:
            setIsDropTarget(false)
            releaseDraggedBlock(from: sourceView)
            return .move
        case .updated:
            slideDraggedBlock(from: sourceView, toward: draggingInfo.draggingLocation)
            return .move
        case .ended:
            setIsDropTarget(false)
            return .move
        }
    }

    /// Whether a drag is hovering this container; drives the drop-target highlight.
    private var isDropTarget = false {
        didSet {
            guard oldValue != isDropTarget else { return }
            needsDisplay = true
        }
    }

    private func setIsDropTarget(_ active: Bool) {
        guard isDropTarget != active else { return }
        isDropTarget = active
        // Light up the matching gutter title in the enclosing SwiftUI strip
        // (FoldedMenuBar) so the destination reads even before the cursor
        // crosses the strip.
        NotificationCenter.default.post(
            name: .layoutBarDragTargetChanged,
            object: nil,
            userInfo: ["section": section.rawValue, "active": active]
        )
    }

    /// Whether every item travelling with sourceView could actually be
    /// assigned to this section.
    ///
    /// Answered before any preview movement, so a drop this container would
    /// reject on release never looks acceptable on the way in.
    private func admitsDrag(of sourceView: LayoutBarArrangedView) -> Bool {
        // Only item views carry section eligibility; anything else (the badge,
        // a placeholder slot) is welcome wherever it is dropped.
        guard case let .item(item) = sourceView.kind else {
            return true
        }
        let experimentalSystemItemHiding = appState?.settings.advanced.enableExperimentalSystemItemHiding ?? false
        // A denylisted item may reorder but not hide; mirror the rejection in
        // performDragOperation with the no-drop cursor.
        if item.tag.isLayoutAnchoredSystemItem,
           sourceView.oldContainerInfo?.container === self,
           !LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: appState)
        {
            return false
        }
        // Every group member must be assignable, or the cursor promises a drop
        // that setSection(_:items:atomically:) refuses.
        let members = dragUnitViews(for: sourceView).compactMap { view -> MenuBarItem? in
            if case let .item(member) = view.kind {
                member
            } else {
                nil
            }
        }
        let assignable = members.isEmpty ? [item] : members
        return assignable.allSatisfy {
            MenuBarBackendProvider.current.canAssign(
                $0,
                to: section,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            )
        }
    }

    /// Takes the travelling block back out of the preview once the cursor has
    /// left this container, so the gap closes behind it.
    private func releaseDraggedBlock(from sourceView: LayoutBarArrangedView) {
        guard arrangedViews.contains(sourceView) else {
            return
        }
        animatesNextLayoutPass = false
        // Pull the whole unit out, or the cluster splits on screen.
        let unit = Set(dragUnitViews(for: sourceView).map(ObjectIdentifier.init))
        arrangedViews.removeAll { unit.contains(ObjectIdentifier($0)) }
    }

    /// Moves the travelling block to the slot windowLocation currently points
    /// at, leaving the arrangement untouched when the cursor has not committed
    /// to a slot yet.
    private func slideDraggedBlock(from sourceView: LayoutBarArrangedView, toward windowLocation: NSPoint) {
        // Remember where the block started the first time this container sees
        // it, so a drag that is later cancelled can be undone.
        if
            sourceView.oldContainerInfo == nil,
            let startIndex = arrangedViews.firstIndex(of: sourceView)
        {
            sourceView.oldContainerInfo = (self, startIndex)
        }
        // The badge moves only when it is the thing being dragged.
        let excludeBadge = !sourceView.isNewItemsBadge
        // No enabled neighbour means one possible slot. A badge-only lane
        // counts as empty.
        guard arrangedViews.contains(where: { $0.isEnabled && !(excludeBadge && $0.isNewItemsBadge) }) else {
            if !arrangedViews.contains(sourceView) {
                arrangedViews.insert(sourceView, at: 0)
            }
            return
        }
        let cursorX = convert(windowLocation, from: nil).x
        // The whole group travels together, so a drop onto any of its own
        // members is a no-op rather than a reorder.
        let unitViews = dragUnitViews(for: sourceView)
        sourceView.dragUnitCount = unitViews.count
        let unitIdentities = Set(unitViews.map(ObjectIdentifier.init))
        guard
            let target = closestView(toX: cursorX, excludingBadge: excludeBadge),
            !unitIdentities.contains(ObjectIdentifier(target)),
            target.isEnabled,
            // A view that is still animating is not where it looks like it is,
            // so measuring against its frame would fight the animation.
            target.layer?.animationKeys() == nil,
            let targetIndex = arrangedViews.firstIndex(of: target)
        else {
            return
        }
        // Swap only inside the target's width, so passing does not displace it.
        // Blocks from another container are exempt: they have no slot here yet.
        let reach = target.frame.width / 2
        if !((target.frame.midX - reach) ... (target.frame.midX + reach)).contains(cursorX),
           sourceView.oldContainerInfo?.container === self
        {
            return
        }
        guard let sourceIndex = arrangedViews.firstIndex(of: sourceView) else {
            // The block belongs to another container, so there is no old
            // position to vacate; it simply takes the target's slot.
            arrangedViews.insert(contentsOf: unitViews, at: targetIndex)
            return
        }
        // Moving within this container: passing the target from the left lands
        // beyond it, so the destination shifts by one in that direction.
        let insertionIndex = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        // placeBlock gathers scattered members and reinserts them
        // contiguously at the drop cursor.
        let memberIndices = unitViews.compactMap { arrangedViews.firstIndex(of: $0) }
        arrangedViews = MenuBarItemGroupResolver.placeBlock(
            arrangedViews,
            memberIndices: memberIndices,
            toIndexInOriginal: insertionIndex
        )
    }

    /// The items currently arranged here, in display order, for menu building.
    ///
    /// Taken from arrangedViews rather than the cache so the menu reasons
    /// about exactly what the user is looking at, including any mid-drag state.
    func orderedItemsForMenu() -> [MenuBarItem] {
        arrangedViews.compactMap { view in
            if case let .item(item) = view.kind {
                item
            } else {
                nil
            }
        }
    }

    /// The arranged views a single drag moves as one block: every member of the
    /// group containing view, in current left-to-right order, or just view
    /// when it belongs to no group.
    ///
    /// The preview moves the whole block so it matches what the drop does.
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

    /// The arranged view sitting closest to xPosition, comparing horizontal
    /// centers in this container's own coordinate space.
    ///
    /// Center, not edge, so a wide view does not swallow its neighbours' slots.
    /// Ties go to the leftmost view.
    ///
    /// - Parameters:
    ///   - xPosition: The coordinate to measure from, usually a dragging
    ///     location already converted out of window coordinates.
    ///   - excludingBadge: Pass true to keep the new-items badge out of the
    ///     running, so an ordinary drag never shoves it aside.
    func closestView(toX xPosition: CGFloat, excludingBadge: Bool = false) -> LayoutBarArrangedView? {
        let candidates = excludingBadge ? arrangedViews.filter { !$0.isNewItemsBadge } : arrangedViews
        return candidates
            .map { (view: $0, offset: abs($0.frame.midX - xPosition)) }
            .min { $0.offset < $1.offset }?
            .view
    }
}
