//
//  SettingsControlStyleGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing

/// Keeps every button and picker on a Settings page in one visual style.
///
/// A button with no style is drawn by macOS, bordered in one row and a flat
/// pill in the next, and a picker outside a Form turns into a bordered popup.
/// Neither shows up in review, so the rule is asserted over the source.
@Suite("Settings control style guard")
struct SettingsControlStyleGuardTests {
    private static let scannedDirectory = "Thaw/Settings/SettingsPanes"

    /// Containers whose buttons the system draws: menus, dialogs, toolbars,
    /// and the hidden shortcut buttons parked in a background.
    private static let systemDrawnContainers: Set<String> = [
        "Menu", "ThawMenu", "MoreActionsMenu", "contextMenu", "ControlGroup",
        "alert", "confirmationDialog", "toolbar", "ToolbarItem", "ToolbarItemGroup",
        "background", "Picker", "commands", "CommandGroup",
    ]

    /// Styles that set a Settings page apart from the rest.
    private static let foreignStyles = [
        ".buttonStyle(.bordered)",
        ".buttonStyle(.borderedProminent)",
        ".pickerStyle(.segmented)",
    ]

    @Test("every in-page button sets a style")
    func buttonsAreStyled() throws {
        let violations = try Self.sources().flatMap { path, lines in
            SwiftScopeScanner(lines: lines).controls(named: "Button").compactMap { control -> String? in
                guard !control.ancestors.contains(where: Self.isSystemDrawn),
                      !control.hasModifier(".hidden()"),
                      !control.hasModifier(".buttonStyle(")
                else { return nil }
                return "\(path):\(control.line)"
            }
        }
        #expect(
            violations.isEmpty,
            "Buttons with no style, drawn by macOS instead of as the other Settings buttons: \(violations.joined(separator: ", ")). Add .buttonStyle(.settingsGlass), or .plain for an icon."
        )
    }

    @Test("every bare picker sets a style")
    func pickersAreStyled() throws {
        let violations = try Self.sources().flatMap { path, lines in
            SwiftScopeScanner(lines: lines).controls(named: "Picker").compactMap { control -> String? in
                guard !control.ancestors.contains(where: Self.isSystemDrawn),
                      !control.hasModifier(".pickerStyle(")
                else { return nil }
                return "\(path):\(control.line)"
            }
        }
        #expect(
            violations.isEmpty,
            "Pickers with no style: \(violations.joined(separator: ", ")). Use ThawPicker, which draws a menu picker the way the other panes do."
        )
    }

    @Test("no page uses a style the others do not")
    func noForeignStyles() throws {
        var violations = [String]()
        for (path, lines) in try Self.sources() {
            for (index, line) in lines.enumerated() where Self.foreignStyles.contains(where: line.contains) {
                violations.append("\(path):\(index + 1)")
            }
        }
        #expect(violations.isEmpty, "Bordered or segmented controls: \(violations.joined(separator: ", ")).")
    }

    @Test("the scan sees the Settings panes")
    func scanIsNotEmpty() throws {
        // A moved directory would otherwise scan nothing and pass.
        let buttons = try Self.sources().reduce(0) { count, source in
            count + SwiftScopeScanner(lines: source.lines).controls(named: "Button").count
        }
        #expect(buttons > 50)
    }

    private static func isSystemDrawn(_ ancestor: String) -> Bool {
        if systemDrawnContainers.contains(ancestor) {
            return true
        }
        // Builders whose buttons are handed to a menu or a dialog, like
        // profileActions(for:) and globalConfirmationButtons(for:).
        guard ancestor.hasPrefix("func ") else { return false }
        return ancestor.hasSuffix("Actions") || ancestor.contains("Menu") || ancestor.contains("Confirmation")
    }

    private static func sources() throws -> [(path: String, lines: [String])] {
        let root = try #require(repositoryRoot(), "repository root not found from \(#filePath)")
        let directory = root.appending(path: scannedDirectory)
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var result = [(path: String, lines: [String])]()
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let path = url.path().replacingOccurrences(of: root.path(), with: "")
            result.append((path, text.components(separatedBy: "\n")))
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Walks up from this file: <root>/ThawUI/Tests/ThawUITests/<self>.
    private static func repositoryRoot() -> URL? {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent() // ThawUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ThawUI
            .deletingLastPathComponent() // <root>
        let marker = root.appending(path: scannedDirectory)
        return FileManager.default.fileExists(atPath: marker.path()) ? root : nil
    }
}

/// A line scanner that knows which call or closure each control sits in and
/// which modifiers follow it, enough to answer "is this button styled" without
/// a Swift parser. Strings and comments are blanked before brackets are counted.
struct SwiftScopeScanner {
    struct Control {
        let line: Int
        /// Enclosing calls and closures, innermost last.
        let ancestors: [String]
        /// Modifier lines chained on the control and on each enclosing call.
        let modifiers: [String]

        func hasModifier(_ prefix: String) -> Bool {
            modifiers.contains { $0.hasPrefix(prefix) }
        }
    }

    private struct Frame {
        let name: String
        let isBrace: Bool
        let line: Int
        let indent: Int
    }

    private let code: [String]
    private let indents: [Int]

    init(lines: [String]) {
        code = Self.blanked(lines)
        indents = lines.map { $0.prefix { $0 == " " }.count }
    }

