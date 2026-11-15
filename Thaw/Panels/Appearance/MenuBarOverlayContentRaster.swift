//
//  MenuBarOverlayContentRaster.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

extension NSView {
    /// Runs this view's draw(_:) on the CPU into one bitmap the size of the view.
    ///
    /// AppKit's own display path hands a view's drawing to Core Animation's GPU
    /// renderer inside this process. For a view as wide as the menu bar, that
    /// renderer holds about 50 MB of buffers for a few seconds after every draw.
    /// One bitmap costs its own size and nothing more. For views that are not flipped.
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
