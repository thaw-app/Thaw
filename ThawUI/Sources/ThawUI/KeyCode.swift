//
//  KeyCode.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox

/// A physical key. The raw value is the platform virtual key code, which identifies where a key sits
/// rather than what it types; keyEquivalent resolves the character on the active layout.
public nonisolated struct KeyCode: Codable, Hashable, RawRepresentable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The codes a key event can carry, which is also what Carbon accepts.
    public static let validRawValues = 0 ... Int(UInt16.max)

    /// Whether the code is one a real key event can carry.
    public var isValid: Bool {
        Self.validRawValues.contains(rawValue)
    }

    // MARK: Letters

    public static let a = KeyCode(rawValue: kVK_ANSI_A)
    public static let b = KeyCode(rawValue: kVK_ANSI_B)
    public static let c = KeyCode(rawValue: kVK_ANSI_C)
    public static let d = KeyCode(rawValue: kVK_ANSI_D)
    public static let e = KeyCode(rawValue: kVK_ANSI_E)
    public static let f = KeyCode(rawValue: kVK_ANSI_F)
    public static let g = KeyCode(rawValue: kVK_ANSI_G)
    public static let h = KeyCode(rawValue: kVK_ANSI_H)
    public static let i = KeyCode(rawValue: kVK_ANSI_I)
    public static let j = KeyCode(rawValue: kVK_ANSI_J)
    public static let k = KeyCode(rawValue: kVK_ANSI_K)
    public static let l = KeyCode(rawValue: kVK_ANSI_L)
    public static let m = KeyCode(rawValue: kVK_ANSI_M)
    public static let n = KeyCode(rawValue: kVK_ANSI_N)
    public static let o = KeyCode(rawValue: kVK_ANSI_O)
    public static let p = KeyCode(rawValue: kVK_ANSI_P)
    public static let q = KeyCode(rawValue: kVK_ANSI_Q)
    public static let r = KeyCode(rawValue: kVK_ANSI_R)
    public static let s = KeyCode(rawValue: kVK_ANSI_S)
    public static let t = KeyCode(rawValue: kVK_ANSI_T)
    public static let u = KeyCode(rawValue: kVK_ANSI_U)
    public static let v = KeyCode(rawValue: kVK_ANSI_V)
    public static let w = KeyCode(rawValue: kVK_ANSI_W)
    public static let x = KeyCode(rawValue: kVK_ANSI_X)
    public static let y = KeyCode(rawValue: kVK_ANSI_Y)
    public static let z = KeyCode(rawValue: kVK_ANSI_Z)

    // MARK: Digits

    public static let zero = KeyCode(rawValue: kVK_ANSI_0)
    public static let one = KeyCode(rawValue: kVK_ANSI_1)
    public static let two = KeyCode(rawValue: kVK_ANSI_2)
    public static let three = KeyCode(rawValue: kVK_ANSI_3)
    public static let four = KeyCode(rawValue: kVK_ANSI_4)
    public static let five = KeyCode(rawValue: kVK_ANSI_5)
    public static let six = KeyCode(rawValue: kVK_ANSI_6)
    public static let seven = KeyCode(rawValue: kVK_ANSI_7)
    public static let eight = KeyCode(rawValue: kVK_ANSI_8)
    public static let nine = KeyCode(rawValue: kVK_ANSI_9)

    // MARK: Punctuation

    public static let grave = KeyCode(rawValue: kVK_ANSI_Grave)
    public static let minus = KeyCode(rawValue: kVK_ANSI_Minus)
    public static let equal = KeyCode(rawValue: kVK_ANSI_Equal)
    public static let leftBracket = KeyCode(rawValue: kVK_ANSI_LeftBracket)
    public static let rightBracket = KeyCode(rawValue: kVK_ANSI_RightBracket)
    public static let backslash = KeyCode(rawValue: kVK_ANSI_Backslash)
    public static let semicolon = KeyCode(rawValue: kVK_ANSI_Semicolon)
    public static let quote = KeyCode(rawValue: kVK_ANSI_Quote)
    public static let comma = KeyCode(rawValue: kVK_ANSI_Comma)
    public static let period = KeyCode(rawValue: kVK_ANSI_Period)
    public static let slash = KeyCode(rawValue: kVK_ANSI_Slash)

    // MARK: Whitespace and Deletion

    public static let space = KeyCode(rawValue: kVK_Space)
    public static let tab = KeyCode(rawValue: kVK_Tab)
    public static let returnKey = KeyCode(rawValue: kVK_Return)
    public static let delete = KeyCode(rawValue: kVK_Delete)
    public static let forwardDelete = KeyCode(rawValue: kVK_ForwardDelete)

    // MARK: Navigation

    public static let escape = KeyCode(rawValue: kVK_Escape)
    public static let help = KeyCode(rawValue: kVK_Help)
    public static let home = KeyCode(rawValue: kVK_Home)
    public static let end = KeyCode(rawValue: kVK_End)
    public static let pageUp = KeyCode(rawValue: kVK_PageUp)
    public static let pageDown = KeyCode(rawValue: kVK_PageDown)
    public static let leftArrow = KeyCode(rawValue: kVK_LeftArrow)
    public static let rightArrow = KeyCode(rawValue: kVK_RightArrow)
    public static let upArrow = KeyCode(rawValue: kVK_UpArrow)
    public static let downArrow = KeyCode(rawValue: kVK_DownArrow)

    // MARK: Function Row

    public static let f1 = KeyCode(rawValue: kVK_F1)
    public static let f2 = KeyCode(rawValue: kVK_F2)
    public static let f3 = KeyCode(rawValue: kVK_F3)
    public static let f4 = KeyCode(rawValue: kVK_F4)
    public static let f5 = KeyCode(rawValue: kVK_F5)
    public static let f6 = KeyCode(rawValue: kVK_F6)
    public static let f7 = KeyCode(rawValue: kVK_F7)
    public static let f8 = KeyCode(rawValue: kVK_F8)
    public static let f9 = KeyCode(rawValue: kVK_F9)
    public static let f10 = KeyCode(rawValue: kVK_F10)
    public static let f11 = KeyCode(rawValue: kVK_F11)
    public static let f12 = KeyCode(rawValue: kVK_F12)
    public static let f13 = KeyCode(rawValue: kVK_F13)
    public static let f14 = KeyCode(rawValue: kVK_F14)
    public static let f15 = KeyCode(rawValue: kVK_F15)
    public static let f16 = KeyCode(rawValue: kVK_F16)
    public static let f17 = KeyCode(rawValue: kVK_F17)
    public static let f18 = KeyCode(rawValue: kVK_F18)
    public static let f19 = KeyCode(rawValue: kVK_F19)
    public static let f20 = KeyCode(rawValue: kVK_F20)

    // MARK: Modifier Keys

    public static let capsLock = KeyCode(rawValue: kVK_CapsLock)
    public static let function = KeyCode(rawValue: kVK_Function)
    public static let control = KeyCode(rawValue: kVK_Control)
    public static let rightControl = KeyCode(rawValue: kVK_RightControl)
    public static let option = KeyCode(rawValue: kVK_Option)
    public static let rightOption = KeyCode(rawValue: kVK_RightOption)
    public static let shift = KeyCode(rawValue: kVK_Shift)
    public static let rightShift = KeyCode(rawValue: kVK_RightShift)
    public static let command = KeyCode(rawValue: kVK_Command)
    public static let rightCommand = KeyCode(rawValue: kVK_RightCommand)

    // MARK: Numeric Keypad

    public static let keypad0 = KeyCode(rawValue: kVK_ANSI_Keypad0)
    public static let keypad1 = KeyCode(rawValue: kVK_ANSI_Keypad1)
    public static let keypad2 = KeyCode(rawValue: kVK_ANSI_Keypad2)
    public static let keypad3 = KeyCode(rawValue: kVK_ANSI_Keypad3)
    public static let keypad4 = KeyCode(rawValue: kVK_ANSI_Keypad4)
    public static let keypad5 = KeyCode(rawValue: kVK_ANSI_Keypad5)
    public static let keypad6 = KeyCode(rawValue: kVK_ANSI_Keypad6)
    public static let keypad7 = KeyCode(rawValue: kVK_ANSI_Keypad7)
    public static let keypad8 = KeyCode(rawValue: kVK_ANSI_Keypad8)
    public static let keypad9 = KeyCode(rawValue: kVK_ANSI_Keypad9)
    public static let keypadDecimal = KeyCode(rawValue: kVK_ANSI_KeypadDecimal)
    public static let keypadPlus = KeyCode(rawValue: kVK_ANSI_KeypadPlus)
    public static let keypadMinus = KeyCode(rawValue: kVK_ANSI_KeypadMinus)
    public static let keypadMultiply = KeyCode(rawValue: kVK_ANSI_KeypadMultiply)
    public static let keypadDivide = KeyCode(rawValue: kVK_ANSI_KeypadDivide)
    public static let keypadEquals = KeyCode(rawValue: kVK_ANSI_KeypadEquals)
    public static let keypadClear = KeyCode(rawValue: kVK_ANSI_KeypadClear)
    public static let keypadEnter = KeyCode(rawValue: kVK_ANSI_KeypadEnter)

    // MARK: Volume Keys

    public static let volumeUp = KeyCode(rawValue: kVK_VolumeUp)
    public static let volumeDown = KeyCode(rawValue: kVK_VolumeDown)
    public static let mute = KeyCode(rawValue: kVK_Mute)
}

// MARK: - Keyboard Layout Lookup

/// What the virtual key types on the active ASCII-capable layout with no modifiers held, or nil if there is none.
/// On the main actor because macOS aborts the process when these input source calls overlap on two threads.
@MainActor
private func layoutText(forVirtualKey virtualKey: UInt16) -> String? {
    guard
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(), let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
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

/// Keys the system prints with a fixed glyph instead of the character they type.
/// Space prints a word, which the app supplies.
private let engravedLabels: [(KeyCode, String)] = [
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

@MainActor
public extension KeyCode {
    /// The text the key types on the current layout. Empty for keys that type nothing, such as the arrow keys.
    var keyEquivalent: String {
        layoutText(forVirtualKey: UInt16(truncatingIfNeeded: rawValue)) ?? ""
    }

    /// A short label for the interface: the key's printed glyph, or else what it types on the current layout.
    ///
    /// The space name is the app's word for the space bar, the one label that needs translating.
    func stringValue(spaceName: String) -> String {
        self == .space ? spaceName : keyLabels[self] ?? keyEquivalent
    }
}