    func controls(named name: String) -> [Control] {
        var stack = [Frame]()
        var closeLine = [Int: Int]() // opening line of a brace frame -> its closing line
        var found = [(line: Int, ancestors: [Frame])]()
        var lastClosedParen = ""

        for (index, line) in code.enumerated() {
            let characters = Array(line)
            var position = 0
            while position < characters.count {
                let character = characters[position]
                let before = String(characters[..<position])
                switch character {
                case "(":
                    let callee = Self.trailingIdentifier(before)
                    if callee == name, Self.isCallStart(before, name: name) {
                        found.append((index, stack))
                    }
                    stack.append(Frame(name: callee, isBrace: false, line: index, indent: indents[index]))
                case ")":
                    if let frame = stack.popLast() {
                        lastClosedParen = frame.name
                    }
                case "{":
                    let frameName = Self.braceName(before, lastClosedParen: lastClosedParen)
                    // Button("x") { was counted at its parenthesis; only Button { starts here.
                    let opensCall = !before.trimmingCharacters(in: .whitespaces).hasSuffix(")")
                    if frameName == name, opensCall, Self.isCallStart(before, name: name) {
                        found.append((index, stack))
                    }
                    stack.append(Frame(name: frameName, isBrace: true, line: index, indent: indents[index]))
                case "}":
                    if let frame = stack.popLast(), frame.isBrace {
                        closeLine[frame.line] = index
                    }
                default:
                    break
                }
                position += 1
            }
        }

        return found.map { occurrence in
            var modifiers = chain(after: lastLine(ofControlAt: occurrence.line), indent: indents[occurrence.line])
            for frame in occurrence.ancestors where frame.isBrace {
                if let end = closeLine[frame.line] {
                    modifiers += chain(after: end, indent: indents[end])
                }
            }
            return Control(
                line: occurrence.line + 1,
                ancestors: occurrence.ancestors.map(\.name).filter { !$0.isEmpty },
                modifiers: modifiers
            )
        }
    }

    /// The last line of a control's own expression: the line that brings the
    /// bracket depth back to where the control started, past any trailing
    /// label: closure.
    private func lastLine(ofControlAt start: Int) -> Int {
        var depth = 0
        var index = start
        while index < code.count {
            for character in code[index] {
                if character == "(" || character == "{" {
                    depth += 1
                }
                if character == ")" || character == "}" {
                    depth -= 1
                }
            }
            let next = index + 1 < code.count ? code[index + 1].trimmingCharacters(in: .whitespaces) : ""
            if depth <= 0, !next.hasPrefix("} label:"), !next.hasPrefix("label:") {
                return index
            }
            index += 1
        }
        return start
    }

    /// Modifier lines directly after end. The chain's indentation is the
    /// first modifier's: level with a multi-line expression's closing brace,
    /// one step in under a single-line one.
    private func chain(after end: Int, indent: Int) -> [String] {
        var modifiers = [String]()
        var chainIndent: Int?
        var index = end + 1
        while index < code.count {
            let trimmed = code[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("."), indents[index] >= indent else { break }
            if chainIndent == nil {
                chainIndent = indents[index]
            }
            if indents[index] == chainIndent {
                modifiers.append(trimmed)
            }
            index += 1
        }
        return modifiers
    }

    private static func isCallStart(_ before: String, name: String) -> Bool {
        // Button( or Button {, not .Button, ThawButton or SettingsButton.
        guard let range = before.range(of: name, options: .backwards) else { return false }
        let preceding = before[..<range.lowerBound].last
        return preceding.map { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" } ?? true
    }

    private static func trailingIdentifier(_ text: String) -> String {
        let trimmed = text.reversed().drop { $0 == " " }
        return String(trimmed.prefix { $0.isLetter || $0.isNumber || $0 == "_" }.reversed())
    }

    private static func braceName(_ before: String, lastClosedParen: String) -> String {
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if let funcRange = trimmed.range(of: "func ") {
            let rest = trimmed[funcRange.upperBound...]
            return "func " + String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        }
        if trimmed.hasSuffix(")") {
            return lastClosedParen
        }
        if trimmed.hasSuffix(":") {
            return trailingIdentifier(String(trimmed.dropLast()))
        }
        return trailingIdentifier(trimmed)
    }

    /// Replaces string literals and comments with spaces, keeping columns.
    private static func blanked(_ lines: [String]) -> [String] {
        var inTripleString = false
        var inBlockComment = false
        return lines.map { line in
            var output = [Character]()
            let characters = Array(line)
            var index = 0
            var inString = false
            while index < characters.count {
                let rest = String(characters[index...])
                if inBlockComment {
                    if rest.hasPrefix("*/") {
                        inBlockComment = false; output += "  "; index += 2; continue
                    }
                    output.append(" "); index += 1; continue
                }
                if inTripleString {
                    if rest.hasPrefix("\"\"\"") {
                        inTripleString = false; output += "   "; index += 3; continue
                    }
                    output.append(" "); index += 1; continue
                }
                if inString {
                    if characters[index] == "\\" {
                        output += "  "; index += 2; continue
                    }
                    if characters[index] == "\"" {
                        inString = false
                    }
                    output.append(" "); index += 1; continue
                }
                if rest.hasPrefix("//") {
                    break
                }
                if rest.hasPrefix("/*") {
                    inBlockComment = true; output += "  "; index += 2; continue
                }
                if rest.hasPrefix("\"\"\"") {
                    inTripleString = true; output += "   "; index += 3; continue
                }
                if characters[index] == "\"" {
                    inString = true; output.append(" "); index += 1; continue
                }
                output.append(characters[index])
                index += 1
            }
            return String(output)
        }
    }
}
