//
//  SyntheticDragInputSession.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

/// Owns pointer takeover for one HID gesture, not its queueing or AX checks.
/// Both the normal exit and the watchdog release the button and input exactly
/// once. After expiry no subsequent frame may reacquire or move the pointer.
@MainActor
final class SyntheticDragInputSession {
    struct Environment {
        var acquire: () throws -> () -> Void
        var post: (MenuBarDragGesture.Phase, CGPoint) throws -> Void
        var reassert: () -> Void

        static func live(source: CGEventSource, watchdogTimeout: Duration) -> Self {
            Self(
                acquire: {
                    guard let location = MouseHelpers.locationCoreGraphics else {
                        throw MenuBarItemManager.EventError.missingMouseLocation
                    }
                    let stopSuppressing = try MoveInputSuppression.suppressUserMouseInput()
                    MouseHelpers.enableBackgroundCursorHiding()
                    // The session watchdog restores all input state first;
                    // retain the existing show-only watchdog as a backstop.
                    MouseHelpers.hideCursor(watchdogTimeout: watchdogTimeout + .seconds(1))
                    MouseHelpers.associateMouseAndCursor(false)
                    return {
                        stopSuppressing()
                        MouseHelpers.warpCursor(to: location)
                        MouseHelpers.associateMouseAndCursor(true)
                        MouseHelpers.showCursor()
                    }
                },
                post: { phase, location in
                    try SyntheticMoveEngine.postMouseEvent(phase, at: location, source: source, address: .hidEventTap)
                },
                reassert: {
                    // Frontmost changes reset visibility and association.
                    MouseHelpers.reassertHiddenCursor()
                    MouseHelpers.associateMouseAndCursor(false)
                }
            )
        }
    }

    private let environment: Environment
    private var restoreInput: (() -> Void)?
    private var watchdog: Task<Void, Never>?
    private var pressedAt: CGPoint?

    init(environment: Environment, watchdogTimeout: Duration = .seconds(10)) throws {
        self.environment = environment
        restoreInput = try environment.acquire()
        watchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: watchdogTimeout)
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    isolated deinit {
        finish()
    }

    func post(_ phase: MenuBarDragGesture.Phase, at point: CGPoint) throws {
        guard restoreInput != nil else { throw MenuBarItemManager.EventError.cannotComplete }
        // Cancellation is checked by the gesture runner, not here: cleanup
        // must be able to post mouse-up from an already cancelled task.
        try environment.post(phase, point)
        switch phase {
        case .down, .dragged: pressedAt = point
        case .up: pressedAt = nil
        case .moved: break
        }
        environment.reassert()
    }

    func finish() {
        guard let restore = restoreInput else { return }
        restoreInput = nil
        watchdog?.cancel()
        watchdog = nil
        if let point = pressedAt {
            try? environment.post(.up, point)
            pressedAt = nil
        }
        restore()
    }
}
