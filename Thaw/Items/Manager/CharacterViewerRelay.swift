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

    /// The request is a public name any app can post, so Thaw answers only right after a real
    /// click or key press, which is how a menu item is chosen, and at most once a second.
    nonisolated static let inputWindow: TimeInterval = 1
    nonisolated static let minimumInterval: Duration = .seconds(1)

    private let log = DiagLog(category: "CharacterViewerRelay")
    private var observer: NSObjectProtocol?
    private var lastOpen: ContinuousClock.Instant?

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

    func stop() {
        guard let observer else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
        self.observer = nil
    }

    /// Whether a request should be answered, from what the relay can check.
    nonisolated static func answers(
        standInIsRunning: Bool,
        secondsSinceInput: TimeInterval,
        sinceLastOpen: Duration?
    ) -> Bool {
        guard standInIsRunning, secondsSinceInput <= inputWindow else { return false }
        return sinceLastOpen.map { $0 >= minimumInterval } ?? true
    }

    private func open() {
        let now = ContinuousClock.now
        let answers = Self.answers(
            standInIsRunning: !NSRunningApplication.runningApplications(
                withBundleIdentifier: SystemExtraStandIn.textInput.bundleIdentifier
            ).isEmpty,
            secondsSinceInput: Self.secondsSinceInput(),
            sinceLastOpen: lastOpen.map { $0.duration(to: now) }
        )
        guard answers, AXIsProcessTrusted() else {
            log.notice("ignored a Character Viewer request")
            return
        }
        lastOpen = now
        for event in Self.shortcutEvents() {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Seconds since the last click or key release anywhere in the session.
    private static func secondsSinceInput() -> TimeInterval {
        let state = CGEventSourceStateID.combinedSessionState
        return [CGEventType.leftMouseUp, .keyUp]
            .map { CGEventSource.secondsSinceLastEventType(state, eventType: $0) }
            .min() ?? .infinity
    }
}
