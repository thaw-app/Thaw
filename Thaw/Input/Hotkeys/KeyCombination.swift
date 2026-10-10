//
//  KeyCombination.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
import Cocoa
import MenuBarModel

struct KeyCombination: Hashable {
    private static let diagLog = DiagLog(category: "KeyCombination")

    let key: KeyCode
    let modifiers: Modifiers

    /// A string representation for the key combination suitable
    /// for display.
    var displayValue: String {
        modifiers.symbolicValue + " " + key.stringValue.capitalized
    }

    /// Returns a Boolean value that indicates whether this key
    /// combination is reserved for system use.
    var isSystemReserved: Bool {
        Self.systemReservedKeyCombinations().contains(self)
    }

    init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        let key = KeyCode(rawValue: Int(event.keyCode))
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        self.init(key: key, modifiers: modifiers)
    }
}

private extension KeyCombination {
    /// Reads the symbolic hotkeys the system has claimed for itself.
    static func systemReservedKeyCombinations() -> [KeyCombination] {
        var symbolicHotkeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&symbolicHotkeys)

        guard status == noErr else {
            diagLog.error("CopySymbolicHotKeys returned invalid status: \(status)")
            return []
        }
        guard let reservedHotkeys = Bridging.arrayValue(of: symbolicHotkeys?.takeRetainedValue()) else {
            diagLog.error("Failed to retrieve symbolic hotkeys")
            return []
        }

        return reservedHotkeys.compactMap { element in
            guard
                let hotkey: [String: Any] = Bridging.dictionaryValue(of: element as CFTypeRef),
                hotkey[kHISymbolicHotKeyEnabled] as? Bool == true,
                let keyCode = hotkey[kHISymbolicHotKeyCode] as? Int,
                let modifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
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
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == 2 else {
            let description = "Expected 2 encoded values, found \(container.count ?? 0)"
            throw DecodingError.dataCorruptedError(in: container, debugDescription: description)
        }
        self.key = try KeyCode(rawValue: container.decode(Int.self))
        self.modifiers = try Modifiers(rawValue: container.decode(Int.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key.rawValue)
        try container.encode(modifiers.rawValue)
    }
}
