//
//  ThawKeyboardList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

public extension View {
    /// Makes a block of hand-drawn rows one keyboard stop that the arrow
    /// keys step through. The system ring around the whole block is off, so
    /// the selected row shows focus with thawFocusRing instead.
    func thawKeyboardList(
        isFocused: FocusState<Bool>.Binding,
        onMove: @escaping (MoveCommandDirection) -> Void
    ) -> some View {
        focusable()
            .focused(isFocused)
            .focusEffectDisabled()
            .onMoveCommand(perform: onMove)
    }

    /// Draws the system keyboard focus ring just outside shape, for the
    /// selected row of a list that has focus.
    func thawFocusRing(_ isShown: Bool, in shape: some InsettableShape) -> some View {
        modifier(ThawFocusRing(isShown: isShown, shape: shape))
    }
}

private struct ThawFocusRing<S: InsettableShape>: ViewModifier {
    /// The width AppKit draws its own focus rings at.
    private static var width: CGFloat {
        3
    }

    @Environment(\.controlActiveState) private var controlActiveState
    let isShown: Bool
    let shape: S

    func body(content: Content) -> some View {
        content
            .overlay {
                if ThawFocusRingRule.isVisible(isShown: isShown, activeState: controlActiveState) {
                    shape
                        .inset(by: -Self.width)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: Self.width)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// When thawFocusRing draws its ring.
enum ThawFocusRingRule {
    /// Only for the row asked to show it, and only while the window is key, as AppKit does.
    static func isVisible(isShown: Bool, activeState: ControlActiveState) -> Bool {
        isShown && activeState == .key
    }
}
