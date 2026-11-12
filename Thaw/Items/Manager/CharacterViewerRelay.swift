//
//  CharacterViewerRelay.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Opens the Character Viewer for the Text Input stand-in's "Show Emoji & Symbols".
///
/// The stand-in runs in the background, and macOS opens no viewer for a background app,
/// so it asks Thaw, which has Accessibility, to press ⌃⌘Space in the app being typed in.
/// Must match CharacterViewerChannel in ThawExtraHelper.
@MainActor
final class CharacterViewerRelay {
    static let shared = CharacterViewerRelay()

    /// ⌃⌘Space, the shortcut for Edit › Emoji & Symbols.
    nonisolated static let keyCode: CGKeyCode = 49
    nonisolated static let flags: CGEventFlags = [.maskControl, .maskCommand]

    private let log = DiagLog(category: "CharacterViewerRelay")
    private var observer: NSObjectProtocol?

    static var notification: Notification.Name {
        notification(parent: ThawMenuBarIdentity.bundleIdentifier)
    }

    nonisolated static func notification(parent: String) -> Notification.Name {
        Notification.Name("\(parent).extra.characterViewer")
    }

    nonisolated static func shortcutEvents() -> [CGEvent] {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return [] }
        for event in [down, up] {
            event.flags = flags
        }
        return [down, up]
    }

    /// Starts listening; calling it again does nothing.
    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.open() }
        }
    }

    private func open() {
        guard AXIsProcessTrusted() else {
            log.notice("no Accessibility permission; cannot open the Character Viewer")
            return
        }
        for event in Self.shortcutEvents() {
            event.post(tap: .cghidEventTap)
        }
    }
}
