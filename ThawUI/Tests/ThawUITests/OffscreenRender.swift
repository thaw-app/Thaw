//
//  OffscreenRender.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing

/// A SwiftUI view hosted in a window that is never shown, so tests can lay it
/// out, draw it into a bitmap and wait for its state changes to apply.
@MainActor
final class OffscreenRender<Content: View> {
    let host: NSHostingView<Content>
    private let window: NSWindow

    init(_ view: Content, size: CGSize) {
        host = NSHostingView(rootView: view)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
    }

    func pixels() throws -> Data {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    /// Lets SwiftUI apply pending updates until condition holds or timeout passes; returns whether it held.
    /// Polls because SwiftUI doesn't signal applied updates. The long default keeps a busy machine from failing a passing test.
    @discardableResult
    func settle(within timeout: Duration = .seconds(30), until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
