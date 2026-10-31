//
//  KeyCombination.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Carbon.HIToolbox
import os

public nonisolated struct KeyCombination: Hashable, Sendable {
    private static let logger = Logger(subsystem: "ThawUI", category: "KeyCombination")

    public let key: KeyCode
    public let modifiers: Modifiers

    /// The space name is the app's word for the space bar.
    @MainActor
    public func displayValue(spaceName: String) -> String {
        modifiers.symbolicValue + " " + key.stringValue(spaceName: spaceName).capitalized
    }

    @MainActor
    public var isSystemReserved: Bool {
        Self.systemReservedKeyCombinations().contains(self)
    }

    public init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(event: NSEvent) {
        let key = KeyCode(rawValue: Int(event.keyCode))
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        self.init(key: key, modifiers: modifiers)
    }
}

extension KeyCombination {
    /// Reads the symbolic hotkeys the system has claimed for itself.
    private static func systemReservedKeyCombinations() -> [KeyCombination] {
        var symbolicHotkeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&symbolicHotkeys)

        guard status == noErr else {
            logger.error("CopySymbolicHotKeys returned invalid status: \(status)")
            return []
        }
        guard let reservedHotkeys = symbolicHotkeys?.takeRetainedValue() as? [Any] else {
            logger.error("Failed to retrieve symbolic hotkeys")
            return []
        }

        return reservedKeyCombinations(fromSymbolicHotkeys: reservedHotkeys)
    }

    /// The enabled entries of the system's list of symbolic hotkeys. Anything else in the list is skipped.
    static func reservedKeyCombinations(fromSymbolicHotkeys hotkeys: [Any]) -> [KeyCombination] {
        hotkeys.compactMap { element in
            guard
                let hotkey = element as? [String: Any], hotkey[kHISymbolicHotKeyEnabled] as? Bool == true, let keyCode = hotkey[kHISymbolicHotKeyCode] as? Int, let modifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }
            return KeyCombination(
                key: KeyCode(rawValue: keyCode),
                modifiers: Modifiers(carbonFlags: modifiers)
            )
        }
    }
}

// MARK: KeyCombination: Codable

extension KeyCombination: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == 2 else {
            let description = "Expected 2 encoded values, found \(container.count ?? 0)"
            throw DecodingError.dataCorruptedError(in: container, debugDescription: description)
        }
        let rawKey = try container.decode(Int.self)
        // Saved or imported data can hold any number, and Carbon traps on a code it can't take.
        guard KeyCode.validRawValues.contains(rawKey) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Key code \(rawKey) is out of range")
        }
        self.key = KeyCode(rawValue: rawKey)
        self.modifiers = try Modifiers(rawValue: container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key.rawValue)
        try container.encode(modifiers.rawValue)
    }
}
