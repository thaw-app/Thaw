//
//  MenuBarItemImageCache+LiveRefresh.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

extension MenuBarItemImageCache {
    // MARK: Live Refresh

    /// Snapshot of navigation state read in a single MainActor hop.
    struct NavigationStateSnapshot {
        let isIceBarPresented: Bool
        let isSearchPresented: Bool
        let isAppFrontmost: Bool
        let isSettingsPresented: Bool
        let settingsNavigationIdentifier: SettingsNavigationIdentifier?
        let isItemHotkeyListExpanded: Bool
        let prefersAppIcon: Bool
    }

    /// Builds a NavigationStateSnapshot in a single MainActor hop.
    @MainActor
    func makeNavigationStateSnapshot() -> NavigationStateSnapshot {
        guard let appState else {
            return NavigationStateSnapshot(
                isIceBarPresented: false,
                isSearchPresented: false,
                isAppFrontmost: false,
                isSettingsPresented: false,
                settingsNavigationIdentifier: nil,
                isItemHotkeyListExpanded: false,
                prefersAppIcon: false
            )
        }
        return NavigationStateSnapshot(
            isIceBarPresented: appState.navigationState.isIceBarPresented,
            isSearchPresented: appState.navigationState.isSearchPresented,
            isAppFrontmost: appState.navigationState.isAppFrontmost,
            isSettingsPresented: appState.navigationState.isSettingsPresented,
            settingsNavigationIdentifier: appState.navigationState.settingsNavigationIdentifier,
            isItemHotkeyListExpanded: isItemHotkeyListExpanded,
            prefersAppIcon: appState.settings.advanced.alwaysUseAppIconForMenuBarItems
        )
    }

    /// A background capture runs only for a visible consumer, or when requested
    /// while the layout pane is open (#759).
    static nonisolated func shouldAllowBackgroundCapture(
        hasVisibleConsumer: Bool,
        allowBackgroundCapture: Bool,
        isSettingsPaneOpen: Bool
    ) -> Bool {
        hasVisibleConsumer || (allowBackgroundCapture && isSettingsPaneOpen)
    }

    /// Returns the identifiers a section needs in the next live capture.
    ///
    /// Visible consumers and global attention take the whole section; trigger-only
    /// demand is intersected with it so unrelated icons stay out of the batch.
    static nonisolated func requiredCaptureIdentifiers(
        availableIdentifiers: some Sequence<String>,
        consumerNeedsWholeSection: Bool,
        globalAttentionNeedsWholeSection: Bool,
        attentionTriggerIdentifiers: Set<String>
    ) -> Set<String> {
        let available = Set(availableIdentifiers)
        if consumerNeedsWholeSection || globalAttentionNeedsWholeSection {
            return available
        }
        return available.intersection(attentionTriggerIdentifiers)
    }

    /// Refreshes the cache for currently visible consumers, or keeps a warm
    /// background snapshot ready for the layout settings pane when no consumer
    /// is visible.
    func refreshVisibleConsumersOrPrewarmLayoutCache(allowBackgroundCapture: Bool = false) async {
        guard appState != nil else {
            return
        }

        let nav = await MainActor.run {
            makeNavigationStateSnapshot()
        }

        let hasVisibleConsumer = hasVisibleCaptureConsumer(nav: nav)

        // Background capture is gated by isSettingsPaneOpen (#759).
        guard Self.shouldAllowBackgroundCapture(
            hasVisibleConsumer: hasVisibleConsumer,
            allowBackgroundCapture: allowBackgroundCapture,
            isSettingsPaneOpen: isSettingsPaneOpen
        ) else {
            return
        }

        if hasVisibleConsumer {
            await updateCache(nav: nav)
        } else {
            await updateCache(
                sections: MenuBarSection.Name.allCases,
                allowBackgroundCapture: true,
                nav: nav
            )
        }
    }

    func hasVisibleCaptureConsumer(nav: NavigationStateSnapshot) -> Bool {
        // App-icon mode renders no capture, so no visible consumer needs one.
        if nav.prefersAppIcon {
            return false
        }
        if nav.isIceBarPresented || nav.isSearchPresented {
            return true
        }

        guard nav.isAppFrontmost, nav.isSettingsPresented else {
            return false
        }
        switch nav.settingsNavigationIdentifier {
        case .menuBarLayout:
            return true
        case .hotkeys:
            // Read from the snapshot so it stays race-free off the main actor.
            return nav.isItemHotkeyListExpanded
        default:
            return false
        }
    }

    @MainActor
    func hasVisibleCaptureConsumer() -> Bool {
        guard let appState else {
            return false
        }
        let nav = NavigationStateSnapshot(
            isIceBarPresented: appState.navigationState.isIceBarPresented,
            isSearchPresented: appState.navigationState.isSearchPresented,
            isAppFrontmost: appState.navigationState.isAppFrontmost,
            isSettingsPresented: appState.navigationState.isSettingsPresented,
            settingsNavigationIdentifier: appState.navigationState.settingsNavigationIdentifier,
            isItemHotkeyListExpanded: isItemHotkeyListExpanded,
            prefersAppIcon: appState.settings.advanced.alwaysUseAppIconForMenuBarItems
        )
        return hasVisibleCaptureConsumer(nav: nav)
    }

