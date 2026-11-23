//
//  MenuBarItemImageCache+OpenedItemCapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawAXCore
import ThawCapture

extension MenuBarItemImageCache {
    /// Retakes the picture of a hidden item opened from the Thaw Bar once its menu closes. See
    /// OpenedItemRecapture. With "Use app icons instead of live previews" on, an item drawn as its
    /// app's icon is left alone, as every other pass leaves it (itemsNeedingCapture(_:demand:)).
    func retakePictureAfterOpening(_ item: MenuBarItem) {
        // Without Screen Recording no picture can be taken, so the menu isn't watched for a minute first.
        guard let appState, ScreenCapture.hasCachedScreenRecordingPermission else { return }
        // Its menu is watched by process, so an item listed without one would never count as open.
        let item = ItemOwnerLookup.resolving(item)
        let demand = CaptureDemand(
            usesAppIcons: configuration.alwaysUseAppIconForMenuBarItems,
            hasUnfilteredConsumer: false,
            alertRevealIdentifiers: []
        )
        guard !Self.itemsNeedingCapture([item], demand: demand).isEmpty else { return }
        let monitor = appState.itemManager.menuOpenMonitor
        let owners = item.reactionPIDs
        let isMenuOpen: @MainActor () async -> Bool = { await monitor.isMenuOpen(ownedBy: owners) }
        // The picture's checks read the windows anew: one before the screenshot and one after, under
        // the cache's 250 ms, would otherwise share an answer and keep a picture taken with a menu open.
        let isMenuOpenNow: @MainActor () async -> Bool = { await monitor.isMenuOpen(ownedBy: owners, fresh: true) }
        let photograph = openedItemPhotograph(appState: appState)
        OpenedItemRecapture.shared.start(item.tag.tagIdentifier, steps: OpenedItemRecapture.Steps(
            isMenuOpen: isMenuOpen,
            attempt: { await photograph.take(item, isMenuOpen: isMenuOpenNow) }
        ))
    }

    /// The opened-item picture over this cache and the live bar. Thaw's windows are usually
    /// closed by then, so captures are held open just for it, and the cache is reloaded first:
    /// the idle trim may have dropped pictures a save would otherwise write out.
    func openedItemPhotograph(appState: AppState) -> OpenedItemPhotograph {
        OpenedItemPhotograph(
            slot: prewarmSlot,
            mayCapture: { [weak self] in
                ScreenCapture.hasCachedScreenRecordingPermission && self?.skipCaptureWhileScreenLocked("opened item picture") == false
            },
            holdCaptures: { [weak self] in
                self?.idleTrimTask?.cancel()
                self?.idleTrimTask = nil
                self?.loadFromDiskIfNeeded()
                await self?.diskLoadTask?.value
                appState.navigationState.beginBackgroundCapture()
            },
            releaseCaptures: { [weak self] in
                appState.navigationState.endBackgroundCapture()
                if self?.hasVisibleCaptureConsumer() == false {
                    self?.scheduleIdleTrim()
                }
            },
            displays: {
                let admitted = appState.itemManager.itemDisplayID
                return (admitted ?? Bridging.activeMenuBarDisplayID, admitted)
            },
            shownItem: { item, displayID in
                // Live geometry only, the owner first: recovering saved positions is synchronous
                // LaunchServices work on the main thread, and the wait reads the bar up to 20 times.
                let owner: Set<pid_t> = [item.sourcePID ?? item.ownerPID]
                return await RevealCaptureSession.waitForRevealedItems(matching: [item]) {
                    await MenuBarItem.getMenuBarItems(on: displayID, option: [.onScreen, .activeSpace], freshOnly: true, priorityPIDs: owner)
                }.first
            },
            settlePixels: { await RevealCaptureSession.settleRevealedPixels([$0], displayID: $1, reader: LiveMenuBarCaptureReader()) },
            admit: { CapturePublicationPolicy.admit(layout: appState.itemManager.layoutPublication, displayID: $0) },
            crop: { [weak self] shown, frame, displayID in
                guard let self else { return CapturePass() }
                return await boundsCropper.crop(
                    // Cut where MenuBarAgent draws it, as a revealed batch is: its reported frame can be a neighbour's seat.
                    AXBoundsCropper.Request(items: [(shown, frame)], displayID: displayID, validateFreshBounds: true, seatsOnDrawnBar: true),
                    using: LiveMenuBarCaptureReader(),
                    skipping: { [weak self] in self?.shouldSkipCapture(for: $0) ?? true }
                )
            },
            commit: { [weak self] in self?.commitOpenedItemPicture($0, shown: $1, admission: $2, appState: appState) ?? false },
            save: { [weak self] in self?.saveToDisk() }
        )
    }

    /// Publishes an opened item's picture as a revealed batch of one. False when the bar changed meanwhile.
    private func commitOpenedItemPicture(
        _ pass: CapturePass,
        shown: OpenedItemPhotograph.Shown,
        admission: CapturePublicationAdmission,
        appState: AppState
    ) -> Bool {
        guard commitRevealedBatch(pass, revealed: [shown], admission: admission, appState: appState) else { return false }
        // Compare pixels: an unchanged icon gives an equal picture in a new image, which the cache doesn't republish.
        if let picture = pass.captured[shown.live.tag],
           let kept = Self.cachedCapture(for: shown.requested.tag, in: capturesByTag)?.capture,
           !MenuBarItemGlyphCapture.isVisuallyEqual(kept, picture)
        {
            Self.diagLog.debug("opened item picture: kept the old picture of \(shown.requested.logString) over the new \(picture.pointSize.width) pt one")
        }
        return true
    }
}
