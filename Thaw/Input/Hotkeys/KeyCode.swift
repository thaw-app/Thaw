//
//  KeyCode.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox

/// Representation of a physical key on a keyboard.
///
/// The raw value is the platform virtual key code, which identifies where a
/// key sits on the keyboard rather than what it types. The character a key
/// produces depends on the active keyboard layout and is resolved separately
/// by keyEquivalent.
nonisolated struct KeyCode: Codable, Hashable, RawRepresentable {
    let rawValue: Int

    // MARK: Letters

    static let a = KeyCode(rawValue: kVK_ANSI_A)
    static let b = KeyCode(rawValue: kVK_ANSI_B)
    static let c = KeyCode(rawValue: kVK_ANSI_C)
    static let d = KeyCode(rawValue: kVK_ANSI_D)
    static let e = KeyCode(rawValue: kVK_ANSI_E)
    static let f = KeyCode(rawValue: kVK_ANSI_F)
    static let g = KeyCode(rawValue: kVK_ANSI_G)
    static let h = KeyCode(rawValue: kVK_ANSI_H)
    static let i = KeyCode(rawValue: kVK_ANSI_I)
    static let j = KeyCode(rawValue: kVK_ANSI_J)
    static let k = KeyCode(rawValue: kVK_ANSI_K)
    static let l = KeyCode(rawValue: kVK_ANSI_L)
    static let m = KeyCode(rawValue: kVK_ANSI_M)
    static let n = KeyCode(rawValue: kVK_ANSI_N)
    static let o = KeyCode(rawValue: kVK_ANSI_O)
    static let p = KeyCode(rawValue: kVK_ANSI_P)
    static let q = KeyCode(rawValue: kVK_ANSI_Q)
    static let r = KeyCode(rawValue: kVK_ANSI_R)
    static let s = KeyCode(rawValue: kVK_ANSI_S)
    static let t = KeyCode(rawValue: kVK_ANSI_T)
    static let u = KeyCode(rawValue: kVK_ANSI_U)
    static let v = KeyCode(rawValue: kVK_ANSI_V)
    static let w = KeyCode(rawValue: kVK_ANSI_W)
    static let x = KeyCode(rawValue: kVK_ANSI_X)
    static let y = KeyCode(rawValue: kVK_ANSI_Y)
    static let z = KeyCode(rawValue: kVK_ANSI_Z)

    // MARK: Digits

    static let zero = KeyCode(rawValue: kVK_ANSI_0)
    static let one = KeyCode(rawValue: kVK_ANSI_1)
    static let two = KeyCode(rawValue: kVK_ANSI_2)
    static let three = KeyCode(rawValue: kVK_ANSI_3)
    static let four = KeyCode(rawValue: kVK_ANSI_4)
    static let five = KeyCode(rawValue: kVK_ANSI_5)
    static let six = KeyCode(rawValue: kVK_ANSI_6)
    static let seven = KeyCode(rawValue: kVK_ANSI_7)
    static let eight = KeyCode(rawValue: kVK_ANSI_8)
    static let nine = KeyCode(rawValue: kVK_ANSI_9)

    // MARK: Punctuation

    static let grave = KeyCode(rawValue: kVK_ANSI_Grave)
    static let minus = KeyCode(rawValue: kVK_ANSI_Minus)
    static let equal = KeyCode(rawValue: kVK_ANSI_Equal)
    static let leftBracket = KeyCode(rawValue: kVK_ANSI_LeftBracket)
    static let rightBracket = KeyCode(rawValue: kVK_ANSI_RightBracket)
    static let backslash = KeyCode(rawValue: kVK_ANSI_Backslash)
    static let semicolon = KeyCode(rawValue: kVK_ANSI_Semicolon)
    static let quote = KeyCode(rawValue: kVK_ANSI_Quote)
    static let comma = KeyCode(rawValue: kVK_ANSI_Comma)
    static let period = KeyCode(rawValue: kVK_ANSI_Period)
    static let slash = KeyCode(rawValue: kVK_ANSI_Slash)

    // MARK: Whitespace and Deletion

    static let space = KeyCode(rawValue: kVK_Space)
    static let tab = KeyCode(rawValue: kVK_Tab)
    static let returnKey = KeyCode(rawValue: kVK_Return)
    static let delete = KeyCode(rawValue: kVK_Delete)
    static let forwardDelete = KeyCode(rawValue: kVK_ForwardDelete)

    // MARK: Navigation

    static let escape = KeyCode(rawValue: kVK_Escape)
    static let help = KeyCode(rawValue: kVK_Help)
    static let home = KeyCode(rawValue: kVK_Home)
    static let end = KeyCode(rawValue: kVK_End)
    static let pageUp = KeyCode(rawValue: kVK_PageUp)
    static let pageDown = KeyCode(rawValue: kVK_PageDown)
    static let leftArrow = KeyCode(rawValue: kVK_LeftArrow)
    static let rightArrow = KeyCode(rawValue: kVK_RightArrow)
    static let upArrow = KeyCode(rawValue: kVK_UpArrow)
    static let downArrow = KeyCode(rawValue: kVK_DownArrow)

    // MARK: Function Row

    static let f1 = KeyCode(rawValue: kVK_F1)
    static let f2 = KeyCode(rawValue: kVK_F2)
    static let f3 = KeyCode(rawValue: kVK_F3)
    static let f4 = KeyCode(rawValue: kVK_F4)
    static let f5 = KeyCode(rawValue: kVK_F5)
    static let f6 = KeyCode(rawValue: kVK_F6)
    static let f7 = KeyCode(rawValue: kVK_F7)
    static let f8 = KeyCode(rawValue: kVK_F8)
    static let f9 = KeyCode(rawValue: kVK_F9)
    static let f10 = KeyCode(rawValue: kVK_F10)
    static let f11 = KeyCode(rawValue: kVK_F11)
    static let f12 = KeyCode(rawValue: kVK_F12)
    static let f13 = KeyCode(rawValue: kVK_F13)
    static let f14 = KeyCode(rawValue: kVK_F14)
    static let f15 = KeyCode(rawValue: kVK_F15)
    static let f16 = KeyCode(rawValue: kVK_F16)
    static let f17 = KeyCode(rawValue: kVK_F17)
    static let f18 = KeyCode(rawValue: kVK_F18)
    static let f19 = KeyCode(rawValue: kVK_F19)
    static let f20 = KeyCode(rawValue: kVK_F20)

    // MARK: Modifier Keys

    static let capsLock = KeyCode(rawValue: kVK_CapsLock)
    static let function = KeyCode(rawValue: kVK_Function)
    static let control = KeyCode(rawValue: kVK_Control)
    static let rightControl = KeyCode(rawValue: kVK_RightControl)
    static let option = KeyCode(rawValue: kVK_Option)
    static let rightOption = KeyCode(rawValue: kVK_RightOption)
    static let shift = KeyCode(rawValue: kVK_Shift)
    static let rightShift = KeyCode(rawValue: kVK_RightShift)
    static let command = KeyCode(rawValue: kVK_Command)
    static let rightCommand = KeyCode(rawValue: kVK_RightCommand)

    // MARK: Numeric Keypad

    static let keypad0 = KeyCode(rawValue: kVK_ANSI_Keypad0)
    static let keypad1 = KeyCode(rawValue: kVK_ANSI_Keypad1)
    static let keypad2 = KeyCode(rawValue: kVK_ANSI_Keypad2)
    static let keypad3 = KeyCode(rawValue: kVK_ANSI_Keypad3)
    static let keypad4 = KeyCode(rawValue: kVK_ANSI_Keypad4)
    static let keypad5 = KeyCode(rawValue: kVK_ANSI_Keypad5)
    static let keypad6 = KeyCode(rawValue: kVK_ANSI_Keypad6)
    static let keypad7 = KeyCode(rawValue: kVK_ANSI_Keypad7)
    static let keypad8 = KeyCode(rawValue: kVK_ANSI_Keypad8)
    static let keypad9 = KeyCode(rawValue: kVK_ANSI_Keypad9)
    static let keypadDecimal = KeyCode(rawValue: kVK_ANSI_KeypadDecimal)
    static let keypadPlus = KeyCode(rawValue: kVK_ANSI_KeypadPlus)
    static let keypadMinus = KeyCode(rawValue: kVK_ANSI_KeypadMinus)
    static let keypadMultiply = KeyCode(rawValue: kVK_ANSI_KeypadMultiply)
    static let keypadDivide = KeyCode(rawValue: kVK_ANSI_KeypadDivide)
    static let keypadEquals = KeyCode(rawValue: kVK_ANSI_KeypadEquals)
    static let keypadClear = KeyCode(rawValue: kVK_ANSI_KeypadClear)
    static let keypadEnter = KeyCode(rawValue: kVK_ANSI_KeypadEnter)

    // MARK: Volume Keys

    static let volumeUp = KeyCode(rawValue: kVK_VolumeUp)
    static let volumeDown = KeyCode(rawValue: kVK_VolumeDown)
    static let mute = KeyCode(rawValue: kVK_Mute)
}

