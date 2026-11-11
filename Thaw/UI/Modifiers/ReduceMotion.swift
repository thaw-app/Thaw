//
//  ReduceMotion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Reduce Motion drops movement and scaling but keeps a short cross-fade, which doesn't move anything.
enum ReduceMotionFade {
    /// Under Reduce Motion, removes the transaction's animation so nothing moves, without disabling the
    /// animations transitions carry, so their fades still play.
    static func apply(to transaction: inout Transaction, reduceMotion: Bool) {
        guard reduceMotion else { return }
        transaction.animation = nil
    }
}

extension AnyTransition {
    /// A fade, with its own animation; under Reduce Motion a quick ease-out instead of none.
    static func fade(reduceMotion: Bool, animation: Animation? = nil) -> AnyTransition {
        fadeAnimation(reduceMotion: reduceMotion, animation: animation).map { .opacity.animation($0) } ?? .opacity
    }

    static func fadeAnimation(reduceMotion: Bool, animation: Animation?) -> Animation? {
        reduceMotion ? ThawMotion.reducedFade : animation
    }
}

extension View {
    /// Stops movement in this view's transactions when Reduce Motion is on, keeping the fades transitions carry.
    func disablesAnimations(when reduceMotion: Bool) -> some View {
        transaction { ReduceMotionFade.apply(to: &$0, reduceMotion: reduceMotion) }
    }
}
