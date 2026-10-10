//
//  LayoutBarScrollView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

final class LayoutBarScrollView: NSScrollView {
    private let paddingView: LayoutBarPaddingView

    /// Laid out left to right in array order.
    var arrangedViews: [LayoutBarArrangedView] {
        get { paddingView.arrangedViews }
        set { paddingView.arrangedViews = newValue }
    }

    /// Creates a layout bar scroll view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
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
