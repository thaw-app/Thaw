//
//  Array+Neighbor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension Array where Element: Equatable {
    /// The element offset places away from element, as the arrow keys step
    /// through a list: nil when element isn't here or the step would leave
    /// the list.
    func neighbor(of element: Element, by offset: Int) -> Element? {
        guard let index = firstIndex(of: element), indices.contains(index + offset) else { return nil }
        return self[index + offset]
    }

    /// The element above or below element in a vertical list, for the up
    /// and down arrow keys: nil for left or right, when element isn't here,
    /// or when the step would leave the list.
    func neighbor(of element: Element, moving direction: MoveCommandDirection) -> Element? {
        let offset = switch direction {
        case .up: -1
        case .down: 1
        default: 0
        }
        guard offset != 0 else { return nil }
        return neighbor(of: element, by: offset)
    }
}
