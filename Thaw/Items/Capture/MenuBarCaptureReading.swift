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
        // Position-store recoveries and retained inventory carry old rectangles,
        // so neither can establish geometry for a new screenshot.
        await MenuBarItem.getMenuBarItems(on: displayID, option: [.onScreen, .activeSpace], freshOnly: true)
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
