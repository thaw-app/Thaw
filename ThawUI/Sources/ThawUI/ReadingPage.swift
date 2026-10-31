//
//  ReadingPage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ReadingPathItem

/// One stop on a reading page's path: what it is called and how it is
/// identified when picked.
public struct ReadingPathItem: Identifiable, Equatable {
    public let id: String
    public let label: String
    public init(
        id: String,
        label: String
    ) {
        self.id = id
        self.label = label
    }
}

// MARK: - ReadingPage

/// The scaffold behind long-form windows: a path along the top, a large title, the body in one column,
/// and outbound links, on the settings glass. It also chromes the host window.
public struct ReadingPage<Content: View, Links: View>: View {
    @Environment(\.dismiss) private var dismiss

    public let appName: String
    public let path: [ReadingPathItem]
    @Binding public var selection: String?
    public var visiblePathCount = 5
    public let title: Text
    public var subtitle: Text?
    /// The menu the path's older stops fold into.
    public let olderLabel: LocalizedStringResource
    @ViewBuilder public let content: () -> Content
    @ViewBuilder public let links: () -> Links

    public init(
        appName: String,
        path: [ReadingPathItem],
        selection: Binding<String?>,
        visiblePathCount: Int = 5,
        title: Text,
        subtitle: Text? = nil,
        olderLabel: LocalizedStringResource,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder links: @escaping () -> Links
    ) {
        self.appName = appName
        self.path = path
        _selection = selection
        self.visiblePathCount = visiblePathCount
        self.title = title
        self.subtitle = subtitle
        self.olderLabel = olderLabel
        self.content = content
        self.links = links
    }

    public var body: some View {
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
                        .padding(.top, ThawSpacing.row)
                }

                content()
                    .padding(.top, 44)

                HStack(spacing: ThawSpacing.inset) {
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
        // The text fades under the transparent title bar, as the settings pages do.
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The left and right arrows step along the path, the way it reads.
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: step(by: -1)
            case .right: step(by: 1)
            default: break
            }
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

    /// The stops as a slash-separated path, the app's name at its head. The active stop is in full weight
    /// with a dot beneath; the rest read as links, and past visiblePathCount they fold into a menu.
    private var pathRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.inset) {
            Text(verbatim: appName)
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
                    Text(olderLabel)
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

    private func step(by offset: Int) {
        guard let index = path.firstIndex(where: { $0.id == selection }), path.indices.contains(index + offset) else { return }
        select(path[index + offset].id)
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
public enum ReadingPageType {
    public static let body = ThawType.body
    public static let heading = ThawType.heading
    public static let lineSpacing: CGFloat = 6
    /// Wide because the page is the window.
    public static let columnWidth: CGFloat = 960
    public static let horizontalInset: CGFloat = 56
}

// MARK: - ReadingParagraph

/// One paragraph at reading size.
public struct ReadingParagraph: View {
    public let text: AttributedString

    public init(_ text: AttributedString) {
        self.text = text
    }

    public init(_ text: String) {
        self.text = AttributedString(text)
    }

    public var body: some View {
        Text(text)
            .font(ReadingPageType.body)
            .lineSpacing(ReadingPageType.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