    @MainActor
    func startLiveRefreshIfNeeded() {
        guard appState != nil else {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
            return
        }

        // Called from synchronous sink closures, hence the Task.
        Task { [weak self] in
            guard let self else { return }
            let nav = await MainActor.run {
                self.makeNavigationStateSnapshot()
            }
            let globalAttentionDetection = self.appState?.settings.advanced.surfaceItemsSeekingAttention == true
            let needsRefresh = self.hasVisibleCaptureConsumer(nav: nav)
                || !self.attentionDetectionItemIdentifiers.isEmpty
                || globalAttentionDetection

            if needsRefresh {
                guard self.liveRefreshTask == nil else { return }
                MenuBarItemImageCache.diagLog.debug(
                    "Starting live refresh (iceBar=\(nav.isIceBarPresented), search=\(nav.isSearchPresented), settings=\(nav.isSettingsPresented), attentionTriggers=\(self.attentionDetectionItemIdentifiers.count), globalAttention=\(globalAttentionDetection))"
                )
                lastSCKRefreshAt = nil
                lastHiddenRefreshAt = nil
                lastAlwaysHiddenRefreshAt = nil
                self.liveRefreshTask = Task { [weak self] in
                    guard let self else { return }
                    await self.runLiveRefreshLoop()
                }
            } else {
                guard let task = self.liveRefreshTask else { return }
                MenuBarItemImageCache.diagLog.debug("Stopping live refresh")
                self.liveRefreshTask = nil
                task.cancel()
                await task.value
                guard self.liveRefreshTask == nil else { return }
                await MenuBarCaptureService.Connection.shared.recycle()
            }
        }
    }

