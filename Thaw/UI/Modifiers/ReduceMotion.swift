//
//  ReduceMotion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension AnyTransition {
    /// A fade, optionally with its own animation, or no transition when Reduce Motion is on.
    static func fade(reduceMotion: Bool, animation: Animation? = nil) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return animation.map { .opacity.animation($0) } ?? .opacity
    }
}

extension View {
    /// Turns off every animation in this view's transactions when Reduce Motion is on.
    func disablesAnimations(when reduceMotion: Bool) -> some View {
        transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}
