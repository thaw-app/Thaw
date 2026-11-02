//
//  HiddenItemCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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
        #expect(result.missing == ["OneDrive", "Tailscale"])
    }

    @Test("Each outcome gets a message, naming what's missing")
    func messages() {
        #expect(HiddenItemCaptureButton.message(for: nil).contains("Screen Recording"))
        let complete = HiddenItemCaptureResult(captured: 2, missing: [])
        #expect(!HiddenItemCaptureButton.message(for: complete).contains("No picture"))
        let partial = HiddenItemCaptureResult(captured: 1, missing: ["Tailscale"])
        #expect(HiddenItemCaptureButton.message(for: partial).contains("Tailscale"))
    }
}
