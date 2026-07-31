//
//  ModifiersTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
import Cocoa
import Testing
@testable import Thaw

// MARK: - Modifiers Tests

@Suite("Modifiers")
struct ModifiersTests {
    // MARK: - Raw Values

    @Test("Control is bit 0")
    func controlRawValue() {
        #expect(Modifiers.control.rawValue == 1 << 0)
    }

    @Test("Option is bit 1")
    func optionRawValue() {
        #expect(Modifiers.option.rawValue == 1 << 1)
    }

    @Test("Shift is bit 2")
    func shiftRawValue() {
        #expect(Modifiers.shift.rawValue == 1 << 2)
    }

    @Test("Command is bit 3")
    func commandRawValue() {
        #expect(Modifiers.command.rawValue == 1 << 3)
    }

    // MARK: - Canonical Order

    @Test("The canonical order holds four modifiers")
    func canonicalOrderCount() {
        #expect(Modifiers.canonicalOrder.count == 4)
    }

    @Test("The canonical order is control, option, shift, command")
    func canonicalOrderSequence() {
        #expect(Modifiers.canonicalOrder[0] == .control)
        #expect(Modifiers.canonicalOrder[1] == .option)
        #expect(Modifiers.canonicalOrder[2] == .shift)
        #expect(Modifiers.canonicalOrder[3] == .command)
    }

    // MARK: - Symbolic Value

    @Test("Control renders as ⌃")
    func symbolicValueControl() {
        let modifiers: Modifiers = [.control]
        #expect(modifiers.symbolicValue == "⌃")
    }

    @Test("Option renders as ⌥")
    func symbolicValueOption() {
        let modifiers: Modifiers = [.option]
        #expect(modifiers.symbolicValue == "⌥")
    }

    @Test("Shift renders as ⇧")
    func symbolicValueShift() {
        let modifiers: Modifiers = [.shift]
        #expect(modifiers.symbolicValue == "⇧")
    }

    @Test("Command renders as ⌘")
    func symbolicValueCommand() {
        let modifiers: Modifiers = [.command]
        #expect(modifiers.symbolicValue == "⌘")
    }

    @Test("An empty set renders as an empty string")
    func symbolicValueEmpty() {
        let modifiers: Modifiers = []
        #expect(modifiers.symbolicValue == "")
    }

    @Test("All four modifiers render in canonical order")
    func symbolicValueAllModifiers() {
        let modifiers: Modifiers = [.control, .option, .shift, .command]
        #expect(modifiers.symbolicValue == "⌃⌥⇧⌘")
    }

    @Test("Command and shift render in canonical order")
    func symbolicValueCommandShift() {
        let modifiers: Modifiers = [.command, .shift]
        #expect(modifiers.symbolicValue == "⇧⌘")
    }

    @Test("Control and option render in canonical order")
    func symbolicValueControlOption() {
        let modifiers: Modifiers = [.control, .option]
        #expect(modifiers.symbolicValue == "⌃⌥")
    }

    // MARK: - NSEvent.ModifierFlags Conversion

    @Test("Control converts to the control event flag alone")
    func nsEventFlagsControl() {
        let modifiers: Modifiers = [.control]
        #expect(modifiers.nsEventFlags.contains(.control))
        #expect(!modifiers.nsEventFlags.contains(.option))
    }

    @Test("Option converts to the option event flag")
    func nsEventFlagsOption() {
        let modifiers: Modifiers = [.option]
        #expect(modifiers.nsEventFlags.contains(.option))
    }

    @Test("Shift converts to the shift event flag")
    func nsEventFlagsShift() {
        let modifiers: Modifiers = [.shift]
        #expect(modifiers.nsEventFlags.contains(.shift))
    }

    @Test("Command converts to the command event flag")
    func nsEventFlagsCommand() {
        let modifiers: Modifiers = [.command]
        #expect(modifiers.nsEventFlags.contains(.command))
    }

    @Test("All four modifiers convert to all four event flags")
    func nsEventFlagsAll() {
        let modifiers: Modifiers = [.control, .option, .shift, .command]
        let flags = modifiers.nsEventFlags

        #expect(flags.contains(.control))
        #expect(flags.contains(.option))
        #expect(flags.contains(.shift))
        #expect(flags.contains(.command))
    }