// MARK: - Keyboard Layout Lookup

/// Asks the active ASCII-capable keyboard layout what the given virtual key
/// types when no modifiers are held.
///
/// - Parameter virtualKey: The virtual key code to translate.
///
/// - Returns: The text the key produces, or nil if the layout is
///   unavailable or the key produces nothing.
private func layoutText(forVirtualKey virtualKey: UInt16) -> String? {
    guard
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
        return nil
    }

    // The layout bytes belong to the input source, so it has to stay alive
    // across the translation below.
    return withExtendedLifetime(source) { () -> String? in
        let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layout) else {
            return nil
        }

        let capacity = 4
        var characters = [UniChar](repeating: 0, count: capacity)
        var characterCount = 0
        var deadKeyState: UInt32 = 0

        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPointer in
            UCKeyTranslate(
                layoutPointer,
                virtualKey,
                UInt16(kUCKeyActionDisplay),
                0, // no modifiers held
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                capacity,
                &characterCount,
                &characters
            )
        }

        guard status == noErr, characterCount > 0 else {
            return nil
        }
        return String(utf16CodeUnits: characters, count: characterCount)
    }
}

// MARK: - Display Labels

/// U+20E3 COMBINING ENCLOSING KEYCAP, which draws the character before it
/// inside a rounded key outline.
private let keycapEnclosure: Character = "\u{20E3}"

