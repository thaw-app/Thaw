//
//  ModifiersTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
import Cocoa
@testable import Thaw
import XCTest

// MARK: - Modifiers Tests

final class ModifiersTests: XCTestCase {
    // MARK: - Raw Values

    func testControlRawValue() {
        XCTAssertEqual(Modifiers.control.rawValue, 1 << 0)
    }

    func testOptionRawValue() {
        XCTAssertEqual(Modifiers.option.rawValue, 1 << 1)
    }

    func testShiftRawValue() {
        XCTAssertEqual(Modifiers.shift.rawValue, 1 << 2)
    }

    func testCommandRawValue() {
        XCTAssertEqual(Modifiers.command.rawValue, 1 << 3)
    }

    // MARK: - Canonical Order

    func testCanonicalOrderCount() {
        XCTAssertEqual(Modifiers.canonicalOrder.count, 4)
    }

    func testCanonicalOrderSequence() {
        XCTAssertEqual(Modifiers.canonicalOrder[0], .control)
        XCTAssertEqual(Modifiers.canonicalOrder[1], .option)
        XCTAssertEqual(Modifiers.canonicalOrder[2], .shift)
        XCTAssertEqual(Modifiers.canonicalOrder[3], .command)
    }

    // MARK: - Symbolic Value

    func testSymbolicValueControl() {
        let modifiers: Modifiers = [.control]
        XCTAssertEqual(modifiers.symbolicValue, "⌃")
    }

    func testSymbolicValueOption() {
        let modifiers: Modifiers = [.option]
        XCTAssertEqual(modifiers.symbolicValue, "⌥")
    }

    func testSymbolicValueShift() {
        let modifiers: Modifiers = [.shift]
        XCTAssertEqual(modifiers.symbolicValue, "⇧")
    }

    func testSymbolicValueCommand() {
        let modifiers: Modifiers = [.command]
        XCTAssertEqual(modifiers.symbolicValue, "⌘")
    }

    func testSymbolicValueEmpty() {
        let modifiers: Modifiers = []
        XCTAssertEqual(modifiers.symbolicValue, "")
    }

    func testSymbolicValueAllModifiers() {
        let modifiers: Modifiers = [.control, .option, .shift, .command]
        XCTAssertEqual(modifiers.symbolicValue, "⌃⌥⇧⌘")
    }

    func testSymbolicValueCommandShift() {
        let modifiers: Modifiers = [.command, .shift]
        XCTAssertEqual(modifiers.symbolicValue, "⇧⌘")
    }

    func testSymbolicValueControlOption() {
        let modifiers: Modifiers = [.control, .option]
        XCTAssertEqual(modifiers.symbolicValue, "⌃⌥")
    }

    // MARK: - NSEvent.ModifierFlags Conversion

    func testNSEventFlagsControl() {
        let modifiers: Modifiers = [.control]
        XCTAssertTrue(modifiers.nsEventFlags.contains(.control))
        XCTAssertFalse(modifiers.nsEventFlags.contains(.option))
    }

    func testNSEventFlagsOption() {
        let modifiers: Modifiers = [.option]
        XCTAssertTrue(modifiers.nsEventFlags.contains(.option))
    }

    func testNSEventFlagsShift() {
        let modifiers: Modifiers = [.shift]
        XCTAssertTrue(modifiers.nsEventFlags.contains(.shift))
    }

    func testNSEventFlagsCommand() {
        let modifiers: Modifiers = [.command]
        XCTAssertTrue(modifiers.nsEventFlags.contains(.command))
    }

    func testNSEventFlagsAll() {
        let modifiers: Modifiers = [.control, .option, .shift, .command]
        let flags = modifiers.nsEventFlags

        XCTAssertTrue(flags.contains(.control))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertTrue(flags.contains(.shift))
        XCTAssertTrue(flags.contains(.command))
    }

    func testNSEventFlagsEmpty() {
        let modifiers: Modifiers = []
        XCTAssertTrue(modifiers.nsEventFlags.isEmpty)
    }

    // MARK: - CGEventFlags Conversion

