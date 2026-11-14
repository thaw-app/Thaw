//
//  SmartRehideClickTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Smart rehide outside clicks")
struct SmartRehideClickTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// A global mouse monitor hands over events for other apps' windows with no window, which is
    /// what an outside click looks like. The control item has no window until the system seats
    /// its status item, so it must not claim such a click.
    @Test("A click with no window is not a click on a control item that has no window either")
    func windowlessClickIsNotOnWindowlessControlItem() {
        #expect(!HIDEventManager.isClick(in: nil, onControlItemWindow: nil))
    }

    @Test("A click in the control item's window is a click on it")
    func clickInControlItemWindow() {
        let window = makeWindow()
        #expect(HIDEventManager.isClick(in: window, onControlItemWindow: window))
    }

    @Test("A click in another window, or a windowless control item, is not a click on it")
    func clickElsewhere() {
        let window = makeWindow()
        #expect(!HIDEventManager.isClick(in: window, onControlItemWindow: makeWindow()))
        #expect(!HIDEventManager.isClick(in: window, onControlItemWindow: nil))
        #expect(!HIDEventManager.isClick(in: nil, onControlItemWindow: window))
    }
}
