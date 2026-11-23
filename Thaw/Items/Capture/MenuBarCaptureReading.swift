//
//  MenuBarCaptureReading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Cocoa
import MenuBarModel
import ThawAXCore
import ThawCapture

/// Window-server, screen-capture and AX reads used by one thumbnail pass.
nonisolated protocol MenuBarCaptureReading: Sendable {
    func captureBand(displayID: CGDirectDisplayID) async -> (frame: CGRect, menuMaxX: CGFloat?)
    /// The CG frames of the displays an item may be seated on, for the parked-frame checks.
    func displayBounds() -> [CGRect]
    func overflowBounds(displayID: CGDirectDisplayID) async -> [CGRect]
    func hostingCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture?
    func barWindowCapture(ownerPID: pid_t, displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture?
    func displayStripCapture(displayID: CGDirectDisplayID) async -> ScreenCapture.MenuBarHostingCapture?
    func menuBarItems(displayID: CGDirectDisplayID) async -> [MenuBarItem]
    func liveBounds(
        for candidates: [(item: MenuBarItem, bounds: CGRect)]
    ) async -> (bounds: [String: CGRect], ambiguous: Set<String>)
    /// Where MenuBarAgent's drawn bar disagrees with the candidates' reported frames. A candidate drawn
    /// where it reports is in neither part, and none is in either when the drawn bar can't be read.
    func drawnSeats(
        for candidates: [(item: MenuBarItem, bounds: CGRect)],
        displayID: CGDirectDisplayID
    ) async -> DrawnSeats
}

nonisolated extension MenuBarCaptureReading {
    func drawnSeats(for _: [(item: MenuBarItem, bounds: CGRect)], displayID _: CGDirectDisplayID) async -> DrawnSeats {
        DrawnSeats()
    }
}

/// The candidates of one crop whose reported frame is not where MenuBarAgent draws them, by identifier.
nonisolated struct DrawnSeats: Equatable, Sendable {
    /// Where each candidate drawn away from its reported frame is drawn.
    var moved: [String: CGRect] = [:]
    /// The candidates no crop is safe for: they report a seat another app's item is drawn in with nothing
    /// to say where they are, or a crop at their drawn seat would take in a neighbour.
    var occupied: Set<String> = []
}

nonisolated struct LiveMenuBarCaptureReader: MenuBarCaptureReading {
    /// The item owners a geometry read refreshes. Empty reads every running app.
    var geometryOwners: Set<pid_t> = []

    /// MenuBarAgent's drawn bar, which places items whose app answers no AX. Tests pass their own.
    var drawnBar: @Sendable () async -> [MenuBarAgentWindow.Entry]? = { await MenuBarItemAXProvider.drawnBarConcurrent() }

    /// The bar MenuBarAgent draws on the display with these bounds, which is the one a crop there is cut from.
    var drawnBarOnDisplay: @Sendable (CGRect) async -> [MenuBarAgentWindow.Entry]? = { await readDrawnBar(onDisplay: $0) }

    /// What these apps list in their own extras bars, which says how many items each has, drawn or not.
    var itemCatalog: @Sendable ([pid_t]) async -> [AXGeometryCatalog.Entry] = { await AXGeometryCatalog.snapshot(hostProcessIdentifiers: $0) }

    /// Reads one display's bar off the main actor. Nil when unreadable or mid-change. The inventory's read
    /// is of the agent's first window, which can be another display's bar.
    @concurrent
    private static func readDrawnBar(onDisplay display: CGRect) async -> [MenuBarAgentWindow.Entry]? {
        AXPrimitives.menuBarAgentSettledEntries(onDisplay: display)
    }

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

    func displayBounds() -> [CGRect] {
        BarAxis.liveDisplayBounds()
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
        let uniqueHostPIDs = Array(hostPIDs.uniqued())
        guard !uniqueHostPIDs.isEmpty else { return ([:], []) }

        // The catalog's serial actor keeps bounded synchronous AX reads off
        // MainActor, including under Approachable Concurrency.
        let snapshot = await AXGeometryCatalog.snapshot(hostProcessIdentifiers: uniqueHostPIDs)
        if snapshot.isEmpty {
            MenuBarItemImageCache.diagLog.debug("CaptureOwnershipTrace: no owner geometry read for \(candidates.count) item(s)")
        }
        var bounds = [String: CGRect]()
        var ambiguous = Set<String>()
        var drawn: [MenuBarAgentWindow.Entry]??
        for candidate in candidates {
            let owner = candidate.item.sourcePID ?? candidate.item.ownerPID
            let match = AXGeometryCatalog.match(
                ownerPID: owner,
                identityTitle: candidate.item.tag.title,
                bounds: candidate.bounds,
                in: snapshot
            )
            switch match {
            case let .frame(liveFrame):
                bounds[candidate.item.uniqueIdentifier] = liveFrame
            case .ambiguous:
                ambiguous.insert(candidate.item.uniqueIdentifier)
                MenuBarItemImageCache.diagLog.debug(Self.ownershipTrace(of: candidate, match: match, in: snapshot))
            case .unavailable:
                let siblings = candidates
                    .filter { ($0.item.sourcePID ?? $0.item.ownerPID) == owner && $0.item.uniqueIdentifier != candidate.item.uniqueIdentifier }
                    .map(\.bounds)
                if Self.drawnBarDistinguishes(candidate.bounds, from: siblings),
                   let frame = await drawnFrame(for: candidate, owner: owner, snapshot: snapshot, drawn: &drawn)
                {
                    bounds[candidate.item.uniqueIdentifier] = frame
                    continue
                }
                MenuBarItemImageCache.diagLog.debug(Self.ownershipTrace(of: candidate, match: match, in: snapshot))
            }
        }
        return (bounds, ambiguous)
    }

    func drawnSeats(
        for candidates: [(item: MenuBarItem, bounds: CGRect)],
        displayID: CGDirectDisplayID
    ) async -> DrawnSeats {
        // Apple's items are the agent's own entries, which can't be told apart by owner, and an item
        // whose app is unknown would take its own entry for another app's.
        let placed = candidates.compactMap { candidate -> DrawnSeatCandidate? in
            guard let app = candidate.item.sourceApplication ?? candidate.item.owningApplication,
                  app.bundleIdentifier != SharedConstants.menuBarHostingBundleID
            else { return nil }
            return (candidate.item.uniqueIdentifier, candidate.bounds, candidate.item.ownerPID, candidate.item.sourcePID)
        }
        guard !placed.isEmpty, let entries = await drawnBarOnDisplay(CGDisplayBounds(displayID)) else { return DrawnSeats() }
        // Only an app with a displaced item is asked what it lists.
        let displaced = Self.displacedApps(among: placed, in: entries)
        let itemCounts = displaced.isEmpty ? [:] : Self.itemCounts(in: await itemCatalog(displaced.sorted()))
        return Self.drawnSeats(for: placed, in: entries, itemCounts: itemCounts)
    }

    /// One candidate of drawnSeats(for:in:itemCounts:). Its frame is the one its app reports.
    typealias DrawnSeatCandidate = (identifier: String, frame: CGRect, ownerPID: pid_t, sourcePID: pid_t?)

    /// The apps whose one drawn entry is away from the frame a candidate of theirs reports.
    static func displacedApps(among candidates: [DrawnSeatCandidate], in entries: [MenuBarAgentWindow.Entry]) -> Set<pid_t> {
        Set(candidates.compactMap { candidate in
            let (frame, owner, source) = (candidate.frame, candidate.ownerPID, candidate.sourcePID)
            guard DrawnItemFrame.cropFrame(for: frame, ownerPID: owner, sourcePID: source, in: entries) != frame else { return nil }
            return DrawnItemFrame.appPID(ownerPID: owner, sourcePID: source)
        })
    }

    /// How many items each app in a catalog read lists in its extras bar. An app that didn't answer has no count.
    static func itemCounts(in catalog: [AXGeometryCatalog.Entry]) -> [pid_t: Int] {
        Dictionary(grouping: catalog, by: \.ownerPID).mapValues { Set($0.map(\.itemIndex)).count }
    }

    /// The candidates MenuBarAgent draws away from their reported frame, given the bar of the display they
    /// are on. An app's one drawn entry is a candidate's own only when itemCounts says the app lists a single
    /// item: a sibling that isn't drawn would otherwise be moved onto it. Any other candidate is only checked
    /// for reporting another app's seat.
    static func drawnSeats(
        for candidates: [DrawnSeatCandidate],
        in entries: [MenuBarAgentWindow.Entry],
        itemCounts: [pid_t: Int]
    ) -> DrawnSeats {
        var seats = DrawnSeats()
        for candidate in candidates {
            let (frame, owner, source) = (candidate.frame, candidate.ownerPID, candidate.sourcePID)
            let isOnlyItem = DrawnItemFrame.appPID(ownerPID: owner, sourcePID: source).map { itemCounts[$0] == 1 } ?? false
            let seat = isOnlyItem ? DrawnItemFrame.cropFrame(for: frame, ownerPID: owner, sourcePID: source, in: entries) : frame
            if seat != frame {
                // The crop keeps the reported width, so it is checked against the items drawn beside the seat.
                if DrawnItemFrame.takesInNeighbour(seat, ownerPID: owner, sourcePID: source, in: entries) {
                    seats.occupied.insert(candidate.identifier)
                } else {
                    seats.moved[candidate.identifier] = seat
                }
            } else if DrawnItemFrame.drawnFrame(for: frame, ownerPID: owner, sourcePID: source, in: entries) == nil || !isOnlyItem,
                      DrawnItemFrame.isPhantom(frame, ownerPID: owner, sourcePID: source, in: entries)
            {
                seats.occupied.insert(candidate.identifier)
            }
        }
        return seats
    }

    /// The frame MenuBarAgent draws for a candidate whose app gave the catalog no entries at all, as
    /// f.lux does. The drawn bar is read once per call, on first need.
    private func drawnFrame(
        for candidate: (item: MenuBarItem, bounds: CGRect),
        owner: pid_t,
        snapshot: [AXGeometryCatalog.Entry],
        drawn: inout [MenuBarAgentWindow.Entry]??
    ) async -> CGRect? {
        guard !snapshot.contains(where: { $0.ownerPID == owner }) else { return nil }
        if drawn == nil { drawn = .some(await drawnBar()) }
        guard let entries = drawn ?? nil,
              let frame = AXGeometryCatalog.drawnFrame(ownerPID: owner, bounds: candidate.bounds, in: entries)
        else { return nil }
        MenuBarItemImageCache.diagLog.debug(
            "CaptureOwnershipTrace: \(candidate.item.uniqueIdentifier) placed at \(frame) from MenuBarAgent's drawn bar"
        )
        return frame
    }

    /// Whether the drawn bar can tell an item at bounds from the same app's other items. It matches on
    /// horizontal place alone, so same-width items could stand in for each other; no picture beats a wrong one.
    static func drawnBarDistinguishes(_ bounds: CGRect, from siblings: [CGRect]) -> Bool {
        !siblings.contains { abs($0.width - bounds.width) <= 1 }
    }

    /// Says why the catalog could not vouch for a candidate's frame.
    static func ownershipTrace(
        of candidate: (item: MenuBarItem, bounds: CGRect),
        match: AXGeometryCatalog.Match,
        in snapshot: [AXGeometryCatalog.Entry]
    ) -> String {
        let details = AXGeometryCatalog.diagnosticSummary(
            ownerPID: candidate.item.sourcePID ?? candidate.item.ownerPID,
            identityTitle: candidate.item.tag.title,
            bounds: candidate.bounds,
            in: snapshot
        )
        return "CaptureOwnershipTrace: \(match == .ambiguous ? "ambiguous" : "unavailable") " +
            "\(candidate.item.uniqueIdentifier) at \(candidate.bounds) \(details)"
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
        autoreleasepool {
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
        guard AXCropRules.isPlausibleCaptureScale(scale) else {
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