    @Test("An empty set converts to no event flags")
    func nsEventFlagsEmpty() {
        let modifiers: Modifiers = []
        #expect(modifiers.nsEventFlags.isEmpty)
    }

    // MARK: - CGEventFlags Conversion

    @Test("Control converts to the control CG mask")
    func cgEventFlagsControl() {
        let modifiers: Modifiers = [.control]
        #expect(modifiers.cgEventFlags.contains(.maskControl))
    }

    @Test("Option converts to the alternate CG mask")
    func cgEventFlagsOption() {
        let modifiers: Modifiers = [.option]
        #expect(modifiers.cgEventFlags.contains(.maskAlternate))
    }

    @Test("Shift converts to the shift CG mask")
    func cgEventFlagsShift() {
        let modifiers: Modifiers = [.shift]
        #expect(modifiers.cgEventFlags.contains(.maskShift))
    }

    @Test("Command converts to the command CG mask")
    func cgEventFlagsCommand() {
        let modifiers: Modifiers = [.command]
        #expect(modifiers.cgEventFlags.contains(.maskCommand))
    }

    @Test("All four modifiers convert to all four CG masks")
    func cgEventFlagsAll() {
        let modifiers: Modifiers = [.control, .option, .shift, .command]
        let flags = modifiers.cgEventFlags

        #expect(flags.contains(.maskControl))
        #expect(flags.contains(.maskAlternate))
        #expect(flags.contains(.maskShift))
        #expect(flags.contains(.maskCommand))
    }

    // MARK: - Carbon Flags Conversion

    @Test("Control converts to the Carbon control key")
    func carbonFlagsControl() {
        let modifiers: Modifiers = [.control]
        #expect(modifiers.carbonFlags & controlKey == controlKey)
    }

    @Test("Option converts to the Carbon option key")
    func carbonFlagsOption() {
        let modifiers: Modifiers = [.option]
        #expect(modifiers.carbonFlags & optionKey == optionKey)
    }

    @Test("Shift converts to the Carbon shift key")
    func carbonFlagsShift() {
        let modifiers: Modifiers = [.shift]
        #expect(modifiers.carbonFlags & shiftKey == shiftKey)
    }

    @Test("Command converts to the Carbon command key")
    func carbonFlagsCommand() {
        let modifiers: Modifiers = [.command]
        #expect(modifiers.carbonFlags & cmdKey == cmdKey)
    }

    @Test("An empty set converts to no Carbon flags")
    func carbonFlagsEmpty() {
        let modifiers: Modifiers = []
        #expect(modifiers.carbonFlags == 0)
    }

    // MARK: - Init from NSEvent.ModifierFlags

    @Test("The control event flag initializes control alone")
    func initFromNSEventFlagsControl() {
        let modifiers = Modifiers(nsEventFlags: .control)
        #expect(modifiers.contains(.control))
        #expect(!modifiers.contains(.option))
    }

    @Test("The option event flag initializes option")
    func initFromNSEventFlagsOption() {
        let modifiers = Modifiers(nsEventFlags: .option)
        #expect(modifiers.contains(.option))
    }

    @Test("The shift event flag initializes shift")
    func initFromNSEventFlagsShift() {
        let modifiers = Modifiers(nsEventFlags: .shift)
        #expect(modifiers.contains(.shift))
    }

    @Test("The command event flag initializes command")
    func initFromNSEventFlagsCommand() {
        let modifiers = Modifiers(nsEventFlags: .command)
        #expect(modifiers.contains(.command))
    }

    @Test("Multiple event flags initialize exactly those modifiers")
    func initFromNSEventFlagsMultiple() {
        let modifiers = Modifiers(nsEventFlags: [.control, .command])
        #expect(modifiers.contains(.control))
        #expect(modifiers.contains(.command))
        #expect(!modifiers.contains(.option))
        #expect(!modifiers.contains(.shift))
    }

    // MARK: - Init from CGEventFlags

    @Test("The control CG mask initializes control")
    func initFromCGEventFlagsControl() {
        let modifiers = Modifiers(cgEventFlags: .maskControl)
        #expect(modifiers.contains(.control))
    }

    @Test("The alternate CG mask initializes option")
    func initFromCGEventFlagsOption() {
        let modifiers = Modifiers(cgEventFlags: .maskAlternate)
        #expect(modifiers.contains(.option))
    }

