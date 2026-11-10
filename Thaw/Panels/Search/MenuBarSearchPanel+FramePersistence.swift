//
//  MenuBarSearchPanel+FramePersistence.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

extension MenuBarSearchPanel {
    // MARK: Per-display frame persistence

    /// Nil when the display has no resolvable UUID.
    private func frameDefaultsKey(for screen: NSScreen) -> String? {
        guard let uuidString = Bridging.getDisplayUUIDString(for: screen.displayID) else {
            return nil
        }
        return "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"
    }

    func saveFrameForDisplay(_ screen: NSScreen) {
        guard isVisible, contentView != nil else {
            return
        }

        let currentFrame = frame
        let actualScreen = NSScreen.screens.first { $0.visibleFrame.intersects(currentFrame) } ?? screen

        guard let keyString = frameDefaultsKey(for: actualScreen) else {
            return
        }

        // Relative to the display's visible frame.
        let visibleFrame = actualScreen.visibleFrame
        let relativeFrame = CGRect(
            x: currentFrame.minX - visibleFrame.minX,
            y: currentFrame.minY - visibleFrame.minY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        UserDefaults.standard.set(relativeFrame.dictionaryRepresentation as NSDictionary, forKey: keyString)
    }

    private func loadFrameForDisplay(_ screen: NSScreen) -> CGRect? {
        guard
            let keyString = frameDefaultsKey(for: screen), let frameDict = UserDefaults.standard.dictionary(forKey: keyString)
        else {
            return nil
        }
        return CGRect(dictionaryRepresentation: frameDict as CFDictionary)
    }

    func placementFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        switch presentation.placement {
        case .remembered: rememberedFrame(on: screen, size: size)
        case .centered: launcherFrame(on: screen, size: size)
        case .nearPointer: assistedFrame(on: screen, size: size)
        }
    }

    /// Anchored to the pointer; see AssistedPanelPlacement.
    private func assistedFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        AssistedPanelPlacement.frame(
            near: NSEvent.mouseLocation,
            in: screen.visibleFrame,
            size: size
        )
    }

    /// The saved spot clamped to the visible area, or dead center.
    private func rememberedFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        let visibleFrame = screen.visibleFrame

        guard let savedFrame = loadFrameForDisplay(screen) else {
            let centered = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
            return CGRect(origin: centered, size: size)
        }

        // Saved origins are relative to the display's visible frame.
        let origin = CGPoint(
            x: min(max(savedFrame.minX + visibleFrame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(savedFrame.minY + visibleFrame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    /// Slightly above center, like Spotlight.
    private func launcherFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        let visible = screen.visibleFrame
        let originX = visible.midX - size.width / 2
        let originY = visible.midY - size.height / 2 + visible.height * 0.12
        return CGRect(
            x: originX.rounded(),
            y: min(originY, visible.maxY - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }
}
