//
//  HotkeyRecorderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Hotkey recorder")
struct HotkeyRecorderTests {
    private final class Log {
        var recording: [Bool] = []
        var captured: [KeyCombination] = []
        var beeps = 0
    }

    private static let strings = HotkeyRecorderStrings(
        typeShortcut: "Press keys",
        recordShortcut: "Set",
        cancel: "Stop",
        clear: "Remove",
        record: "Start",
        spaceKey: "Barra",
        reservedTitle: "Taken",
        reservedMessage: "Try another",
        chooseAnother: "OK"
    )

    private static let commandA = KeyCombination(key: .a, modifiers: .command)

    private func capture(reserved: Set<KeyCombination> = [], log: Log) -> KeyCapture {
        let capture = KeyCapture(isReserved: { reserved.contains($0) }, beep: { log.beeps += 1 })
        capture.start(onRecordingChange: { log.recording.append($0) }, onCapture: { log.captured.append($0) })
        return capture
    }

    private func keyEvent(_ key: KeyCode, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(key.rawValue)
        ))
    }

    @Test("Starting tells the app so it can stand its hotkeys down, once")
    func startReports() {
        let log = Log()
        let capture = capture(log: log)
        defer { capture.stop() }
        capture.start(onRecordingChange: { log.recording.append($0) }, onCapture: { log.captured.append($0) })
        #expect(capture.isListening)
        #expect(log.recording == [true])
    }

    @Test("A usable combination is handed over and ends the recording")
    func acceptsCombination() {
        let log = Log()
        let capture = capture(log: log)
        capture.consider(Self.commandA)
        #expect(log.captured == [Self.commandA])
        #expect(log.recording == [true, false])
        #expect(!capture.isListening)
    }

    @Test("The new combination is stored before the hotkeys come back")
    func capturesBeforeResuming() {
        var order: [String] = []
        let capture = KeyCapture(isReserved: { _ in false }, beep: {
            Issue.record("The combination is usable")
        })
        capture.start(
            onRecordingChange: { order.append($0 ? "start" : "stop") },
            onCapture: { _ in order.append("capture") }
        )
        capture.consider(Self.commandA)
        #expect(order == ["start", "capture", "stop"])
    }

    @Test("Escape backs out without a change, with or without Shift", arguments: [Modifiers(), .shift])
    func escapeCancels(modifiers: Modifiers) {
        let log = Log()
        let capture = capture(log: log)
        capture.consider(KeyCombination(key: .escape, modifiers: modifiers))
        #expect(log.captured.isEmpty)
        #expect(log.beeps == 0)
        #expect(!capture.isListening)
    }

    @Test("A key without a modifier beyond Shift beeps and keeps listening", arguments: [Modifiers(), .shift])
    func bareKeyIsRefused(modifiers: Modifiers) {
        let log = Log()
        let capture = capture(log: log)
        defer { capture.stop() }
        capture.consider(KeyCombination(key: .a, modifiers: modifiers))
        #expect(log.beeps == 1)
        #expect(log.captured.isEmpty)
        #expect(capture.isListening)
    }

    @Test("A combination macOS owns warns, stores nothing and keeps recording")
    func reservedWarns() {
        let log = Log()
        let capture = capture(reserved: [Self.commandA], log: log)
        defer { capture.stop() }
        capture.consider(Self.commandA)
        #expect(capture.isShowingReservedWarning)
        #expect(log.captured.isEmpty)
        #expect(capture.isListening)
    }

    @Test("After the warning the next combination is recorded straight away")
    func recordsAfterWarning() {
        let log = Log()
        let capture = capture(reserved: [Self.commandA], log: log)
        capture.consider(Self.commandA)
        capture.isShowingReservedWarning = false
        let other = KeyCombination(key: .b, modifiers: .command)
        capture.consider(other)
        #expect(log.captured == [other])
    }

    @Test("While recording, key presses are swallowed")
    func swallowsKeys() throws {
        let log = Log()
        let capture = capture(log: log)
        #expect(try capture.intercept(keyEvent(.a, flags: .command)) == nil)
        #expect(log.captured == [Self.commandA])
    }

    @Test("While the warning is up, key presses reach the alert")
    func warningLetsKeysThrough() throws {
        let log = Log()
        let capture = capture(reserved: [Self.commandA], log: log)
        defer { capture.stop() }
        capture.consider(Self.commandA)
        let event = try keyEvent(.returnKey)
        #expect(capture.intercept(event) === event)
        #expect(log.beeps == 0)
    }

    @Test("Stopping twice reports once and clears the warning")
    func stopIsIdempotent() {
        let log = Log()
        let capture = capture(reserved: [Self.commandA], log: log)
        capture.consider(Self.commandA)
        capture.stop()
        capture.stop()
        #expect(log.recording == [true, false])
        #expect(!capture.isShowingReservedWarning)
    }

    private func recorder(_ combination: KeyCombination?, width: CGFloat? = nil) -> some View {
        HotkeyRecorder(keyCombination: .constant(combination), strings: Self.strings, width: width) {
            Text("Open")
        }
    }

    @Test("A fixed width holds whatever the combination")
    func fixedWidth() {
        let short = NSHostingView(rootView: recorder(nil, width: 160).labelsHidden())
        let long = NSHostingView(rootView: recorder(KeyCombination(key: .space, modifiers: [.control, .option, .shift, .command]), width: 160).labelsHidden())
        #expect(short.fittingSize.width == long.fittingSize.width)
        #expect(short.fittingSize.width >= 160)
    }

    @Test("Without a width the control keeps its minimum")
    func flexibleWidth() {
        let view = NSHostingView(rootView: recorder(nil).labelsHidden())
        #expect(view.fittingSize.width >= 132)
    }

    @Test("The combination shows with the app's word for the space bar")
    func spaceWord() {
        let view = HotkeyRecorder(
            keyCombination: .constant(KeyCombination(key: .space, modifiers: .option)),
            strings: Self.strings
        ) {
            Text("Open")
        }
        #expect(view.strings.spaceKey == "Barra")
        #expect(view.title(for: KeyCombination(key: .space, modifiers: .option)) == "⌥ Barra")
    }
}
