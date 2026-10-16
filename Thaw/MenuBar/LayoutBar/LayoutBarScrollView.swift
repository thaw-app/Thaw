//
//  LayoutBarScrollView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

final class LayoutBarScrollView: NSScrollView {
    private let paddingView: LayoutBarPaddingView

    var arrangedViews: [LayoutBarArrangedView] {
        get { paddingView.arrangedViews }
        set { paddingView.arrangedViews = newValue }
    }

    init(appState: AppState, section: MenuBarSection.Name) {
        self.paddingView = LayoutBarPaddingView(appState: appState, section: section)

        super.init(frame: .zero)

        self.documentView = paddingView
        self.hasHorizontalScroller = true
        self.hasVerticalScroller = false
        self.verticalScrollElasticity = .none
        self.autohidesScrollers = true
        self.drawsBackground = false
        self.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paddingView.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            paddingView.widthAnchor.constraint(greaterThanOrEqualTo: contentView.widthAnchor),
            paddingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension LayoutBarScrollView {
    override func accessibilityChildren() -> [Any]? {
        return arrangedViews
    }
}
