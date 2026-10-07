//
//  SettingsWindowDiagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Writes the Settings window's geometry to the diagnostic log when it opens.
///
/// For reports of clicks landing below the control that was drawn (#1265), where the window's own
/// numbers are the first thing to compare with a Mac that does not show it.
@MainActor
enum SettingsWindowDiagnostics {
    private static let diagLog = DiagLog(category: "SettingsWindow")

    /// What is read from the window. Kept apart from NSWindow so the line can be tested.
    nonisolated struct Reading: Equatable {
        var frame: CGRect
        /// The part of the window the title bar and toolbar leave uncovered.
        var contentLayout: CGRect
        var contentView: CGRect
        var screen: CGRect
        var backingScale: CGFloat
        var hasFullSizeContent: Bool
        var zoomPercent: Int
        var isSimpleMode: Bool

        /// Title bar and toolbar together.
        var chromeHeight: CGFloat {
            frame.height - contentLayout.height
        }

        var summary: String {
            func size(_ rect: CGRect) -> String {
                "\(Int(rect.width))x\(Int(rect.height))"
            }
            return "window=\(size(frame)) at (\(Int(frame.minX)), \(Int(frame.minY)))"
                + " contentLayout=\(size(contentLayout)) contentView=\(size(contentView))"
                + " chromeHeight=\(Int(chromeHeight)) fullSizeContent=\(hasFullSizeContent)"
                + " screen=\(size(screen)) backingScale=\(backingScale)"
                + " uiZoom=\(zoomPercent)% layout=\(isSimpleMode ? "simple" : "full")"
        }
    }

    /// Logs once the window has had a moment to lay out its toolbar.
    static func logWhenLaidOut(_ window: NSWindow, zoomPercent: Int, isSimpleMode: Bool) {
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let window, window.isVisible else { return }
            let reading = Reading(
                frame: window.frame,
                contentLayout: window.contentLayoutRect,
                contentView: window.contentView?.frame ?? .zero,
                screen: window.screen?.frame ?? .zero,
                backingScale: window.backingScaleFactor,
                hasFullSizeContent: window.styleMask.contains(.fullSizeContentView),
                zoomPercent: zoomPercent,
                isSimpleMode: isSimpleMode
            )
            diagLog.info("Settings window opened: \(reading.summary)")
        }
    }
}
