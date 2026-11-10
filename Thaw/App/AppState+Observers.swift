//
//  AppState+Observers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation

extension AppState {
    // MARK: - Observers

    /// Subscribe after bootstrap because immediate current-value emissions must not reach a half-built subsystem graph.
    func installObservers() {
        cancellables.removeAll()

        observeActiveSpace()
        observeAppFocus()
        observeItemDrags()
        observeImageCacheTriggers()
        // Observation tracks owned-model reads through appState directly; no objectWillChange forwarding is needed.
        startDisplayChangeCoordinator()
    }

    /// Frontmost-app changes cover space notifications missed on secondary displays.
    /// Sample clicks immediately and again later because fullscreen notifications can precede window-server updates.
    private func observeActiveSpace() {
        let spaceSwitched = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .replace(with: ())
            .eraseToAnyPublisher()

        let appSwitched = NSWorkspace.shared
            .publisher(for: \.frontmostApplication)
            .replace(with: ())
            .eraseToAnyPublisher()

        let clicked = EventMonitor.publish(events: .leftMouseDown, scope: .universal)
            .throttle(for: .seconds(0.15), scheduler: DispatchQueue.main, latest: true)
            .flatMap { _ in
                Just(()).append(Just(()).delay(for: 0.1, scheduler: DispatchQueue.main))
            }
            .eraseToAnyPublisher()

        Publishers.MergeMany(spaceSwitched, appSwitched, clicked)
            .map { _ in Bridging.getActiveSpaceID() }
            .removeDuplicates()
            .sink { [weak self] spaceID in
                self?.updateActiveSpace(spaceID)
            }
            .store(in: &cancellables)
    }

    /// Mirrors "is Thaw the frontmost app" into navigationState, which the
    /// settings window and the Thaw bar both key their behaviour off.
    private func observeAppFocus() {
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .map { $0 == .current }
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &cancellables)
    }

    /// Mirrors HIDEventManager drags for views, manually deduplicating Observation values.
    private func observeItemDrags() {
        let task = Task { @MainActor [weak self, hidEventManager] in
            let changes = Observations { hidEventManager.isDraggingMenuBarItem }
            var previous: Bool?
            for await isDragging in changes {
                guard let self else { return }
                guard isDragging != previous else { continue }
                let dragEnded = previous == true && !isDragging
                previous = isDragging
                updateIsDraggingMenuBarItem(isDragging)
                if isDragging {
                    itemManager.dragMembership.dragStarted(pressing: hidEventManager.pressedItemTag)
                } else if dragEnded {
                    itemManager.noteUserMenuBarDragEnded()
                }
            }
        }
        cancellables.insert(AnyCancellable { task.cancel() })
    }

    /// Refresh on frontmost Settings and once after bootstrap to populate the first draw.
    /// Observation flags change only on navigation, so no throttle is needed.
    private func observeImageCacheTriggers() {
        navigationStateObservationTask?.cancel()
        navigationStateObservationTask = Task { [weak self, navigationState] in
            let changes = Observations {
                (navigationState.isAppFrontmost, navigationState.isSettingsPresented)
            }
            for await (isAppFrontmost, isSettingsPresented) in changes {
                guard let self else { return }
                guard isAppFrontmost, isSettingsPresented else { continue }
                await self.refreshAllItemImages()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.refreshAllItemImages()
        }
    }

    /// Use the visible-consumer guard: SCK's first capture retains roughly 10-20 MB, so wait until a consumer opens.
    private func refreshAllItemImages() async {
        await imageCache.recaptureIfWarranted()
        if imageCache.cacheSize > 15 {
            imageCache.logCacheStatus("Periodic update")
        }
    }
}
