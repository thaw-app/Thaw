//
//  ThawTabStrip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A tab that names itself, for ThawTabStrip(selection:tabs:).
public nonisolated protocol ThawTab: Hashable {
    var title: LocalizedStringResource { get }
    var systemImage: String { get }
}

/// Icon-and-title tabs sharing the strip's width; the full-width counterpart to
/// ThawPillPicker, for Settings pages, where a segmented control is not allowed.
public struct ThawTabStrip<Tab: Hashable>: View {
    public typealias Item = ThawSegment<Tab>

    @Binding private var selection: Tab
    private let items: [Item]

    public init(selection: Binding<Tab>, items: [Item]) {
        _selection = selection
        self.items = items
    }

    /// Tabs that carry their own name and symbol, in the order given.
    public init(selection: Binding<Tab>, tabs: [Tab]) where Tab: ThawTab {
        self.init(selection: selection, items: tabs.map { Item($0, title: $0.title, systemImage: $0.systemImage) })
    }

    public var body: some View {
        ThawCapsuleSegments(selection: $selection, segments: items, sizing: .filling)
    }
}
