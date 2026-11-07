//
//  GrantedBounce.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Bounces the symbols in its content once when they first appear, so a grant lands as an event rather
/// than a quiet swap. Reduce Motion keeps them still.
struct GrantedBounce: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = false

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            .onAppear {
                if Self.bounces(reduceMotion: reduceMotion) {
                    trigger.toggle()
                }
            }
    }

    static func bounces(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
