//
//  HIDEventManager+Tooltip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Foundation
import ThawCapture

extension HIDEventManager {
    // MARK: Menu Bar Tooltips

    func handleMenuBarTooltip(appState: AppState, screen: NSScreen) {
        guard ScreenCapture.hasCachedScreenRecordingPermission, configuration.showMenuBarTooltips else {
            return
        }

        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let mouseLocation = MouseHelpers.locationCoreGraphics,
            let hoveredEntry = drawnSeat(at: mouseLocation)
        else {
            dismissMenuBarTooltip()
            return
        }

        let hoveredID = hoveredEntry.windowID

        if hoveredID == tooltipHoveredWindowID {
            return
        }

        dismissMenuBarTooltip()
        tooltipHoveredWindowID = hoveredID

        let delay = configuration.tooltipDelay
        tooltipTask = Task {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            try Task.checkCancellation()

            // Re-read the cached bounds to pick up any cache rebuilds during the delay.
            guard let target = drawnSeat(at: mouseLocation), target.windowID == hoveredID else { return }

            let allItems = appState.itemManager.managedItems
            let displayName: String
            if let item = allItems.first(where: { $0.windowID == hoveredID }) {
                displayName = item.displayName
            } else if appState.menuBarManager.sections.contains(where: {
                $0.controlItem.window?.windowNumber == Int(hoveredID)
            }) {
                displayName = Constants.displayName
            } else {
                return
            }

            // Convert top-left Core Graphics bounds to bottom-left AppKit coordinates for the panel.
            guard let appKitBounds = NSScreen.cocoaRect(fromCG: target.bounds) else { return }
            let appKitOrigin = CGPoint(x: appKitBounds.midX, y: appKitBounds.minY)

            CustomTooltipPanel.shared.show(
                text: displayName,
                near: appKitOrigin,
                in: screen,
                owner: "menuBar"
            )
        }
    }

    /// Only dismisses panels owned by the menu bar tooltip handler.
    func dismissMenuBarTooltip() {
        tooltipTask?.cancel()
        tooltipTask = nil
        tooltipHoveredWindowID = nil
        CustomTooltipPanel.shared.dismiss(owner: "menuBar")
    }
}
