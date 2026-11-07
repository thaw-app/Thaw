//
//  HiddenItemCaptureButton.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Takes new pictures of the Hidden and Always Hidden items, and says how it went.
struct HiddenItemCaptureButton: View {
    @Environment(AppState.self) private var appState

    @State private var isCapturing = false
    @State private var result: String?
    @State private var isOptionDown = false
    @State private var flagsMonitor: Any?

    var body: some View {
        Button(Self.title(retakingAll: isOptionDown), systemImage: "camera.viewfinder") {
            capture()
        }
        .buttonStyle(.settingsGlass)
        .disabled(isCapturing)
        .help("Takes pictures of your Hidden and Always Hidden items that have none or a poor one. Hold Option to retake every picture. They may appear in the menu bar for a moment, and with the Native hiding method other icons can move.")
        .onAppear(perform: watchOption)
        .onDisappear(perform: stopWatchingOption)
        .popover(isPresented: isShowingResult) {
            Text(result ?? "")
                .font(ThawType.detail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(ThawSpacing.base)
        }
    }

    private var isShowingResult: Binding<Bool> {
        Binding(get: { result != nil }, set: { if !$0 { result = nil } })
    }

    private func capture() {
        isCapturing = true
        result = nil
        let retakingAll = Self.retakesAll(modifierFlags: NSEvent.modifierFlags)
        Task {
            let outcome = await appState.imageCache.captureHiddenItems(retakingAll: retakingAll)
            let message = Self.message(for: outcome)
            result = message
            isCapturing = false
            AccessibilityAnnouncements.post(message)
        }
    }

    /// Option-click retakes every picture; a plain click leaves good ones alone.
    static func retakesAll(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }

    /// The title says what a click does now, as a menu item's Option alternate does.
    static func title(retakingAll: Bool) -> String {
        retakingAll ? String(localized: "Retake All Pictures") : String(localized: "Capture Hidden Items")
    }

    private func watchOption() {
        isOptionDown = Self.retakesAll(modifierFlags: NSEvent.modifierFlags)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionDown = Self.retakesAll(modifierFlags: event.modifierFlags)
            return event
        }
    }

    private func stopWatchingOption() {
        flagsMonitor.map(NSEvent.removeMonitor)
        flagsMonitor = nil
    }

    static func message(for result: HiddenItemCaptureResult?) -> String {
        guard let result else {
            return String(localized: "Thaw needs Screen Recording permission to capture items.")
        }
        let kept = result.kept > 0
            ? " " + String(localized: "Left \(result.kept) good pictures as they were. Option-click to retake them too.")
            : ""
        guard !result.missing.isEmpty else {
            return String(localized: "Captured \(result.captured) of \(result.total) items.") + kept
        }
        let names = result.missing.formatted(.list(type: .and))
        return String(localized: "Captured \(result.captured) of \(result.total) items. No new picture for: \(names).") + kept
    }
}