    func testCGEventFlagsControl() {
        let modifiers: Modifiers = [.control]
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskControl))
    }

    func testCGEventFlagsOption() {
        let modifiers: Modifiers = [.option]
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskAlternate))
    }

    func testCGEventFlagsShift() {
        let modifiers: Modifiers = [.shift]
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskShift))
    }

    func testCGEventFlagsCommand() {
        let modifiers: Modifiers = [.command]
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskCommand))
    }

    func testCGEventFlagsAll() {
        let modifiers: Modifiers = [.control, .option, .shift, .command]
        let flags = modifiers.cgEventFlags

        XCTAssertTrue(flags.contains(.maskControl))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertTrue(flags.contains(.maskCommand))
    }

    // MARK: - Carbon Flags Conversion

    func testCarbonFlagsControl() {
        let modifiers: Modifiers = [.control]
        XCTAssertEqual(modifiers.carbonFlags & controlKey, controlKey)
    }

    func testCarbonFlagsOption() {
        let modifiers: Modifiers = [.option]
        XCTAssertEqual(modifiers.carbonFlags & optionKey, optionKey)
    }

    func testCarbonFlagsShift() {
        let modifiers: Modifiers = [.shift]
        XCTAssertEqual(modifiers.carbonFlags & shiftKey, shiftKey)
    }

    func testCarbonFlagsCommand() {
        let modifiers: Modifiers = [.command]
        XCTAssertEqual(modifiers.carbonFlags & cmdKey, cmdKey)
    }

    func testCarbonFlagsEmpty() {
        let modifiers: Modifiers = []
        XCTAssertEqual(modifiers.carbonFlags, 0)
    }

    // MARK: - Init from NSEvent.ModifierFlags

    func testInitFromNSEventFlagsControl() {
        let modifiers = Modifiers(nsEventFlags: .control)
        XCTAssertTrue(modifiers.contains(.control))
        XCTAssertFalse(modifiers.contains(.option))
    }

    func testInitFromNSEventFlagsOption() {
        let modifiers = Modifiers(nsEventFlags: .option)
        XCTAssertTrue(modifiers.contains(.option))
    }

    func testInitFromNSEventFlagsShift() {
        let modifiers = Modifiers(nsEventFlags: .shift)
        XCTAssertTrue(modifiers.contains(.shift))
    }

    func testInitFromNSEventFlagsCommand() {
        let modifiers = Modifiers(nsEventFlags: .command)
        XCTAssertTrue(modifiers.contains(.command))
    }

    func testInitFromNSEventFlagsMultiple() {
        let modifiers = Modifiers(nsEventFlags: [.control, .command])
        XCTAssertTrue(modifiers.contains(.control))
        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertFalse(modifiers.contains(.option))
        XCTAssertFalse(modifiers.contains(.shift))
    }

    // MARK: - Init from CGEventFlags

    func testInitFromCGEventFlagsControl() {
        let modifiers = Modifiers(cgEventFlags: .maskControl)
        XCTAssertTrue(modifiers.contains(.control))
    }

    func testInitFromCGEventFlagsOption() {
        let modifiers = Modifiers(cgEventFlags: .maskAlternate)
        XCTAssertTrue(modifiers.contains(.option))
    }

    func testInitFromCGEventFlagsShift() {
        let modifiers = Modifiers(cgEventFlags: .maskShift)
        XCTAssertTrue(modifiers.contains(.shift))
    }

    func testInitFromCGEventFlagsCommand() {
        let modifiers = Modifiers(cgEventFlags: .maskCommand)
        XCTAssertTrue(modifiers.contains(.command))
    }

    func testInitFromCGEventFlagsMultiple() {
        let modifiers = Modifiers(cgEventFlags: [.maskShift, .maskCommand])
        XCTAssertTrue(modifiers.contains(.shift))
        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertFalse(modifiers.contains(.control))
        XCTAssertFalse(modifiers.contains(.option))
    }

    // MARK: - Init from Carbon Flags

    func testInitFromCarbonFlagsControl() {
        let modifiers = Modifiers(carbonFlags: controlKey)
        XCTAssertTrue(modifiers.contains(.control))
    }

    func testInitFromCarbonFlagsOption() {
        let modifiers = Modifiers(carbonFlags: optionKey)
        XCTAssertTrue(modifiers.contains(.option))
    }

    func testInitFromCarbonFlagsShift() {
        let modifiers = Modifiers(carbonFlags: shiftKey)
        XCTAssertTrue(modifiers.contains(.shift))
    }

    func testInitFromCarbonFlagsCommand() {
        let modifiers = Modifiers(carbonFlags: cmdKey)
        XCTAssertTrue(modifiers.contains(.command))
    }

    func testInitFromCarbonFlagsMultiple() {
        let modifiers = Modifiers(carbonFlags: optionKey | cmdKey)
        XCTAssertTrue(modifiers.contains(.option))
        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertFalse(modifiers.contains(.control))
        XCTAssertFalse(modifiers.contains(.shift))
    }

    // MARK: - Round Trip Conversions

    func testNSEventFlagsRoundTrip() {
        let original: Modifiers = [.control, .shift, .command]
        let flags = original.nsEventFlags
        let roundTrip = Modifiers(nsEventFlags: flags)

        XCTAssertEqual(original, roundTrip)
    }

    func testCGEventFlagsRoundTrip() {
        let original: Modifiers = [.option, .command]
        let flags = original.cgEventFlags
        let roundTrip = Modifiers(cgEventFlags: flags)

        XCTAssertEqual(original, roundTrip)
    }

    func testCarbonFlagsRoundTrip() {
        let original: Modifiers = [.control, .option, .shift, .command]
        let flags = original.carbonFlags
        let roundTrip = Modifiers(carbonFlags: flags)

        XCTAssertEqual(original, roundTrip)
    }

    // MARK: - Codable

    func testEncodeDecode() throws {
        let original: Modifiers = [.control, .command]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Modifiers.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testEncodeDecodeEmpty() throws {
        let original: Modifiers = []

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Modifiers.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testEncodeDecodeAllModifiers() throws {
        let original: Modifiers = [.control, .option, .shift, .command]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Modifiers.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Hashable

    func testHashableInSet() {
        var set = Set<Modifiers>()
        set.insert([.command])
        set.insert([.command, .shift])
        set.insert([.command]) // duplicate

        XCTAssertEqual(set.count, 2)
    }
}
