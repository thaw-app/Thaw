//
//  MenuBarSearchPanel+Actions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

extension MenuBarSearchPanel {
    /// By window when the row knew one, otherwise by tag.
    func cachedItem(withTag tag: MenuBarItemTag, windowID: CGWindowID?) -> MenuBarItem? {
        guard let itemManager = appState?.itemManager else {
            return nil
        }
        if let windowID {
            return itemManager.managedItem(withWindowID: windowID)
        }
        return itemManager.managedItem(withTag: tag)
    }

    /// The item a search list row stands for, if it is still in the cache.
    func cachedItem(for selection: MenuBarSearchModel.ItemID) -> MenuBarItem? {
        guard case let .item(tag, windowID) = selection else {
            return nil
        }
        return cachedItem(withTag: tag, windowID: windowID)
    }

    // MARK: Selection spotlight

    /// The selection-driven counterpart of LayoutBarItemView's hover spotlight.
    func observeSelectionForSpotlight() {
        selectionObservationTask?.cancel()
        selectionObservationTask = Task { @MainActor [weak self, weak model = self.model] in
            let changes = Observations { model?.selection }.removeDuplicates()
            for await _ in changes {
                guard let self else { return }
                retargetSpotlight()
            }
        }
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func warmCachesOnShow(appState: AppState) {
        guard presentation.warmsCachesOnShow else {
            return
        }
        // Cancelled in close() to avoid holding appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState] in
            guard let appState else { return }
            await appState.imageCache.ensureDiskLoaded()
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.recaptureIfWarranted()
            appState.imageCache.logCacheStatus("Search panel opened")
        }
    }

    // MARK: - Actions, Spotlight, Rename & Color Sampling

    private func retargetSpotlight() {
        endSpotlight()
        guard
            presentation.spotlightsSelection, isVisible, let selection = model.selection, let item = cachedItem(for: selection),
            // Control items and untitled items have no AX title to address.
            !item.isControlItem, let title = item.title, !title.isEmpty
        else {
            return
        }
        scheduleSpotlight(name: title)
    }

    /// Shorter delay than hover's, since a selection change is deliberate.
    private func scheduleSpotlight(name: String) {
        guard let spotlighting = MenuBarPresentationProvider.itemSpotlighting, spotlighting.isSupported else {
            return
        }
        spotlightedName = name
        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let landed = await spotlighting.setItemSpotlighted(true, forItemNamed: name)
            guard let self, !Task.isCancelled else {
                // Superseded mid-call: pair the true with a false.
                if landed {
                    Task { await spotlighting.setItemSpotlighted(false, forItemNamed: name) }
                }
                return
            }
            self.isSpotlighted = landed
        }
    }

    /// Pairs every true sent to the agent with a false.
    func endSpotlight() {
        spotlightTask?.cancel()
        spotlightTask = nil
        defer { spotlightedName = nil }
        guard isSpotlighted, let name = spotlightedName, let spotlighting = MenuBarPresentationProvider.itemSpotlighting else {
            return
        }
        isSpotlighted = false
        Task { await spotlighting.setItemSpotlighted(false, forItemNamed: name) }
    }

    /// The item the highlighted row stands for, if it is still in the cache.
    var selectedItem: MenuBarItem? {
        guard let selection = model.selection else {
            return nil
        }
        return cachedItem(for: selection)
    }

    /// A menu, not buttons, because group destinations have unknown length;
    /// it also matches the layout editor's right-click menu.
    func presentItemActions() {
        guard let appState, let anchor = itemActionsAnchor, let item = selectedItem else {
            return
        }

        let menu = MenuBarSearchItemActions.menu(for: item, appState: appState) { [weak self] in
            guard let self else { return }
            close()
            MenuBarSearchItemActions.openSettings(appState: appState)
        }
        menu.delegate = self
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    /// ⌘1 to ⌘3. A disabled section's number does nothing rather than
    /// renumbering the others.
    func moveSelection(toDestinationAt index: Int) {
        guard let appState, let item = selectedItem else {
            return
        }
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState)
        guard destinations.indices.contains(index), let section = destinations[index] else {
            return
        }
        MenuBarSearchItemActions.move(item, to: section, appState: appState)
    }

    func beginRenamingSelection() {
        guard case let .item(tag, windowID)? = model.selection, let item = cachedItem(withTag: tag, windowID: windowID) else {
            return
        }
        model.renameSession = .init(tag: tag, windowID: windowID, draft: item.customName ?? "")
    }

    /// An all-whitespace draft removes the custom name.
    func commitRename() {
        guard let session = model.renameSession else {
            return
        }
        model.renameSession = nil

        guard let item = cachedItem(withTag: session.tag, windowID: session.windowID) else {
            Self.diagLog.error("Cannot save custom name, no matching item")
            return
        }
        Self.diagLog.debug("Saving custom name for tag: \(session.tag)")

        var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        let newName = session.draft.trimmingCharacters(in: .whitespaces)
        if newName.isEmpty {
            names.removeValue(forKey: item.uniqueIdentifier)
        } else {
            names[item.uniqueIdentifier] = newName
        }
        Defaults.set(names, forKey: .menuBarItemCustomNames)
        // The launchers rank by names captured with their inventory; rebuild it.
        model.launcherCandidates = []
        // A Defaults write is not observed. Reassigning displayedItems is,
        // since the @Observable setter has no equality check, so rows re-render.
        // Routed through a local so it does not read as a typo'd x = x.
        let itemsToRerender = model.displayedItems
        model.displayedItems = itemsToRerender
    }

    /// Sampling costs a screen capture per showing, so only modes that preview
    /// items over the bar color do it. Switched per showing, since the mode can change.
    func updateMenuBarColorSampling() {
        let wanted = presentation.samplesMenuBarColor
        guard wanted != isSamplingMenuBarColor else {
            return
        }
        isSamplingMenuBarColor = wanted
        if wanted {
            model.attach(to: self, displayInvalidations: displayInvalidations)
        } else {
            model.detach()
        }
    }
}

// MARK: - Actions menu tracking

extension MenuBarSearchPanel: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        isPresentingItemActions = true
    }

    func menuDidClose(_: NSMenu) {
        isPresentingItemActions = false
        // Apply a dismissal suppressed while the menu was up. Tested now, not
        // remembered, since Escape closes the menu without the panel losing key.
        if !isKeyWindow {
            close()
        }
    }
}
