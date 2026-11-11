//
//  LayoutBarMotionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Timing for the layout bar's AppKit motion.
@MainActor
@Suite("Layout bar motion")
struct LayoutBarMotionTests {
    @Test("A view placed without sliding moves at once, and a slide leaves the shared context's timing alone")
    func placeScopesItsTiming() {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        LayoutBarMotion.place(view, sliding: false, at: CGPoint(x: 30, y: 2))
        #expect(view.frame.origin == CGPoint(x: 30, y: 2))

        let before = NSAnimationContext.current.duration
        LayoutBarMotion.place(view, sliding: true, at: CGPoint(x: 50, y: 2))
        #expect(NSAnimationContext.current.duration == before)
        var point = [Float](repeating: 0, count: 2)
        LayoutBarMotion.easeOut.getControlPoint(at: 1, values: &point)
        #expect(point == [0.23, 1])
    }

    @Test("A fade sets the model alpha and animates the layer from what is on screen")
    func fadeAnimatesTheLayer() throws {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        LayoutBarMotion.fade(view, to: 0.6)
        #expect(view.alphaValue == 0.6)
        let fade = try #require(view.layer?.animation(forKey: "layoutBarFade") as? CABasicAnimation)
        #expect(fade.fromValue as? Float == 1)
        #expect(fade.toValue as? Float == 0.6)

        let still = NSView(frame: .zero)
        still.wantsLayer = true
        LayoutBarMotion.fade(still, to: 1)
        #expect(still.layer?.animation(forKey: "layoutBarFade") == nil, "nothing to fade")
    }

    @Test("The badge grows from its center with a fade, and Reduce Motion keeps only the fade")
    func badgeAppearance() throws {
        let group = try #require(LayoutBarMotion.badgeAppearance(size: CGSize(width: 20, height: 10), reduceMotion: false) as? CAAnimationGroup)
        let grow = try #require(group.animations?.first as? CASpringAnimation)
        let from = try #require((grow.fromValue as? NSValue)?.caTransform3DValue)
        let center = CGPoint(x: 10, y: 5)
        let moved = CGPoint(x: center.x * from.m11 + center.y * from.m21 + from.m41, y: center.x * from.m12 + center.y * from.m22 + from.m42)
        #expect(abs(moved.x - center.x) < 0.001 && abs(moved.y - center.y) < 0.001, "the center stays put")
        #expect(abs(from.m11 - 0.85) < 0.001)

        let reduced = LayoutBarMotion.badgeAppearance(size: CGSize(width: 20, height: 10), reduceMotion: true)
        #expect((reduced as? CABasicAnimation)?.keyPath == "opacity")
    }
}