/// U+20DD COMBINING ENCLOSING CIRCLE.
private let circleEnclosure: Character = "\u{20DD}"

/// Keys the system prints with a fixed glyph or word instead of the character
/// they type.
private let engravedLabels: [(KeyCode, String)] = [
    (.space, "Space"),
    (.tab, "⇥"),
    (.returnKey, "⏎"),
    (.delete, "⌫"),
    (.forwardDelete, "⌦"),
    (.escape, "⎋"),
    (.help, "?\(circleEnclosure)"),
    (.home, "↖"),
    (.end, "↘"),
    (.pageUp, "⇞"),
    (.pageDown, "⇟"),
    (.leftArrow, "←"),
    (.rightArrow, "→"),
    (.upArrow, "↑"),
    (.downArrow, "↓"),
    (.capsLock, "⇪"),
    (.function, "🌐\u{FE0E}"),
    (.control, "⌃"),
    (.rightControl, "⌃"),
    (.option, "⌥"),
    (.rightOption, "⌥"),
    (.shift, "⇧"),
    (.rightShift, "⇧"),
    (.command, "⌘"),
    (.rightCommand, "⌘"),
    (.keypadClear, "⌧"),
    (.keypadEnter, "⌤"),
    (.volumeUp, "🔊"),
    (.volumeDown, "🔉"),
    (.mute, "🔇"),
]

/// The function row, ordered so that each key's label is its position plus one.
private let functionRow: [KeyCode] = [
    .f1, .f2, .f3, .f4, .f5,
    .f6, .f7, .f8, .f9, .f10,
    .f11, .f12, .f13, .f14, .f15,
    .f16, .f17, .f18, .f19, .f20,
]

/// Keypad keys paired with the character printed on the keycap. Enclosing that
/// character is what tells a keypad key apart from its twin on the main block.
private let keypadFaces: [(KeyCode, Character)] = [
    (.keypad0, "0"),
    (.keypad1, "1"),
    (.keypad2, "2"),
    (.keypad3, "3"),
    (.keypad4, "4"),
    (.keypad5, "5"),
    (.keypad6, "6"),
    (.keypad7, "7"),
    (.keypad8, "8"),
    (.keypad9, "9"),
    (.keypadDecimal, "."),
    (.keypadPlus, "+"),
    (.keypadMinus, "-"),
    (.keypadMultiply, "*"),
    (.keypadDivide, "/"),
    (.keypadEquals, "="),
]

/// Every key that displays as something other than the character it types.
private let keyLabels: [KeyCode: String] = {
    var labels = [KeyCode: String](minimumCapacity: 70)
    for (key, label) in engravedLabels {
        labels[key] = label
    }
    for (position, key) in functionRow.enumerated() {
        labels[key] = "F\(position + 1)"
    }
    for (key, face) in keypadFaces {
        labels[key] = "\(face)\(keycapEnclosure)"
    }
    return labels
}()

// MARK: - String Representations

extension KeyCode {
    /// The text the key types on the current keyboard layout.
    ///
    /// Empty for keys that type nothing, such as the arrow keys.
    var keyEquivalent: String {
        layoutText(forVirtualKey: UInt16(truncatingIfNeeded: rawValue)) ?? ""
    }

    /// A short label for the key, suitable for display in the interface.
    ///
    /// Keys that carry a printed glyph are shown with that glyph; the rest fall
    /// back to whatever they type on the current layout.
    var stringValue: String {
        keyLabels[self] ?? keyEquivalent
    }
}
