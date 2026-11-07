//
//  LayoutBarMotion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Timing for the layout bar's AppKit motion: reorder slides, the dim after a drop and the new-items badge.
@MainActor
enum LayoutBarMotion {
    /// Reorder slides retarget mid-drag, so they ease out; an ease-in-out would restart slow on every update.
    static let slideDuration: TimeInterval = 0.2

    /// Starts fast and lands soft.
    static var easeOut: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    /// Moves view to origin, sliding it in its own animation group so the timing doesn't reach other animations.
    static func place(_ view: NSView, sliding: Bool, at origin: CGPoint) {
        guard sliding else {
            view.setFrameOrigin(origin)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = slideDuration
            context.timingFunction = easeOut
            view.animator().setFrameOrigin(origin)
        }
    }

    /// Fades a view's layer to alpha. NSView's animator alpha finishes in one frame on macOS 27, so the layer
    /// carries the fade. It starts from what is on screen, so a reversal doesn't jump.
    static func fade(_ view: NSView, to alpha: CGFloat, duration: CFTimeInterval = 0.15) {
        view.wantsLayer = true
        guard let layer = view.layer else {
            view.alphaValue = alpha
            return
        }
        let from = layer.presentation()?.opacity ?? Float(view.alphaValue)
        view.alphaValue = alpha
        guard abs(from - Float(alpha)) > 0.001 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = Float(alpha)
        fade.duration = duration
        fade.timingFunction = easeOut
        layer.add(fade, forKey: "layoutBarFade")
    }

    /// The new-items badge's entrance: a short, gentle spring from 0.85 about its center, with a fade.
    /// Reduce Motion keeps only the fade.
    static func badgeAppearance(size: CGSize, reduceMotion: Bool) -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.15
        guard !reduceMotion else { return fade }

        let center = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        let back = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        let scale = CATransform3DConcat(CATransform3DConcat(back, CATransform3DMakeScale(0.85, 0.85, 1)), center)
        let grow = CASpringAnimation(perceptualDuration: 0.35, bounce: 0.15)
        grow.keyPath = "transform"
        grow.fromValue = NSValue(caTransform3D: scale)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = max(grow.settlingDuration, fade.duration)
        return group
    }
}