    /// The centralized live refresh loop for image updates.
    ///
    /// One loop serves every consumer view. refreshImages is @concurrent; only
    /// navigation reads run on the main actor. Uses the weak appState to avoid a retain cycle.
    @MainActor
    private func runLiveRefreshLoop() async {
        MenuBarItemImageCache.diagLog.debug("Live refresh loop started")

        while !Task.isCancelled {
            guard let appState = self.appState else { break }
            let interval = appState.settings.advanced.iconRefreshInterval
            guard interval > 0 else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            let nav = appState.navigationState

            let preferredDisplayID = preferredCaptureDisplayID(appState: appState)
            guard let resolvedScreen = Self.resolveScreen(preferredDisplayID: preferredDisplayID) else {
                MenuBarItemImageCache.diagLog.warning("liveRefresh: no connected screens available, skipping")
                try? await Task.sleep(for: .seconds(max(interval, Self.minIconRefreshInterval)))
                continue
            }
            let screen = resolvedScreen.screen
            if resolvedScreen.usedFallback, let preferredDisplayID {
                MenuBarItemImageCache.diagLog.warning(
                    "liveRefresh: cached displayID \(preferredDisplayID) is not connected; using displayID \(screen.displayID)"
                )
            }

            // Sections a UI consumer needs in full. Trigger demand is per identifier
            // below, so one watched icon can't pull in a whole section.
            var consumerSections = Set<MenuBarSection.Name>()
            let isLayoutPane = nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .menuBarLayout
            let isHotkeyListVisible = nav.isSettingsPresented
                && nav.settingsNavigationIdentifier == .hotkeys
                && isItemHotkeyListExpanded
            if nav.isSearchPresented || isLayoutPane || isHotkeyListVisible {
                if nav.isSearchPresented, !isLayoutPane, !isHotkeyListVisible {
                    // Search is the only consumer here that can omit sections.
                    let advanced = appState.settings.advanced
                    consumerSections = Set(MenuBarSection.Name.allCases.filter { name in
                        switch name {
                        case .visible: advanced.searchIncludeVisible
                        case .hidden: advanced.searchIncludeHidden
                        case .alwaysHidden: advanced.searchIncludeAlwaysHidden
                        }
                    })
                } else {
                    consumerSections = Set(MenuBarSection.Name.allCases)
                }
            } else if nav.isIceBarPresented,
                      let current = appState.menuBarManager.iceBarPanel.currentSection
            {
                consumerSections = [current]
            }

            let globalAttentionDetection = appState.settings.advanced.surfaceItemsSeekingAttention
            let triggerAttentionIdentifiers = attentionDetectionItemIdentifiers
            guard !consumerSections.isEmpty
                || globalAttentionDetection
                || !triggerAttentionIdentifiers.isEmpty
            else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }

            // Every section, so trigger demand follows a watched item that moves.
            let sections = MenuBarSection.Name.allCases

            if appState.itemManager.lastMoveOperationOccurred(within: .seconds(2))
                || appState.itemManager.isResettingLayout
            {
                try? await Task.sleep(for: .seconds(max(interval, Self.minIconRefreshInterval)))
                continue
            }

            let scale = screen.backingScaleFactor
            let now = ContinuousClock.now
            var nextWake = now + .seconds(max(interval, Self.minIconRefreshInterval))

            var hiddenItems = [MenuBarItem]()
            var alwaysHiddenItems = [MenuBarItem]()
            var capturedTags = [MenuBarItemTag]()

            for section in sections {
                let availableItems = appState.itemManager.itemCache.managedItems(for: section)
                let requiredIdentifiers = Self.requiredCaptureIdentifiers(
                    availableIdentifiers: availableItems.map(\.tag.tagIdentifier),
                    consumerNeedsWholeSection: consumerSections.contains(section),
                    globalAttentionNeedsWholeSection: globalAttentionDetection && section != .visible,
                    attentionTriggerIdentifiers: triggerAttentionIdentifiers
                )
                let items = availableItems.filter {
                    requiredIdentifiers.contains($0.tag.tagIdentifier)
                }
                guard !items.isEmpty else { continue }
                guard let sectionInterval = MenuBarLiveRefreshPolicy.refreshInterval(
                    for: section,
                    target: interval
                ) else { continue }
                let duration = Duration.seconds(sectionInterval)

                switch section {
                case .visible:
                    if MenuBarLiveRefreshPolicy.isDue(
                        lastCaptureAt: lastSCKRefreshAt,
                        now: now,
                        interval: duration
                    ) {
                        lastSCKRefreshAt = now
                        MenuBarItemImageCache.diagLog.debug(
                            "liveRefresh (SCK): section=\(section.logString) items=\(items.count)"
                        )
                        await withCapturePermit {
                            await refreshImages(of: items, scale: scale, viaSCK: true)
                        }
                        capturedTags.append(contentsOf: items.map(\.tag))
                    }
                    nextWake = min(
                        nextWake,
                        MenuBarLiveRefreshPolicy.nextDeadline(
                            capturedAt: lastSCKRefreshAt ?? now,
                            interval: duration,
                            now: ContinuousClock.now
                        )
                    )
                case .hidden:
                    hiddenItems = items
                case .alwaysHidden:
                    alwaysHiddenItems = items
                }
            }

            // One offscreen request in flight. Always Hidden goes first when
            // both are due so Hidden at 30 fps cannot starve its 1 fps slot.
            let hiddenInterval = MenuBarLiveRefreshPolicy.refreshInterval(for: .hidden, target: interval)
            let alwaysInterval = MenuBarLiveRefreshPolicy.refreshInterval(for: .alwaysHidden, target: interval)
            let hiddenDue = !hiddenItems.isEmpty
                && hiddenInterval != nil
                && MenuBarLiveRefreshPolicy.isDue(
                    lastCaptureAt: lastHiddenRefreshAt,
                    now: now,
                    interval: .seconds(hiddenInterval ?? interval)
                )
            let alwaysDue = !alwaysHiddenItems.isEmpty
                && alwaysInterval != nil
                && MenuBarLiveRefreshPolicy.isDue(
                    lastCaptureAt: lastAlwaysHiddenRefreshAt,
                    now: now,
                    interval: .seconds(alwaysInterval ?? 1)
                )

            switch MenuBarLiveRefreshPolicy.nextOffscreenSection(
                hiddenDue: hiddenDue,
                alwaysHiddenDue: alwaysDue
            ) {
            case .hidden:
                lastHiddenRefreshAt = now
                MenuBarItemImageCache.diagLog.debug("liveRefresh (capture): hidden items=\(hiddenItems.count)")
                await withCapturePermit {
                    await refreshImages(of: hiddenItems, scale: scale)
                }
                capturedTags.append(contentsOf: hiddenItems.map(\.tag))
            case .alwaysHidden:
                lastAlwaysHiddenRefreshAt = now
                MenuBarItemImageCache.diagLog.debug(
                    "liveRefresh (capture): alwaysHidden items=\(alwaysHiddenItems.count)"
                )
                await withCapturePermit {
                    await refreshImages(of: alwaysHiddenItems, scale: scale)
                }
                capturedTags.append(contentsOf: alwaysHiddenItems.map(\.tag))
            case .visible, nil:
                break
            }

            await MainActor.run {
                storeImages(for: screen.displayID, capturedTags: capturedTags)
            }

            if let hiddenInterval, !hiddenItems.isEmpty {
                nextWake = min(
                    nextWake,
                    MenuBarLiveRefreshPolicy.nextDeadline(
                        capturedAt: lastHiddenRefreshAt ?? now,
                        interval: .seconds(hiddenInterval),
                        now: ContinuousClock.now
                    )
                )
            }
            if let alwaysInterval, !alwaysHiddenItems.isEmpty {
                nextWake = min(
                    nextWake,
                    MenuBarLiveRefreshPolicy.nextDeadline(
                        capturedAt: lastAlwaysHiddenRefreshAt ?? now,
                        interval: .seconds(alwaysInterval),
                        now: ContinuousClock.now
                    )
                )
            }

            let sleep = nextWake - ContinuousClock.now
            if sleep > .zero {
                try? await Task.sleep(for: sleep)
            }
        }

        MenuBarItemImageCache.diagLog.debug("Live refresh loop stopped")
    }
}
