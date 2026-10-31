//
//  AnnotationView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A view that displays content as an annotation below a parent view.
public struct AnnotationView<Parent: View, Content: View, ForegroundStyle: ShapeStyle>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let font: Font?
    private let foregroundStyle: ForegroundStyle
    private let parent: Parent
    private let content: Content

    /// Creates an annotation view. The font and foreground style apply to the content view's environment.
    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = ThawInk.supporting,
        @ViewBuilder parent: () -> Parent,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.font = font
        self.foregroundStyle = foregroundStyle
        self.parent = parent()
        self.content = content()
    }

    public init(
        _ titleKey: LocalizedStringResource,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = ThawInk.supporting,
        @ViewBuilder parent: () -> Parent
    ) where Content == Text {
        self.init(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            parent()
        } content: {
            Text(titleKey)
        }
    }

    /// Creates a standalone annotation, with no parent view above it.
    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = ThawInk.supporting,
        @ViewBuilder content: () -> Content
    ) where Parent == EmptyView {
        self.init(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            EmptyView()
        } content: {
            content()
        }
    }

    /// Creates a standalone annotation showing the text for titleKey.
    public init(
        _ titleKey: LocalizedStringResource,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = ThawInk.supporting
    ) where Parent == EmptyView, Content == Text {
        self.init(
            titleKey,
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            EmptyView()
        }
    }

    @Environment(\.settingsDescriptionsVisible) private var descriptionsVisible

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            parent
            if descriptionsVisible {
                content
                    .font(font)
                    .foregroundStyle(foregroundStyle)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One line of annotation with the rest behind an info.circle popover, collapsed until someone asks.
/// The summary has to fit one line at the settings window's default width.
private struct DeferredAnnotation<Parent: View, ForegroundStyle: ShapeStyle>: View {
    let summary: LocalizedStringResource
    let more: LocalizedStringResource
    let moreLabel: LocalizedStringResource
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let font: Font?
    let foregroundStyle: ForegroundStyle
    let parent: Parent

    @Environment(\.settingsDescriptionsVisible) private var descriptionsVisible
    @State private var isShowingMore = false

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            parent
            if descriptionsVisible {
                HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.tight) {
                    Text(summary)
                    moreButton
                }
                .font(font)
                .foregroundStyle(foregroundStyle)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Sized to the annotation's own font, so the glyph doesn't outweigh the grey line.
    private var moreButton: some View {
        Button {
            isShowingMore = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .help(Text(moreLabel))
        .accessibilityLabel(Text(moreLabel))
        .popover(isPresented: $isShowingMore, arrowEdge: .bottom) {
            Text(more)
                .font(ThawType.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .padding(ThawSpacing.gutter)
        }
    }
}

extension View {
    /// Adds the given view as an annotation below this view.
    /// The font and foreground style apply to the annotation content's environment.
    public func annotation(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: some ShapeStyle = ThawInk.supporting,
        @ViewBuilder content: () -> some View
    ) -> some View {
        AnnotationView(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            self
        } content: {
            content()
        }
    }

    /// Adds the given text as an annotation below this view.
    /// The font and foreground style apply to the annotation content's environment.
    public func annotation(
        _ titleKey: LocalizedStringResource,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: some ShapeStyle = ThawInk.supporting
    ) -> some View {
        AnnotationView(
            titleKey,
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            self
        }
    }

    /// Adds a one-line annotation below this view, with the rest behind an info button beside it.
    /// Use it when the copy wraps past one line at the settings window's default width.
    ///
    /// The more text opens in a popover on request; the more label is the info button's help and VoiceOver name.
    public func annotation(
        _ titleKey: LocalizedStringResource,
        more: LocalizedStringResource,
        moreLabel: LocalizedStringResource,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: some ShapeStyle = ThawInk.supporting
    ) -> some View {
        DeferredAnnotation(
            summary: titleKey,
            more: more,
            moreLabel: moreLabel,
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle,
            parent: self
        )
    }
}

extension CGFloat {
    /// The default spacing for annotated form rows.
    public static let annotationDefaultSpacing: CGFloat = 2
}
