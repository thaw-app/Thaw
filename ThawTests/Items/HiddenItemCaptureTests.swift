//
//  HiddenItemCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Hidden item capture")
struct HiddenItemCaptureTests {
    @Test("The tally counts pictures and lists each missing name once")
    func tally() {
        let result = HiddenItemCaptureResult.tally([
            (name: "Hue Sync", hasImage: true),
            (name: "OneDrive", hasImage: false),
            (name: "OneDrive", hasImage: false),
            (name: "Tailscale", hasImage: false),
        ])
        #expect(result.captured == 1)
        #expect(result.total == 4)
        #expect(result.missing == ["OneDrive", "Tailscale"])
    }

    @Test("Items left alone for already having a good picture are counted apart, not as missing")
    func keptPicturesAreCountedApart() {
        let result = HiddenItemCaptureResult.tally([(name: "Tailscale", hasImage: true)], kept: 3)
        #expect(result.captured == 1)
        #expect(result.total == 1)
        #expect(result.kept == 3)
        #expect(result.missing.isEmpty)
        #expect(HiddenItemCaptureButton.message(for: result).contains("3"))
        #expect(HiddenItemCaptureButton.message(for: .tally([(name: "Tailscale", hasImage: true)])).contains("kept") == false)
    }

    @Test("Option-click retakes every picture; a plain click only the missing and weak ones")
    func optionRetakesAll() {
        #expect(HiddenItemCaptureButton.retakesAll(modifierFlags: [.option]))
        #expect(HiddenItemCaptureButton.retakesAll(modifierFlags: [.option, .shift]))
        #expect(!HiddenItemCaptureButton.retakesAll(modifierFlags: []))
        #expect(!HiddenItemCaptureButton.retakesAll(modifierFlags: [.command]))
    }

    @Test("A kept picture stays kept when the menu bar rebuilds its window", arguments: [UInt32(9), UInt32(10)])
    func rebuiltKeptPicture(windowID: UInt32) {
        let current = item(.string("com.example.app"), "Item-0")
        let saved = MenuBarItemTag(namespace: current.tag.namespace, title: current.tag.title, windowID: windowID, instanceIndex: 0)
        let result = MenuBarItemImageCache.hiddenItemCaptureResult(items: [current], alreadyGood: [saved], newlyCaptured: [])
        #expect(result == HiddenItemCaptureResult(captured: 0, total: 0, missing: [], kept: 1))
    }

    @Test("A new picture counts even when replacing a kept picture", arguments: [false, true])
    func newlyCapturedPicture(wasGood: Bool) {
        let current = item(.string("com.example.app"), "Item-0")
        let saved = MenuBarItemTag(namespace: current.tag.namespace, title: current.tag.title, windowID: 10, instanceIndex: 0)
        let result = MenuBarItemImageCache.hiddenItemCaptureResult(
            items: [current], alreadyGood: wasGood ? [saved] : [], newlyCaptured: [saved]
        )
        #expect(result == HiddenItemCaptureResult(captured: 1, total: 1, missing: [], kept: 0))
    }

    @Test("A kept picture of another instance does not hide a missing picture")
    func differentInstanceIsMissing() {
        let current = item(.string("com.example.app"), "Item-0")
        let other = MenuBarItemTag(namespace: current.tag.namespace, title: current.tag.title, windowID: 10, instanceIndex: 1)
        let result = MenuBarItemImageCache.hiddenItemCaptureResult(items: [current], alreadyGood: [other], newlyCaptured: [])
        #expect(result == HiddenItemCaptureResult(captured: 0, total: 1, missing: [current.displayName]))
    }

    private func item(_ namespace: MenuBarItemTag.Namespace, _ title: String, width: CGFloat = 24) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, windowID: 9, instanceIndex: 0),
            windowID: 9,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 900, y: 4, width: width, height: 24),
            title: nil,
            isOnScreen: true
        )
    }

    @Test("A hidden Control Center module is left out, since showing it never draws it")
    func controlCenterModulesAreSkipped() {
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        #expect(cache.prewarmSkips(item(.menuBarAgent, "com.apple.menuextra.bluetooth")))
        #expect(cache.prewarmSkips(item(.menuBarAgent, "com.apple.menuextra.wifi")))
        #expect(!cache.prewarmSkips(item(.string("com.example.app"), "Item-0")))
        #expect(cache.prewarmSkips(item(.string("com.example.app"), "Item-0", width: 2)), "A blank item is still left out")
    }

    @Test("Each outcome gets a message, naming what's missing")
    func messages() {
        #expect(HiddenItemCaptureButton.message(for: nil).contains("Screen Recording"))
        let complete = HiddenItemCaptureResult(captured: 2, total: 2, missing: [])
        #expect(!HiddenItemCaptureButton.message(for: complete).contains("No new picture"))
        let partial = HiddenItemCaptureResult(captured: 1, total: 2, missing: ["Tailscale"])
        #expect(HiddenItemCaptureButton.message(for: partial).contains("Tailscale"))
    }
}
