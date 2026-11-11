//
//  ReduceMotionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// Reduce Motion removed fades too, though a short cross-fade is what it should keep.
@MainActor
@Suite("Reduce Motion")
struct ReduceMotionTests {
    @Test("Under Reduce Motion a fade keeps a quick ease-out; otherwise it keeps the animation it was given")
    func fadeKeepsAQuickFade() {
        #expect(AnyTransition.fadeAnimation(reduceMotion: true, animation: .spring) == ReduceMotionFade.animation)
        #expect(AnyTransition.fadeAnimation(reduceMotion: true, animation: nil) == ReduceMotionFade.animation)
        #expect(AnyTransition.fadeAnimation(reduceMotion: false, animation: .spring) == .spring)
        #expect(AnyTransition.fadeAnimation(reduceMotion: false, animation: nil) == nil)
    }

    @Test("Under Reduce Motion a transaction drops its movement but leaves transitions their own fades")
    func transactionDropsMovement() {
        var reduced = Transaction(animation: .spring)
        ReduceMotionFade.apply(to: &reduced, reduceMotion: true)
        #expect(reduced.animation == nil)
        #expect(!reduced.disablesAnimations)

        var kept = Transaction(animation: .spring)
        ReduceMotionFade.apply(to: &kept, reduceMotion: false)
        #expect(kept.animation == .spring)
    }
}
