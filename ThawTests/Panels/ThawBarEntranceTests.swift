//
//  ThawBarEntranceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// How the Thaw Bar appears: a short drop out of the menu bar, or a fade under Reduce Motion.
@MainActor
@Suite("Thaw Bar entrance")
struct ThawBarEntranceTests {
    @Test("The entrance is brief, and shorter still under Reduce Motion")
    func durations() {
        #expect(ThawBarEntrance.duration(reduceMotion: false) == 0.16)
        #expect(ThawBarEntrance.duration(reduceMotion: true) == 0.1)
    }

    @Test("The start pose sits above the rest pose and is scaled about the top center")
    func startTransformDropsFromTheMenuBar() {
        let size = CGSize(width: 200, height: 40)
        let start = ThawBarEntrance.startTransform(size: size)
        func apply(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * start.m11 + point.y * start.m21 + start.m41, y: point.x * start.m12 + point.y * start.m22 + start.m42)
        }
        let topCenter = apply(CGPoint(x: 100, y: 40))
        #expect(abs(topCenter.x - 100) < 0.001, "the top center stays centered")
        #expect(abs(topCenter.y - 46) < 0.001, "and starts 6 pt toward the menu bar")
        #expect(abs(start.m11 - 0.97) < 0.001)
    }

    @Test("Dismissing mid-entrance leaves the panel opaque with no animation left")
    func dismissResetsThePanel() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 50, height: 20), styleMask: .borderless, backing: .buffered, defer: true)
        panel.contentView?.wantsLayer = true
        panel.alphaValue = 0.3
        panel.contentView?.layer?.add(CABasicAnimation(keyPath: "transform"), forKey: ThawBarEntrance.animationKey)
        ThawBarEntrance.dismiss(panel)
        #expect(panel.alphaValue == 1)
        #expect(panel.contentView?.layer?.animation(forKey: ThawBarEntrance.animationKey) == nil)
        #expect(!panel.isVisible)
    }

    @Test("Presenting fades the panel in with the drop, and a reopen while visible doesn't restart the drop")
    func presentPlaysOnce() throws {
        let panel = NSPanel(contentRect: CGRect(x: -20000, y: -20000, width: 50, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        defer { ThawBarEntrance.dismiss(panel) }
        ThawBarEntrance.present(panel, reduceMotion: false)
        #expect(panel.isVisible)
        let layer = try #require(panel.contentView?.layer)
        #expect(layer.animation(forKey: ThawBarEntrance.animationKey) != nil)
        layer.removeAnimation(forKey: ThawBarEntrance.animationKey)
        ThawBarEntrance.present(panel, reduceMotion: false)
        #expect(layer.animation(forKey: ThawBarEntrance.animationKey) == nil, "already visible, so no second drop")

        let calm = NSPanel(contentRect: CGRect(x: -20000, y: -20000, width: 50, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        defer { ThawBarEntrance.dismiss(calm) }
        ThawBarEntrance.present(calm, reduceMotion: true)
        #expect(calm.contentView?.layer?.animation(forKey: ThawBarEntrance.animationKey) == nil)
    }

    @Test("The content's animation starts at the drop and ends at rest, with no movement under Reduce Motion")
    func contentAnimation() {
        let moving = ThawBarEntrance.contentAnimation(size: CGSize(width: 200, height: 40), reduceMotion: false)
        #expect(moving?.keyPath == "transform")
        let end = (moving?.toValue as? NSValue)?.caTransform3DValue
        #expect(end.map(CATransform3DIsIdentity) == true)
        #expect(ThawBarEntrance.contentAnimation(size: CGSize(width: 200, height: 40), reduceMotion: true) == nil)
    }
}
