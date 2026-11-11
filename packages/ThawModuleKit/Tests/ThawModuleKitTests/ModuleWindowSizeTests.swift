//
//  ModuleWindowSizeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawModuleKit

/// A module's window opened as a bare title bar, because a scrolling form reports no size of its own.
@MainActor
@Suite("Module window size")
struct ModuleWindowSizeTests {
    @Test("The window takes the content's fitting size, capped to the screen")
    func contentSizeIsCapped() {
        #expect(ModuleWindowController.contentSize(fitting: CGSize(width: 520, height: 600), visibleHeight: 900) == CGSize(width: 520, height: 600))
        #expect(ModuleWindowController.contentSize(fitting: CGSize(width: 520, height: 1174), visibleHeight: 900) == CGSize(width: 520, height: 720))
    }

    @Test("A built window shows its content, not just a title bar")
    func builtWindowHasHeight() {
        let window = ModuleWindowController.makeWindow(title: "Test", styleMask: [.titled]) {
            Form { Text("One"); Text("Two") }.formStyle(.grouped).frame(width: 300)
        }
        #expect(window.contentLayoutRect.height > 40)
        #expect(window.contentLayoutRect.width == 300)
    }
}
