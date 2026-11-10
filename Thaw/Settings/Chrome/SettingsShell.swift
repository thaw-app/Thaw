//
//  SettingsShell.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - SettingsShellMetrics

private enum SettingsShellMetrics {
    static let sidebarWidth: CGFloat = 220
    static let headerHeight: CGFloat = 52
    static let sidebarTopInset: CGFloat = 40
    static let simpleModeTrafficLightInset: CGFloat = 76
    static let searchFieldWidth: CGFloat = 210
    static let searchFieldHeight: CGFloat = 28
}

// MARK: - SettingsSplitShell

/// Lightweight split chrome replacing `NavigationSplitView` + `NSToolbar` + `.searchable`, eliminating
/// retained Liquid Glass toolbar/search/edge-blur backing surfaces after Settings closes.
struct SettingsSplitShell<Sidebar: View, Detail: View, LeadingHeader: View, TrailingHeader: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let sidebar: Sidebar
    private let detail: Detail
    private let leadingHeader: LeadingHeader
    private let trailingHeader: TrailingHeader

    init(
        title: Text,
        subtitle: Text? = nil,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder leadingHeader: () -> LeadingHeader,
        @ViewBuilder trailingHeader: () -> TrailingHeader
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sidebar = sidebar()
        self.detail = detail()
        self.leadingHeader = leadingHeader()
        self.trailingHeader = trailingHeader()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                WindowDragArea()
                    .frame(height: SettingsShellMetrics.sidebarTopInset)
                sidebar
            }
            .frame(width: SettingsShellMetrics.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background {
                SettingsPaneBackdrop(material: .sidebar)
            }

            Divider()

            VStack(spacing: 0) {
                detailHeaderBar
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var detailHeaderBar: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: ThawSpacing.inset) {
                leadingHeader
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(ThawType.heading)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        subtitle
                            .font(ThawType.sublabel)
                            .foregroundStyle(ThawInk.supporting)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: ThawSpacing.base)
                trailingHeader
            }
            .padding(.horizontal, ThawSpacing.gutter)
        }
        .frame(height: SettingsShellMetrics.headerHeight)
    }
}

// MARK: - SettingsSingleHeaderShell

/// Lightweight single-column header chrome for Simple Mode without attaching an `NSToolbar`.
struct SettingsSingleHeaderShell<TrailingHeader: View, Content: View>: View {
    private let title: Text
    private let trailingHeader: TrailingHeader
    private let content: Content

    init(
        title: Text,
        @ViewBuilder trailingHeader: () -> TrailingHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailingHeader = trailingHeader()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                WindowDragArea()
                HStack(spacing: ThawSpacing.inset) {
                    title
                        .font(ThawType.heading)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.leading, SettingsShellMetrics.simpleModeTrafficLightInset)
                    Spacer(minLength: ThawSpacing.base)
                    trailingHeader
                }
                .padding(.trailing, ThawSpacing.gutter)
            }
            .frame(height: SettingsShellMetrics.headerHeight)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - SettingsHeaderSearchField

/// Compact header search pill supporting `⌘F`, clear, and `Escape` without `NSSearchToolbarItem`.
struct SettingsHeaderSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringResource
    let findLabel: LocalizedStringResource

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            Image(systemName: "magnifyingglass")
                .font(ThawType.sublabel)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(ThawType.body)
                .labelsHidden()
                .focused($isFocused)
                .onExitCommand {
                    if !text.isEmpty {
                        text = ""
                    } else {
                        isFocused = false
                    }
                }
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(ThawType.sublabel)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, ThawSpacing.row)
        .frame(width: SettingsShellMetrics.searchFieldWidth, height: SettingsShellMetrics.searchFieldHeight)
        .background(.quinary, in: Self.shape)
        .overlay {
            Self.shape.strokeBorder(
                isFocused ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: isFocused ? 1 : 0.5
            )
        }
        .contentShape(Self.shape)
        .onTapGesture {
            isFocused = true
        }
        .background {
            Button(findLabel) {
                isFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
    }

    private static let shape = Capsule(style: .continuous)
}

// MARK: - WindowDragArea

/// Transparent AppKit region behind header chrome that lets users drag or double-click-zoom the borderless-titlebar window.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_: WindowDragNSView, context _: Context) {}
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
            if action == "Minimize" {
                window?.performMiniaturize(nil)
            } else if action != "None" {
                window?.performZoom(nil)
            }
            return
        }
        window?.performDrag(with: event)
    }
}
