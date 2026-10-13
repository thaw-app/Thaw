//
//  ScreenCapture+BackdropService.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

public extension ScreenCapture {
    /// Helper-only SkyLight entry point. Re-reads window levels and geometry;
    /// a caller cannot use a backdrop request to capture arbitrary app content.
    static func captureBackdropForService(
        windowIDs: [CGWindowID],
        screenBounds: CGRect,
        options: CGWindowImageOption
    ) -> CGImage? {
        guard !screenBounds.isNull,
              Bridging.isValidCaptureBounds(screenBounds, scale: Bridging.maximumActiveDisplayScale()),
              !windowIDs.isEmpty, windowIDs.count <= 64
        else { return nil }

        let displayIDs = Bridging.activeDisplayIDs()
        guard !displayIDs.isEmpty else { return nil }
        let displayGeometry = displayIDs.map { displayID in
            (bounds: CGDisplayBounds(displayID), menuBarHeight: liveMenuBarHeight(for: displayID))
        }
        let onScreen = Set(Bridging.getWindowList(option: .onScreen))
        var seen = Set<CGWindowID>()
        let accepted = windowIDs.filter { windowID in
            guard windowID != 0, onScreen.contains(windowID), seen.insert(windowID).inserted,
                  let level = Bridging.getWindowLevel(for: windowID),
                  let bounds = Bridging.getWindowBounds(for: windowID)
            else { return false }
            return displayGeometry.contains { display in
                isAllowedBackdropWindow(
                    captureBounds: screenBounds,
                    windowBounds: bounds,
                    windowLevel: level,
                    displayBounds: display.bounds,
                    menuBarHeight: display.menuBarHeight
                )
            }
        }
        guard !accepted.isEmpty else { return nil }
        return Bridging.captureWindowsImage(windowIDs: accepted, screenBounds: screenBounds, options: options)
    }
}

extension ScreenCapture {
    static func isAllowedBackdropWindow(
        captureBounds: CGRect,
        windowBounds: CGRect,
        windowLevel: CGWindowLevel,
        displayBounds: CGRect,
        menuBarHeight: CGFloat?
    ) -> Bool {
        guard !captureBounds.isNull,
              Bridging.isValidCaptureBounds(captureBounds, scale: 1),
              displayBounds.contains(captureBounds),
              windowBounds.intersects(captureBounds),
              windowLevel < kCGMainMenuWindowLevel
        else { return false }
        if windowLevel <= CGWindowLevelForKey(.desktopWindow) {
            return true
        }
        let strip = menuBarDisplayStripFrame(
            displayFrame: displayBounds,
            height: menuBarDisplayStripHeight(menuBarHeight: menuBarHeight)
        )
        return strip.contains(captureBounds)
    }
}
