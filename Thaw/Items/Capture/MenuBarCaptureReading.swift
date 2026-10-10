//
//  MenuBarCaptureReading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawCapture

/// Window-server, screen-capture and AX reads used by one thumbnail pass.
nonisolated protocol MenuBarCaptureReading: Sendable {
    func captureBand(displayID: CGDirectDisplayID) async -> (frame: CGRect, menuMaxX: CGFloat?)
    func overflowBounds(displayID: CGDirectDisplayID) async -> [CGRect]
    func hostingCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture?
    func barWindowCapture(ownerPID: pid_t, displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture?
    func displayStripCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture?
    func menuBarItems(displayID: CGDirectDisplayID) async -> [MenuBarItem]
    func liveBounds(
        for candidates: [(item: MenuBarItem, bounds: CGRect)]
    ) async -> (bounds: [String: CGRect], ambiguous: Set<String>)
}

nonisolated struct LiveMenuBarCaptureReader: MenuBarCaptureReading {
    /// The item owners a geometry read refreshes. Empty reads every running app.
    var geometryOwners: Set<pid_t> = []

    func captureBand(displayID: CGDirectDisplayID) async -> (frame: CGRect, menuMaxX: CGFloat?) {
        await MainActor.run {
            guard let screen = NSScreen.screen(for: displayID) else {
                return (.zero, nil)
            }
            let menuMaxX = screen.getApplicationMenuFrame().flatMap { frame in
                frame.width > 0 ? frame.maxX : nil
            }
            return (screen.frame, menuMaxX)
        }
    }

    func overflowBounds(displayID: CGDirectDisplayID) async -> [CGRect] {
        await MenuBarItemAXProvider.nativeOverflowControlBoundsConcurrent(on: displayID)
    }

    func hostingCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID)
    }

    func barWindowCapture(ownerPID: pid_t, displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        await MenuBarItemImageCache.barWindowCapture(for: ownerPID, displayBounds: CGDisplayBounds(displayID))
    }

    func displayStripCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture? {
        await ScreenCapture.captureMenuBarDisplayStripAsync(displayID: displayID)
    }

    func menuBarItems(displayID: CGDirectDisplayID) async -> [MenuBarItem] {
        await MenuBarItemImageCache.freshCaptureGeometry(
            owners: geometryOwners,
            readOwners: { await MenuBarItemAXProvider.menuBarItemsForCaptureConcurrent(knownOwners: $0) },
            // Position-store recoveries and retained inventory carry old rectangles,
            // so neither can establish geometry for a new screenshot.
            discover: {
                await MenuBarItem.getMenuBarItems(on: displayID, option: [.onScreen, .activeSpace], freshOnly: true)
            }
        )
    }

    func liveBounds(
        for candidates: [(item: MenuBarItem, bounds: CGRect)]
    ) async -> (bounds: [String: CGRect], ambiguous: Set<String>) {
        guard !candidates.isEmpty else { return ([:], []) }
        let hostPIDs = candidates.compactMap { candidate -> pid_t? in
            guard let app = candidate.item.sourceApplication ?? candidate.item.owningApplication else {
                return nil
            }
            return app.processIdentifier
        }
        var seen = Set<pid_t>()
        let uniqueHostPIDs = hostPIDs.filter { seen.insert($0).inserted }
        guard !uniqueHostPIDs.isEmpty else { return ([:], []) }

        // The catalog's serial actor keeps bounded synchronous AX reads off
        // MainActor, including under Approachable Concurrency.
        let snapshot = await AXGeometryCatalog.snapshot(hostProcessIdentifiers: uniqueHostPIDs)
        guard !snapshot.isEmpty else { return ([:], []) }
        var bounds = [String: CGRect]()
        var ambiguous = Set<String>()
        for candidate in candidates {
            switch AXGeometryCatalog.match(
                ownerPID: candidate.item.sourcePID ?? candidate.item.ownerPID,
                identityTitle: candidate.item.tag.title,
                bounds: candidate.bounds,
                in: snapshot
            ) {
            case let .frame(liveFrame):
                bounds[candidate.item.uniqueIdentifier] = liveFrame
            case .ambiguous:
                ambiguous.insert(candidate.item.uniqueIdentifier)
                let details = AXGeometryCatalog.diagnosticSummary(
                    ownerPID: candidate.item.sourcePID ?? candidate.item.ownerPID,
                    identityTitle: candidate.item.tag.title,
                    bounds: candidate.bounds,
                    in: snapshot
                )
                MenuBarItemImageCache.diagLog.debug("CaptureOwnershipTrace: \(candidate.item.uniqueIdentifier) \(details)")
            case .unavailable:
                break
            }
        }
        return (bounds, ambiguous)
    }
}

