//
//  AccessibilityAnnouncementsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Posting an announcement is a fire-and-forget hand-off to the accessibility
/// system, which returns nothing and is a no-op when VoiceOver is not running.
/// There is no observable result to assert, so these check the call is well
/// formed and survives the inputs it can actually be given.
@Suite("Accessibility announcements")
@MainActor
struct AccessibilityAnnouncementsTests {
    @Test("Posting an announcement completes")
    func postCompletes() {
        AccessibilityAnnouncements.post("Hidden section revealed")
    }

    @Test("An empty or very long message is posted the same way")
    func postAcceptsAnyMessage() {
        // Callers build these from item names, which can be empty while a
        // title is still resolving, or long enough to be a whole sentence.
        AccessibilityAnnouncements.post("")
        AccessibilityAnnouncements.post(String(repeating: "a", count: 4096))
        AccessibilityAnnouncements.post("Ítem oculto — 100 % ✅")
    }
}
