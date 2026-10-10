//
//  AnnotationView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// A view that displays content as an annotation below a parent view.
struct AnnotationView<Parent: View, Content: View, ForegroundStyle: ShapeStyle>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let font: Font?
    private let foregroundStyle: ForegroundStyle
    private let parent: Parent
    private let content: Content

    /// Creates an annotation view with a parent and content view.
    ///
    /// - Parameters:
    ///   - alignment: The alignment of the content view in relation to the parent view.
    ///   - spacing: The spacing between the parent and content view.
    ///   - font: The font to apply to the content view's environment.
    ///   - foregroundStyle: The foreground style to apply to the content view's environment.
    ///   - parent: The parent view of the annotation.
    ///   - content: The content view of the annotation.
    init(
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

    /// Creates an annotation view whose content is the text for titleKey.
    init(
        _ titleKey: LocalizedStringKey,
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
    init(
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
    init(
        _ titleKey: LocalizedStringKey,
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

    var body: some View {
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

/// An annotation that shows one line and keeps the rest behind an info button.
///
/// A paragraph under a control turns a row into body copy, and a few of them
/// make a pane read as prose with switches in it. Cutting the text is the
/// wrong fix, since for several controls it is the only explanation. So one
/// line always shows and the rest moves behind the same info.circle popover
/// PlatformLimitationsNotice uses, collapsed until someone asks.
///
/// The summary has to fit one line at the settings window's default width. If
/// it does not, it is not a summary and the split is in the wrong place.
private struct DeferredAnnotation<Parent: View, ForegroundStyle: ShapeStyle>: View {
    let summary: LocalizedStringKey
    let more: LocalizedStringKey
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

    /// Sized to the annotation's own font rather than the body size, so the
    /// glyph sits on the grey line instead of outweighing it.
    private var moreButton: some View {
        Button {
            isShowingMore = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .help("More about this setting")
        .accessibilityLabel("More about this setting")
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

extension EnvironmentValues {
    /// Whether explanatory captions below settings rows are shown.
    ///
    /// Defaults to true so surfaces outside the settings window (such as
    /// the standalone appearance editor) keep their captions regardless of
    /// the "Show setting descriptions" preference.
    @Entry var settingsDescriptionsVisible: Bool = true
}

extension View {
    /// Adds the given view as an annotation below this view.
    ///
    /// - Parameters:
    ///   - alignment: The guide for aligning the annotation content horizontally with this view.
    ///   - spacing: The vertical spacing between this view and the annotation content.
    ///   - font: The font to apply to the annotation content's environment.
    ///   - foregroundStyle: The foreground style to apply to the annotation content's environment.
    ///   - content: A view builder that creates the annotation content.
    func annotation(
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
    ///
    /// - Parameters:
    ///   - titleKey: The string key to display as text below this view.
    ///   - alignment: The guide for aligning the annotation content horizontally with this view.
    ///   - spacing: The vertical spacing between this view and the annotation content.
    ///   - font: The font to apply to the annotation content's environment.
    ///   - foregroundStyle: The foreground style to apply to the annotation content's environment.
    func annotation(
        _ titleKey: LocalizedStringKey,
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

    /// Adds a one-line annotation below this view and defers the rest of the
    /// explanation to an info button beside it.
    ///
    /// Reach for this instead of annotation(_:alignment:spacing:font:foregroundStyle:)
    /// whenever the copy wraps past a single line at the settings window's
    /// default width. See DeferredAnnotation for why.
    ///
    /// - Parameters:
    ///   - titleKey: The one line that always shows below this view.
    ///   - more: The rest of the explanation, shown in a popover on request.
    ///   - alignment: The guide for aligning the annotation horizontally with this view.
    ///   - spacing: The vertical spacing between this view and the annotation.
    ///   - font: The font to apply to the annotation's environment.
    ///   - foregroundStyle: The foreground style to apply to the annotation's environment.
    func annotation(
        _ titleKey: LocalizedStringKey,
        more: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: some ShapeStyle = ThawInk.supporting
    ) -> some View {
        DeferredAnnotation(
            summary: titleKey,
            more: more,
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
    static let annotationDefaultSpacing: CGFloat = 2
}
