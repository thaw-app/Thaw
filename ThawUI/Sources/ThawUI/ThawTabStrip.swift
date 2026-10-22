//
//  ThawTabStrip.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A tab that names itself, for ThawTabStrip(selection:tabs:).
public nonisolated protocol ThawTab: Hashable {
    var title: LocalizedStringKey { get }
    var systemImage: String { get }
}

/// Tabs, each an icon and its name, in one glass capsule like Xcode's navigator bar,
/// switching what a page shows below it. Settings pages use it where a segmented
/// control is not allowed. The tabs share the strip's width evenly, so it fills the
/// page it heads instead of sitting as a small pill in a wide card.
public struct ThawTabStrip<Tab: Hashable>: View {
    public struct Item {
        let tab: Tab
        let title: LocalizedStringKey
        let systemImage: String

        public init(_ tab: Tab, title: LocalizedStringKey, systemImage: String) {
            self.tab = tab
            self.title = title
            self.systemImage = systemImage
        }
    }

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
        ThawCapsuleSegments(
            selection: $selection,
            segments: items.map { item in
                .init(value: item.tab, title: item.title, systemImage: item.systemImage, help: nil)
            },
            sizing: .filling
        )
    }
}
