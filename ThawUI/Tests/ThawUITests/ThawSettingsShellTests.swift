//
//  ThawSettingsShellTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@Suite("Settings shell")
@MainActor
struct ThawSettingsShellTests {
    @Test("The sidebar opens at the shared width, fixed or draggable", arguments: [nil, 250] as [CGFloat?])
    func sidebarWidth(maxWidth: CGFloat?) async throws {
        let probe = FrameProbe()
        let window = Self.window(
            ThawSettingsShell(title: Text(verbatim: "General"), sidebarMaxWidth: maxWidth) {
                Color.clear.frameProbe(probe)
            } detail: {
                Color.clear
            }
        )
        defer { window.close() }

        await Self.settle { probe.frame != nil }
        let frame = try #require(probe.frame)
        #expect(frame.width == ThawSidebar<Never, EmptyView>.width)
    }

    @Test("The title and the subtitle reach the window")
    func titleReachesTheWindow() async {
        let window = Self.window(
            ThawSettingsShell(title: Text(verbatim: "General"), subtitle: Text(verbatim: "Everyday settings")) {
                Color.clear
            } detail: {
                Color.clear
            }
        )
        defer { window.close() }

        let settled = await Self.settle { window.title == "General" && window.subtitle == "Everyday settings" }
        #expect(settled, "title: \(window.title), subtitle: \(window.subtitle)")
    }

    @Test("A shell with no subtitle sets none")
    func noSubtitle() async {
        let window = Self.window(
            ThawSettingsShell(title: Text(verbatim: "General")) {
                Color.clear
            } detail: {
                Color.clear
            }
        )
        defer { window.close() }

        await Self.settle { window.title == "General" }
        #expect(window.title == "General")
        #expect(window.subtitle.isEmpty)
    }

    @Test("Toolbar items reach the window's toolbar")
    func toolbarReachesTheWindow() async {
        let window = Self.window(
            ThawSettingsShell(title: Text(verbatim: "General")) {
                Color.clear
            } detail: {
                Color.clear
            } toolbar: {
                ToolbarItem(placement: .primaryAction) {
                    Button("More") {}
                }
            }
        )
        defer { window.close() }

        let settled = await Self.settle { (window.toolbar?.items.count ?? 0) > 1 }
        #expect(settled)
    }

    @Test("The detail column is filled, with its content at the top")
    func detailFillsItsColumn() async throws {
        let probe = FrameProbe()
        let window = Self.window(
            ThawSettingsShell(title: Text(verbatim: "General")) {
                Color.clear
            } detail: {
                Color.clear
                    .frame(height: 10)
                    .frameProbe(probe)
            }
        )
        defer { window.close() }

        await Self.settle { probe.frame != nil }
        let frame = try #require(probe.frame)
        #expect(frame.height == 10)
        // Just under the toolbar, not in the middle of the 560 point column.
        #expect(frame.minY < 100)
    }

    /// A window like the apps': titled and unified, with the view's title and toolbar bridged to it.
    private static func window(_ view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        let host = NSHostingView(rootView: view)
        host.sceneBridgingOptions = [.title, .toolbars]
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    @discardableResult
    private static func settle(within timeout: Duration = .seconds(30), until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

@MainActor
private final class FrameProbe {
    var frame: CGRect?
}

private extension View {
    func frameProbe(_ probe: FrameProbe) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.onAppear { probe.frame = geometry.frame(in: .global) }
            }
        }
    }
}
