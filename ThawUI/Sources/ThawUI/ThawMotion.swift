//
//  ThawMotion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// Shared timing curves; apply through thawAnimation or withThawAnimation to honor Reduce Motion.
/// Keep timing and the accessibility gate here rather than duplicating them at call sites.
public enum ThawMotion {
    /// A press acknowledging itself.
    public static let instant: Animation = .easeOut(duration: 0.08)
    /// Hover, focus, and selection feedback.
    public static let quick: Animation = .easeOut(duration: 0.12)
    /// Short, insertion-only settings pane swaps; see SettingsView.paneTransition.
    public static let pane: Animation = .easeOut(duration: 0.1)
    /// A surface responding as an object: the hover lift.
    public static let interactive: Animation = .spring(response: 0.25, dampingFraction: 0.8)
    /// Layout finding its place after a change.
    public static let settle: Animation = .smooth(duration: 0.3)
}

// MARK: - Applying motion

public extension View {
    /// Animates value changes unless Reduce Motion is enabled.
    func thawAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(ThawAnimationModifier(animation: animation, value: value))
    }
}

private struct ThawAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

public extension View {
    /// Animates only the closure's modifiers, leaving surrounding layout still, unless Reduce Motion is enabled.
    func thawAnimation(
        _ animation: Animation,
        @ViewBuilder body transform: @escaping (PlaceholderContentView<Self>) -> some View
    ) -> some View {
        ThawScopedAnimation(animation: animation, source: self, transform: transform)
    }
}

/// Preserves the concrete source type required by animation's placeholder; a ViewModifier exposes only opaque Content.
private struct ThawScopedAnimation<Source: View, Result: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let source: Source
    let transform: (PlaceholderContentView<Source>) -> Result

    var body: some View {
        source.animation(reduceMotion ? nil : animation, body: transform)
    }
}

/// Honors Reduce Motion outside SwiftUI by reading the equivalent workspace preference.
@MainActor
public func withThawAnimation<Result>(
    _ animation: Animation,
    _ body: () throws -> Result
) rethrows -> Result {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    return try withAnimation(reduceMotion ? nil : animation, body)
}
