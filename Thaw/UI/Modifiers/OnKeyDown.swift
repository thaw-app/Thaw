//
//  OnKeyDown.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension View {
    /// Performs action when key is pressed in the window hosting this
    /// view, whatever inside that window holds focus.
    ///
    /// Prefer onKeyPress, which lets the responder chain decide. This is
    /// for the one shape it cannot express: a control that must answer the
    /// keyboard while focus deliberately sits somewhere else, the search
    /// panel's list, arrowed through while the caret stays in the field.
    /// isEnabled is the caller's whole say in when it stands down, so gate
    /// it on the state that makes the key the caller's to take.
    func onKeyDown(
        key: KeyCode,
        isEnabled: Bool = true,
        action: @escaping () -> KeyCode.PressResult
    ) -> some View {
        modifier(OnKeyDownModifier(key: key, isEnabled: isEnabled, action: action))
    }
}

private struct OnKeyDownModifier: ViewModifier {
    /// The window this view is in, so keys pressed in the app's other
    /// windows are not answered here. A local monitor sees the whole
    /// process, and Thaw keeps several windows and panels open at once.
    @State private var hostWindow: NSWindow?

    let key: KeyCode
    let isEnabled: Bool
    let action: () -> KeyCode.PressResult

    func body(content: Content) -> some View {
        content
            .onWindowChange(update: $hostWindow)
            .localEventMonitor(mask: .keyDown, isEnabled: isEnabled && hostWindow != nil) { event in
                guard event.window === hostWindow, event.keyCode == key.rawValue else {
                    return event
                }
                return switch action() {
                case .handled: nil
                case .ignored: event
                }
            }
    }
}

extension KeyCode {
    /// A result value from a key press action that indicates
    /// whether the action consumed the event.
    enum PressResult {
        /// The action consumed the event, preventing dispatch
        /// from continuing.
        case handled

        /// The action ignored the event, allowing dispatch to
        /// continue.
        case ignored
    }
}
