//
//  LayoutItemListCommands.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI

/// The Layout window list's keys, the bars' set plus Home, End, Page Up and Page Down.
enum LayoutItemListCommand: Equatable {
    case step(Int)
    case page(Int)
    case edge(first: Bool)
    /// ⌥← and ⌥→: one place along the section.
    case nudge(left: Bool)
    /// ⌥↑ and ⌥↓: to the section above or below.
    case adjacentSection(up: Bool)
    /// ⌘1 to ⌘3: to that section, as the item menu lists them.
    case sectionNumber(Int)
    case selectAll
    case undo
    case redo
    /// Return: the row's menu, as a right click shows it.
    case menu
    /// Space: the item's editor, as Space opens the bars' inspector.
    case showEditor
    /// Escape: empties the filter, then closes the window.
    case escape

    /// The command for a key, or nil to let it through. Shift extends a step.
    static func command(for key: KeyEquivalent, characters: String, modifiers: EventModifiers) -> (command: Self, extends: Bool)? {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        let shift = mods.contains(.shift)
        switch mods.subtracting(.shift) {
        case []:
            return plainCommand(for: key, shift: shift).map { ($0, shift) }
        case .option where !shift:
            return optionCommand(for: key).map { ($0, false) }
        case .command:
            return commandCommand(for: key, characters: characters.lowercased(), shift: shift).map { ($0, false) }
        default:
            return nil
        }
    }

    private static func plainCommand(for key: KeyEquivalent, shift: Bool) -> Self? {
        switch key {
        case .downArrow: .step(1)
        case .upArrow: .step(-1)
        case .pageDown: .page(1)
        case .pageUp: .page(-1)
        case .home: .edge(first: true)
        case .end: .edge(first: false)
        case .return where !shift: .menu
        case .space where !shift: .showEditor
        case .escape where !shift: .escape
        default: nil
        }
    }

    private static func optionCommand(for key: KeyEquivalent) -> Self? {
        switch key {
        case .leftArrow: .nudge(left: true)
        case .rightArrow: .nudge(left: false)
        case .upArrow: .adjacentSection(up: true)
        case .downArrow: .adjacentSection(up: false)
        default: nil
        }
    }

    private static func commandCommand(for key: KeyEquivalent, characters: String, shift: Bool) -> Self? {
        switch (characters, shift) {
        case ("a", false): return .selectAll
        case ("z", false): return .undo
        case ("z", true): return .redo
        case ("1", false), ("2", false), ("3", false): return Int(characters).map(sectionNumber)
        default: break
        }
        switch key {
        case .upArrow: return .edge(first: true)
        case .downArrow: return .edge(first: false)
        default: return nil
        }
    }
}

/// Where list moves land, worked out on a section's items left to right as the batch move reads them.
enum LayoutItemListPlacement {
    /// ⌥← or ⌥→ for the moving items: one step past their neighbour, a group counting as one step.
    /// Nil at the end of the section, or when the moving items aren't all in it.
    static func nudge(
        _ moving: [String],
        in entries: [LayoutBatchMoveSnapshot.Entry],
        left: Bool
    ) -> LayoutBatchMove.Placement? {
        let movingSet = Set(moving)
        guard !moving.isEmpty, movingSet.isSubset(of: entries.map(\.id)) else { return nil }
        // Control items have no row, so a step never spends a press on one.
        let remaining = entries.filter { !movingSet.contains($0.id) && !$0.isControlItem }
        let blocks = blocks(of: remaining)
        guard let firstMoving = entries.firstIndex(where: { movingSet.contains($0.id) }) else { return nil }
        // How many blocks sit left of the moving items now.
        let before = blocks.count { block in
            entries.firstIndex { $0.id == block.last } ?? 0 < firstMoving
        }
        let target = left ? before - 1 : before + 1
        guard target >= 0, target <= blocks.count else { return nil }
        let placement: LayoutBatchMove.Placement? = target == 0 ? .start : blocks[target - 1].last.map(LayoutBatchMove.Placement.after)
        // A move that leaves the order as it is would still be undoable, so it isn't made.
        guard let placement, order(entries.map(\.id), moving: moving, to: placement) != entries.map(\.id) else { return nil }
        return placement
    }

    /// The order once moving lands at placement, the moving items keeping their own order.
    static func order(_ ids: [String], moving: [String], to placement: LayoutBatchMove.Placement) -> [String] {
        let movingSet = Set(moving)
        var remaining = ids.filter { !movingSet.contains($0) }
        let ordered = ids.filter(movingSet.contains)
        switch placement {
        case .start:
            remaining.insert(contentsOf: ordered, at: 0)
        case let .after(id):
            let index = remaining.firstIndex(of: id).map { $0 + 1 } ?? remaining.count
            remaining.insert(contentsOf: ordered, at: index)
        case .end:
            remaining.append(contentsOf: ordered)
        }
        return remaining
    }

    /// A drop on a row: the moving items land just left of it. Nil when the row is one of them.
    static func drop(_ moving: Set<String>, before targetID: String, in order: [String]) -> LayoutBatchMove.Placement? {
        guard !moving.contains(targetID) else { return nil }
        let remaining = order.filter { !moving.contains($0) }
        guard let index = remaining.firstIndex(of: targetID) else { return nil }
        return index == 0 ? .start : .after(remaining[index - 1])
    }

    /// Runs of items that share a group, so a step never lands inside one.
    private static func blocks(of entries: [LayoutBatchMoveSnapshot.Entry]) -> [[String]] {
        var blocks = [[String]]()
        var lastGroup: String?
        for entry in entries {
            if let group = entry.groupID, group == lastGroup, !blocks.isEmpty {
                blocks[blocks.count - 1].append(entry.id)
            } else {
                blocks.append([entry.id])
            }
            lastGroup = entry.groupID
        }
        return blocks
    }

    /// The section above or below current, among the sections switched on.
    static func adjacent(to current: MenuBarSectionName, up: Bool, destinations: [MenuBarSectionName?]) -> MenuBarSectionName? {
        let sections = destinations.compactMap(\.self)
        guard let index = sections.firstIndex(of: current) else { return nil }
        let target = up ? index - 1 : index + 1
        return sections.indices.contains(target) ? sections[target] : nil
    }

    /// The section ⌘number names, when it is switched on.
    static func numbered(_ number: Int, destinations: [MenuBarSectionName?]) -> MenuBarSectionName? {
        destinations.indices.contains(number - 1) ? destinations[number - 1] : nil
    }
}
