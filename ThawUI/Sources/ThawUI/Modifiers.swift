//
//  Modifiers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Carbon.HIToolbox

/// A bit mask containing the modifier keys for a hotkey.
public nonisolated struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

public nonisolated extension Modifiers {
    /// All modifiers in the order displayed by the system, according to Apple's style guide.
    static let canonicalOrder = [control, option, shift, command]

    var symbolicValue: String {
        var result = ""
        if contains(.control) {
            result.append("⌃")
        }
        if contains(.option) {
            result.append("⌥")
        }
        if contains(.shift) {
            result.append("⇧")
        }
        if contains(.command) {
            result.append("⌘")
        }
        return result
    }

    var nsEventFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.control) {
            result.insert(.control)
        }
        if contains(.option) {
            result.insert(.option)
        }
        if contains(.shift) {
            result.insert(.shift)
        }
        if contains(.command) {
            result.insert(.command)
        }
        return result
    }

    var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.control) {
            result.insert(.maskControl)
        }
        if contains(.option) {
            result.insert(.maskAlternate)
        }
        if contains(.shift) {
            result.insert(.maskShift)
        }
        if contains(.command) {
            result.insert(.maskCommand)
        }
        return result
    }

    var carbonFlags: Int {
        var result = 0
        if contains(.control) {
            result |= controlKey
        }
        if contains(.option) {
            result |= optionKey
        }
        if contains(.shift) {
            result |= shiftKey
        }
        if contains(.command) {
            result |= cmdKey
        }
        return result
    }

    init(nsEventFlags: NSEvent.ModifierFlags) {
        self.init()
        if nsEventFlags.contains(.control) {
            insert(.control)
        }
        if nsEventFlags.contains(.option) {
            insert(.option)
        }
        if nsEventFlags.contains(.shift) {
            insert(.shift)
        }
        if nsEventFlags.contains(.command) {
            insert(.command)
        }
    }

    init(cgEventFlags: CGEventFlags) {
        self.init()
        if cgEventFlags.contains(.maskControl) {
            insert(.control)
        }
        if cgEventFlags.contains(.maskAlternate) {
            insert(.option)
        }
        if cgEventFlags.contains(.maskShift) {
            insert(.shift)
        }
        if cgEventFlags.contains(.maskCommand) {
            insert(.command)
        }
    }

    init(carbonFlags: Int) {
        self.init()
        if carbonFlags & controlKey == controlKey {
            insert(.control)
        }
        if carbonFlags & optionKey == optionKey {
            insert(.option)
        }
        if carbonFlags & shiftKey == shiftKey {
            insert(.shift)
        }
        if carbonFlags & cmdKey == cmdKey {
            insert(.command)
        }
    }
}
