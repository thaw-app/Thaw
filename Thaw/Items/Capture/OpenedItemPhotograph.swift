//
//  OpenedItemPhotograph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import ThawAXCore

/// One try at the picture of a hidden item opened from the Thaw Bar, while the item is still in
/// the menu bar. OpenedItemRecapture decides when to try.
///
/// The try finds the item where the menu bar shows it, waits for its pixels to settle, crops it
/// where MenuBarAgent draws it (see AXBoundsCropper.Request.seatsOnDrawnBar) and keeps the picture unless a menu of
/// its app opened meanwhile, since an open menu draws the item highlighted. It holds the reveal
/// capture slot, so no prewarm reveals or conceals another item into the screenshot.
@MainActor
struct OpenedItemPhotograph {
    typealias Shown = (requested: MenuBarItem, live: MenuBarItem)
    typealias CapturePass = MenuBarItemImageCache.CapturePass
    /// The display a try takes its picture on, and the item cache's display it is admitted against.
    typealias Displays = (capture: CGDirectDisplayID, admitted: CGDirectDisplayID?)

    let slot: RevealCaptureSlot
    /// Whether a picture can be taken: Screen Recording is granted and the screen isn't locked.
    let mayCapture: @MainActor () -> Bool
    /// Gets the cache ready to save and lets captures run while no Thaw window is open.
    let holdCaptures: @MainActor () async -> Void
    /// Ends holdCaptures.
    let releaseCaptures: @MainActor () -> Void
    /// Read once per try, so a display switch meanwhile rejects the picture rather than becoming its baseline.
    let displays: @MainActor () -> Displays
    /// The item where the menu bar shows it on the display once its frame is stable, or nil when it isn't shown.
    let shownItem: @MainActor (MenuBarItem, CGDirectDisplayID) async -> Shown?
    /// Waits for the shown item's pixels on the display to stop changing, and says whether they did.
    let settlePixels: @MainActor (MenuBarItem, CGDirectDisplayID) async -> RevealCaptureSession.PixelSettle
    /// Admits the picture for publishing against the item cache's display. Asked with nothing awaited before the screenshot.
    let admit: @MainActor (CGDirectDisplayID?) -> CapturePublicationAdmission
    /// Crops the shown item at the frame on the display, moved to where MenuBarAgent draws it.
    let crop: @MainActor (MenuBarItem, CGRect, CGDirectDisplayID) async -> CapturePass
    /// Publishes the picture through a revealed batch's checks. False when the bar changed meanwhile.
    let commit: @MainActor (CapturePass, Shown, CapturePublicationAdmission) -> Bool
    let save: @MainActor () -> Void

    /// Takes and keeps the item's picture, or says why not.
    func take(_ item: MenuBarItem, isMenuOpen: @MainActor () async -> Bool) async -> OpenedItemRecapture.Attempt {
        guard mayCapture() else {
            Self.log("no Screen Recording permission, or the screen is locked")
            return .missed
        }
        // One capture at a time: another pass's reveal or conceal would land in this screenshot.
        await slot.begin()
        defer { slot.end() }
        await holdCaptures()
        defer { releaseCaptures() }
        let outcome = await photograph(item, isMenuOpen: isMenuOpen)
        Self.log("\(item.logString): \(outcome)")
        return outcome
    }

    private func photograph(_ item: MenuBarItem, isMenuOpen: @MainActor () async -> Bool) async -> OpenedItemRecapture.Attempt {
        let displays = displays()
        guard let shown = await shownItem(item, displays.capture) else {
            Self.log("\(item.logString) isn't shown in the menu bar")
            return .missed
        }
        let pixelSettle = await settlePixels(shown.live, displays.capture)
        guard !Task.isCancelled else { return .missed }
        guard await !isMenuOpen() else { return .menuOpened }
        let cropFrame = shown.live.bounds

        // Admitted with nothing else awaited before the screenshot, as a revealed batch is.
        let admission = admit(displays.admitted)
        var pass = await crop(shown.live, cropFrame, displays.capture)
        // As for a revealed batch: a picture cut off at an edge while the pixels still changed is the icon mid-slide.
        RevealCaptureSession.dropCutOffPictures(from: &pass, amongChanging: pixelSettle.mayBeChanging(at: 0) ? [shown.live.tag] : [])
        // Before the picture check: a menu that opened mid-slide may be why the picture was dropped.
        guard await !isMenuOpen() else { return .menuOpened }
        guard pass.captured[shown.live.tag] != nil else {
            Self.log("no crop of \(item.logString) at \(cropFrame)")
            return .missed
        }
        guard commit(pass, shown, admission) else {
            Self.log("the menu bar changed during the picture of \(item.logString)")
            return .missed
        }
        save()
        return .stored
    }

    private static func log(_ message: String) {
        MenuBarItemImageCache.diagLog.debug("opened item picture: \(message)")
    }
}