extension MenuBarItemImageCache {
    /// The owners one capture's geometry read must refresh: the items being
    /// cropped, plus every other known item, since any of them can sit beside one.
    static nonisolated func captureGeometryOwners(
        for targets: [MenuBarItem],
        knownItems: [MenuBarItem],
        recentItems: [MenuBarItem]
    ) -> Set<pid_t> {
        guard !targets.isEmpty else { return [] }
        return Set((targets + knownItems + recentItems).map { $0.sourcePID ?? $0.ownerPID })
    }

    /// Fresh item geometry from the known owners alone, leaving new apps to the inventory scanner.
    /// The owners read answers nil unless every known item owner was re-read, and then every app is walked.
    static nonisolated func freshCaptureGeometry(
        owners: Set<pid_t>,
        readOwners: (Set<pid_t>) async -> [MenuBarItem]?,
        discover: () async -> [MenuBarItem]
    ) async -> [MenuBarItem] {
        guard !owners.isEmpty else { return await discover() }
        if let fresh = await readOwners(owners) {
            return fresh
        }
        diagLog.debug("freshCaptureGeometry: known-owner read was incomplete; reading every app")
        return await discover()
    }

    /// The widest owner window with nonzero alpha anchored to this display's menu-bar band.
    static nonisolated func barWindow(
        for ownerPID: pid_t,
        displayBounds: CGRect
    ) -> (windowID: CGWindowID, frame: CGRect)? {
        guard
            displayBounds.width > 0,
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        var best: (windowID: CGWindowID, frame: CGRect, info: [String: Any])?
        for info in list {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPID,
                let number = info[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            guard ScreenCapture.isMenuBarStripFrame(frame, in: displayBounds),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            if let current = best, frame.width <= current.frame.width {
                continue
            }
            best = (windowID: number, frame: frame, info: info)
        }
        guard let best else { return nil }
        let layer = best.info[kCGWindowLayer as String] as? Int ?? -1
        let onScreen = best.info[kCGWindowIsOnscreen as String] as? Bool ?? false
        let owner = best.info[kCGWindowOwnerName as String] as? String ?? "?"
        MenuBarItemImageCache.diagLog.debug(
            "barWindow: pid \(ownerPID) (\(owner)) → wid=\(best.windowID) frame=\(best.frame) " +
                "layer=\(layer) onScreen=\(onScreen)"
        )
        return (windowID: best.windowID, frame: best.frame)
    }

    static nonisolated func barWindowCapture(
        for ownerPID: pid_t,
        displayBounds: CGRect
    ) async -> ScreenCapture.MenuBarHostingCapture? {
        guard
            let barWindow = barWindow(for: ownerPID, displayBounds: displayBounds),
            barWindow.frame.width > 0,
            let capture = await ScreenCapture.captureOwnerBarWindow(
                windowID: barWindow.windowID,
                frame: barWindow.frame
            )
        else { return nil }
        let image = capture.image
        // SkyLight offers no pixel-format control; retain this evidence when
        // distinguishing an opaque slab from a usable capture in field logs.
        MenuBarItemImageCache.diagLog.debug(
            "barWindowCapture: wid=\(barWindow.windowID) \(image.width)×\(image.height)px " +
                "alphaInfo=\(image.alphaInfo.rawValue) bpp=\(image.bitsPerPixel) " +
                "colorSpace=\((image.colorSpace?.name as String?) ?? "nil")"
        )
        let scale = CGFloat(image.width) / barWindow.frame.width
        guard isPlausibleCaptureScale(scale) else {
            MenuBarItemImageCache.diagLog.warning(
                "barWindowCapture: scale \(scale) implausible for a \(barWindow.frame.width)pt bar window"
            )
            return nil
        }
        return ScreenCapture.MenuBarHostingCapture(
            image: image,
            windowFrame: barWindow.frame,
            scale: scale
        )
    }
}
