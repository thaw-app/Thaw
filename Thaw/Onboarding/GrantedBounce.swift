//
//  GrantedBounce.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Bounces the symbols in its content once when the permission is granted while they are on screen.
/// One already granted when the content appeared stays still, as does everything under Reduce Motion.
struct GrantedBounce: ViewModifier {
    /// Whether the permission was granted since its card appeared.
    let justGranted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = false

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            .onChange(of: justGranted) { _, granted in
                if Self.bounces(justGranted: granted, reduceMotion: reduceMotion) {
                    trigger.toggle()
                }
            }
    }

    static func bounces(justGranted: Bool, reduceMotion: Bool) -> Bool {
        justGranted && !reduceMotion
    }
}
