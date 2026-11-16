//
//  MenuBarOverlayContentRaster.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

extension NSView {
    /// Runs this view's draw(_:) on the CPU into one bitmap the size of the view. For views that are not flipped.
    /// AppKit's own path draws through Core Animation's GPU renderer, which holds about 50 MB for seconds after each draw of a bar-wide view.
    func bitmapOfOwnDrawing() -> CGImage? {
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = bitmapImageRepForCachingDisplay(in: bounds),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        draw(bounds)
        return bitmap.cgImage
    }

    /// Replaces the layer's picture with a fresh bitmap of the view's own drawing.
    func showBitmapOfOwnDrawing() {
        guard let layer, let image = bitmapOfOwnDrawing() else { return }
        layer.contentsScale = CGFloat(image.width) / bounds.width
        layer.contents = image
    }
}