    @Test("The shift CG mask initializes shift")
    func initFromCGEventFlagsShift() {
        let modifiers = Modifiers(cgEventFlags: .maskShift)
        #expect(modifiers.contains(.shift))
    }

    @Test("The command CG mask initializes command")
    func initFromCGEventFlagsCommand() {
        let modifiers = Modifiers(cgEventFlags: .maskCommand)
        #expect(modifiers.contains(.command))
    }

    @Test("Multiple CG masks initialize exactly those modifiers")
    func initFromCGEventFlagsMultiple() {
        let modifiers = Modifiers(cgEventFlags: [.maskShift, .maskCommand])
        #expect(modifiers.contains(.shift))
        #expect(modifiers.contains(.command))
        #expect(!modifiers.contains(.control))
        #expect(!modifiers.contains(.option))
    }

    // MARK: - Init from Carbon Flags

    @Test("The Carbon control key initializes control")
    func initFromCarbonFlagsControl() {
        let modifiers = Modifiers(carbonFlags: controlKey)
        #expect(modifiers.contains(.control))
    }

    @Test("The Carbon option key initializes option")
    func initFromCarbonFlagsOption() {
        let modifiers = Modifiers(carbonFlags: optionKey)
        #expect(modifiers.contains(.option))
    }

    @Test("The Carbon shift key initializes shift")
    func initFromCarbonFlagsShift() {
        let modifiers = Modifiers(carbonFlags: shiftKey)
        #expect(modifiers.contains(.shift))
    }

    @Test("The Carbon command key initializes command")
    func initFromCarbonFlagsCommand() {
        let modifiers = Modifiers(carbonFlags: cmdKey)
        #expect(modifiers.contains(.command))
    }

    @Test("Multiple Carbon keys initialize exactly those modifiers")
    func initFromCarbonFlagsMultiple() {
        let modifiers = Modifiers(carbonFlags: optionKey | cmdKey)
        #expect(modifiers.contains(.option))
        #expect(modifiers.contains(.command))
        #expect(!modifiers.contains(.control))
        #expect(!modifiers.contains(.shift))
    }

    // MARK: - Round Trip Conversions

    @Test("Event flags survive a round trip")
    func nsEventFlagsRoundTrip() {
        let original: Modifiers = [.control, .shift, .command]
        let flags = original.nsEventFlags
        let roundTrip = Modifiers(nsEventFlags: flags)

        #expect(original == roundTrip)
    }

    @Test("CG masks survive a round trip")
    func cgEventFlagsRoundTrip() {
        let original: Modifiers = [.option, .command]
        let flags = original.cgEventFlags
        let roundTrip = Modifiers(cgEventFlags: flags)

        #expect(original == roundTrip)
    }

    @Test("Carbon flags survive a round trip")
    func carbonFlagsRoundTrip() {
        let original: Modifiers = [.control, .option, .shift, .command]
        let flags = original.carbonFlags
        let roundTrip = Modifiers(carbonFlags: flags)

        #expect(original == roundTrip)
    }

    // MARK: - Codable

    @Test("A pair of modifiers survives an encode/decode round trip")
    func encodeDecode() throws {
        let original: Modifiers = [.control, .command]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Modifiers.self, from: data)

        #expect(original == decoded)
    }

    @Test("An empty set survives an encode/decode round trip")
    func encodeDecodeEmpty() throws {
        let original: Modifiers = []

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Modifiers.self, from: data)

        #expect(original == decoded)
    }

    @Test("All four modifiers survive an encode/decode round trip")
    func encodeDecodeAllModifiers() throws {
        let original: Modifiers = [.control, .option, .shift, .command]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Modifiers.self, from: data)

        #expect(original == decoded)
    }

    // MARK: - Hashable

    @Test("Order of insertion does not change the hash")
    func hashableConsistency() {
        let modifiers1: Modifiers = [.command, .shift]
        let modifiers2: Modifiers = [.shift, .command]

        #expect(modifiers1.hashValue == modifiers2.hashValue)
    }

    @Test("A set deduplicates equal modifier sets")
    func hashableInSet() {
        var set = Set<Modifiers>()
        set.insert([.command])
        set.insert([.command, .shift])
        set.insert([.command]) // duplicate

        #expect(set.count == 2)
    }
}
