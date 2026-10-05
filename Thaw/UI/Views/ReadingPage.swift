//
//  ReadingPage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - ReadingPathItem

/// One stop on a reading page's path: what it is called and how it is
/// identified when picked.
struct ReadingPathItem: Identifiable, Equatable {
    let id: String
    let label: String
}

// MARK: - ReadingPage

/// The scaffold behind the app's long-form windows: a path along the top, a
/// large title, the body in one column, and outbound links, on the settings
/// glass. It also chromes the host window.
struct ReadingPage<Content: View, Links: View>: View {
    @Environment(\.dismiss) private var dismiss

    let path: [ReadingPathItem]
    @Binding var selection: String?
    var visiblePathCount = 5
    let title: Text
    var subtitle: Text?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let links: () -> Links

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pathRow
                    // Clears the transparent title bar; the path is the
                    // first thing under the traffic lights.
                    .padding(.top, 48)
                    .padding(.bottom, 72)

                title
                    .font(ThawType.hero)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    subtitle
                        .font(ThawType.label)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                }

                content()
                    .padding(.top, 44)

                HStack(spacing: 12) {
                    links()
                }
                .buttonStyle(.plain)
                .font(ThawType.label)
                .foregroundStyle(.secondary)
                .padding(.top, 64)
            }
            .textSelection(.enabled)
            .frame(maxWidth: ReadingPageType.columnWidth, alignment: .leading)
            .padding(.horizontal, ReadingPageType.horizontalInset)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            // The same HUD material and wash as the settings detail column.
            BehindWindowMaterialBackground(material: .hudWindow)
                .overlay {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.3))
                }
                .ignoresSafeArea()
        }
        .frame(minWidth: 640, idealWidth: 860, maxWidth: .infinity, minHeight: 520, idealHeight: 780, maxHeight: .infinity)
        .onWindowChange { window in
            Self.configureChrome(window)
        }
        .onExitCommand {
            dismiss()
        }
    }

    // MARK: Path

    /// The stops as a slash-separated path, the app's name at its head. The
    /// active stop is printed in full weight with a dot beneath it; the rest
    /// read as links. Past visiblePathCount the remainder fold into a menu.
    private var pathRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: Constants.displayName)
                .foregroundStyle(ThawInk.supporting)
            Text(verbatim: ":")
                .foregroundStyle(.secondary)

            ForEach(Array(path.prefix(visiblePathCount).enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Text(verbatim: "/")
                        .foregroundStyle(.secondary)
                }
                pathLink(item)
            }

            if path.count > visiblePathCount {
                Text(verbatim: "/")
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(path.dropFirst(visiblePathCount)) { item in
                        Button(item.label) {
                            select(item.id)
                        }
                    }
                } label: {
                    Text("Older")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .font(ThawType.label)
    }

    private func pathLink(_ item: ReadingPathItem) -> some View {
        let isActive = item.id == selection
        return Button {
            select(item.id)
        } label: {
            VStack(spacing: 5) {
                Text(verbatim: item.label)
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .fontWeight(isActive ? .semibold : .medium)
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .opacity(isActive ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func select(_ id: String) {
        withThawAnimation(ThawMotion.quick) {
            selection = id
        }
    }

    // MARK: Chrome

    /// The page draws its glass under the title bar and hides the title: the
    /// path along the top is the window's heading.
    private static func configureChrome(_ window: NSWindow?) {
        guard let window else {
            return
        }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

// MARK: - ReadingPageType

/// Reading pages share the settings text styles; spacing separates long-form sections.
enum ReadingPageType {
    static let body = ThawType.body
    static let heading = ThawType.heading
    static let lineSpacing: CGFloat = 6
    /// Wide on purpose: the page is the window, not a column inside it.
    static let columnWidth: CGFloat = 960
    static let horizontalInset: CGFloat = 56
}

// MARK: - ReadingParagraph

/// One paragraph at reading size.
struct ReadingParagraph: View {
    let text: AttributedString

    init(_ text: AttributedString) {
        self.text = text
    }

    init(_ text: String) {
        self.text = AttributedString(text)
    }

    var body: some View {
        Text(text)
            .font(ReadingPageType.body)
            .lineSpacing(ReadingPageType.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
