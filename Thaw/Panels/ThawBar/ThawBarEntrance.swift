//
//  ThawBarEntrance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The Thaw Bar drops a few points out of the menu bar as it fades in, quick enough for a hotkey opened many
/// times a day. Closing stays instant. Reduce Motion keeps a short fade without movement.
@MainActor
enum ThawBarEntrance {
    static let animationKey = "thawBarEntrance"
    private static let drop: CGFloat = 6
    private static let startScale: CGFloat = 0.97

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.1 : 0.16
    }

    /// Scaled about the top center and lifted toward the menu bar; AppKit's layer y runs up.
    static func startTransform(size: CGSize) -> CATransform3D {
        let toOrigin = CATransform3DMakeTranslation(-size.width / 2, -size.height, 0)
        let scaled = CATransform3DConcat(toOrigin, CATransform3DMakeScale(startScale, startScale, 1))
        return CATransform3DConcat(scaled, CATransform3DMakeTranslation(size.width / 2, size.height + drop, 0))
    }

    /// The content's drop, or nil under Reduce Motion. The model transform is left alone, so removing it can't strand the view.
    static func contentAnimation(size: CGSize, reduceMotion: Bool) -> CABasicAnimation? {
        guard !reduceMotion else { return nil }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: startTransform(size: size))
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = duration(reduceMotion: false)
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        return animation
    }

    /// A reopen while the panel is still visible fades on from the alpha it shows, without a second drop.
    static func present(
        _ panel: NSWindow,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        let wasVisible = panel.isVisible
        if !wasVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        if !wasVisible, let content = panel.contentView,
           let drop = contentAnimation(size: content.bounds.size, reduceMotion: reduceMotion)
        {
            content.wantsLayer = true
            content.layer?.add(drop, forKey: animationKey)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration(reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = 1
        }
    }

    /// Orders the panel out at once, ending any entrance still playing so the next open starts clean.
    static func dismiss(_ panel: NSWindow) {
        panel.contentView?.layer?.removeAnimation(forKey: animationKey)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderOut(nil)
    }
}
