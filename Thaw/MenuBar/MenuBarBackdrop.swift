//
//  MenuBarBackdrop.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import ThawCapture

/// What the transparent macOS 27 menu bar is drawn over, per display, for
/// anything that paints over the bar and must match it.
///
/// Composited via SLWindowListCreateImageFromArray, which needs no
/// ScreenCaptureKit stream and never lights the recording indicator. The bar's
/// blur and tint belong to no window (including them renders flat grey), so
/// only windows below kCGMainMenuWindowLevel are requested.
@MainActor
final class MenuBarBackdrop {
    /// One display's strip under the menu bar.
    struct Strip {
        /// The strip in CG-global coordinates.
        let rect: CGRect
        let image: CGImage
        /// The windows it was composited from, with the rect. A refresh that
        /// finds the same key has nothing new to capture.
        fileprivate let key: String

        /// The part of the strip under cgRect, as a unit rect for a layer's
        /// contentsRect.
        func contentsRect(for cgRect: CGRect) -> CGRect {
            CGRect(
                x: (cgRect.minX - rect.minX) / rect.width,
                y: (cgRect.minY - rect.minY) / rect.height,
                width: cgRect.width / rect.width,
                height: cgRect.height / rect.height
            )
        }

        /// The part of the strip under cgRect, cropped out as an image.
        func image(of cgRect: CGRect) -> CGImage? {
            let scaleX = CGFloat(image.width) / rect.width
            let scaleY = CGFloat(image.height) / rect.height
            let crop = CGRect(
                x: (cgRect.minX - rect.minX) * scaleX,
                y: (cgRect.minY - rect.minY) * scaleY,
                width: cgRect.width * scaleX,
                height: cgRect.height * scaleY
            ).integral
            return image.cropping(to: crop)
        }
    }

    private(set) var strips: [CGDirectDisplayID: Strip] = [:]
    private var refreshTask: Task<Void, Never>?
    private var observation: Task<Void, Never>?

    func performSetup(with appState: AppState) {
        observation = Task { @MainActor [weak self] in
            let menuBarManager = appState.menuBarManager
            // A new wallpaper or appearance keeps the same windows, so the key
            // alone would not notice it; the sampler's colour does.
            for await _ in Observations({ menuBarManager.averageColors }) {
                self?.refresh(force: true)
            }
        }
        refresh(force: true)
    }

    func strip(for displayID: CGDirectDisplayID) -> Strip? {
        strips[displayID]
    }

    /// Re-composites each display's strip when what is behind it changed.
    /// Cheap when nothing did: one window-list read per display. force
    /// re-composites regardless, for changes the key cannot see.
    func refresh(force: Bool = false) {
        refreshTask?.cancel()
        let requests = NSScreen.screens.map { screen in
            (screen.displayID, CGRect(
                x: screen.cgFrame.minX,
                y: screen.cgFrame.minY,
                width: screen.cgFrame.width,
                height: screen.getMenuBarHeight() ?? screen.getMenuBarHeightEstimate()
            ))
        }
        let known = force ? [:] : strips.mapValues(\.key)
        refreshTask = Task { [weak self] in
            for (displayID, rect) in requests {
                let windowIDs = await Self.windowsBelowMenuBar(intersecting: rect)
                let key = "\(rect)|\(windowIDs.sorted())"
                guard key != known[displayID],
                      let image = await Self.composite(windowIDs, in: rect, resolution: .bestResolution)
                else {
                    continue
                }
                guard !Task.isCancelled else { return }
                self?.strips[displayID] = Strip(rect: rect, image: image, key: key)
            }
        }
    }

    /// Composites whatever lies below the menu bar inside cgRect, which may
    /// reach below the bar (the wallpaper palette reads the whole wallpaper).
    /// For one-off reads; bar-height reads should use strip(for:).
    func capture(
        _ cgRect: CGRect,
        resolution: CGWindowImageOption = .bestResolution,
        belowLayer ceiling: Int = Int(kCGMainMenuWindowLevel)
    ) async -> CGImage? {
        let windowIDs = await Self.windowsBelowMenuBar(intersecting: cgRect, belowLayer: ceiling)
        return await Self.composite(windowIDs, in: cgRect, resolution: resolution)
    }

    /// Composites the given windows. For callers that pick their own windows,
    /// which must all sit below the menu bar.
    @concurrent
    static nonisolated func composite(
        _ windowIDs: [CGWindowID],
        in cgRect: CGRect,
        resolution: CGWindowImageOption
    ) async -> CGImage? {
        await ScreenCapture.compositeWindows(windowIDs, in: cgRect, options: resolution)
    }

    @concurrent
    static nonisolated func windowsBelowMenuBar(
        intersecting cgRect: CGRect,
        belowLayer ceiling: Int = Int(kCGMainMenuWindowLevel)
    ) async -> [CGWindowID] {
        WindowInfo.createWindows(option: .onScreen)
            .filter { $0.isOnScreen && $0.layer < ceiling && $0.bounds.intersects(cgRect) }
            .map(\.windowID)
    }
}
