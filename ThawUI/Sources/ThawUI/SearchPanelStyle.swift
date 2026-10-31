//
//  SearchPanelStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.

import SwiftUI

/// Query field: .title2 text in an interactive glass capsule, inset from the panel's
/// edges, that reads one step more solid while it has focus.
public struct SearchQueryField<Accessory: View>: View {
    public let prompt: String
    @Binding public var text: String
    public let focusToken: Int
    public var isLoading = false
    /// Outlines the field in red: Return found nothing to open.
    public var isRefused = false
    @ViewBuilder public var accessory: Accessory
    @FocusState private var isFocused: Bool
    @Environment(\.searchFieldCorners) private var fieldCorners
    @Environment(\.fieldPieceOutline) private var pieceOutline
    @Environment(\.searchFieldBeam) private var beam

    public init(
        prompt: String,
        text: Binding<String>,
        focusToken: Int,
        isLoading: Bool = false,
        isRefused: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.prompt = prompt
        _text = text
        self.focusToken = focusToken
        self.isLoading = isLoading
        self.isRefused = isRefused
        self.accessory = accessory()
    }

    public var body: some View {
        Group {
            if pieceOutline != nil {
                // The piece of glass around it is the field: no outline inside it, and none for focus, which it always has.
                row
                    .padding(.horizontal, ThawSpacing.inset + 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if let pieceOutline, !isRefused, beam != .off {
                            SearchFieldBeamView(outline: pieceOutline, beam: beam, part: .spill)
                        }
                    }
                    .overlay {
                        if let pieceOutline {
                            if isRefused {
                                pieceOutline.strokeBorder(Color(nsColor: .systemRed), lineWidth: 1.5)
                            } else if beam != .off {
                                SearchFieldBeamView(outline: pieceOutline, beam: beam)
                            }
                        }
                    }
            } else {
                row
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                    // On the glass and under the text: the glass draws itself behind what it is given.
                    .background {
                        if !isRefused, beam != .off {
                            SearchFieldBeamView(outline: fieldCorners.outline, beam: beam, part: .spill)
                        }
                    }
                    .thawGlass(.field(isFocused: isFocused), in: fieldCorners.outline)
                    .overlay {
                        // A refusal's red takes the beam's place, so the one cue is not lost in the other.
                        if isRefused {
                            fieldCorners.outline.strokeBorder(Color(nsColor: .systemRed), lineWidth: 1.5)
                        } else if beam != .off {
                            SearchFieldBeamView(outline: fieldCorners.outline, beam: beam)
                        }
                    }
                    .padding(.horizontal, ThawSpacing.inset)
                    .padding(.top, ThawSpacing.inset)
                    .padding(.bottom, ThawSpacing.row)
            }
        }
        .onAppear {
            // A non-activating panel does not hand first responder to a SwiftUI field synchronously.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isFocused = true
            }
        }
        .onChange(of: focusToken) { isFocused = true }
    }

    private var row: some View {
        HStack(spacing: ThawSpacing.row) {
            // Sized by the field's own text style, so it scales with the query.
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            TextField(text: $text, prompt: Text(prompt)) { Text(prompt) }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title2)
                .autocorrectionDisabled(true)
                .writingToolsBehavior(.disabled)
                .focused($isFocused)
            Spacer(minLength: 0)
            if isLoading {
                ProgressView().controlSize(.small)
            }
            accessory
        }
    }
}

/// The measures every row of the panel shares, whatever its mode.
public enum PanelRow {
    public static let height: CGFloat = 38
    /// The box a row's icon sits in, and the room between it and the title.
    public static let iconBox: CGFloat = 24
    public static let iconSpacing = ThawSpacing.row
    /// Room at either end of the row, inside its highlight.
    public static let inset = ThawSpacing.base
}

/// Palette row: icon, name, and a quieter second line when it says something the name doesn't.
public struct PaletteRow<Icon: View, Trailing: View>: View {
    public let title: String
    public let subtitle: String?
    public let selected: Bool
    /// Character offsets in the title that the query matched; they are drawn in a stronger weight.
    public var matched: [Int] = []
    @ViewBuilder public var icon: Icon
    @ViewBuilder public var trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        selected: Bool,
        matched: [Int] = [],
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.matched = matched
        self.icon = icon()
        self.trailing = trailing()
    }

    private var styledTitle: AttributedString {
        var styled = AttributedString(title)
        for offset in matched where offset < styled.characters.count {
            let start = styled.characters.index(styled.startIndex, offsetBy: offset)
            styled[start ..< styled.characters.index(after: start)].font = ThawType.body.weight(.semibold)
        }
        return styled
    }

    public var body: some View {
        HStack(spacing: PanelRow.iconSpacing) {
            icon.frame(width: PanelRow.iconBox, height: PanelRow.iconBox)
            VStack(alignment: .leading, spacing: 1) {
                Text(styledTitle).font(ThawType.body).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(ThawType.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, PanelRow.inset)
        .frame(minHeight: PanelRow.height)
        .modifier(SearchRowBackground(selected: selected))
    }
}

/// The selection and hover washes from SectionedList rows.
public struct SearchRowBackground: ViewModifier {
    public let selected: Bool
    @State private var isHovering = false
    @Environment(\.searchRowCornerRadius) private var cornerRadius

    public init(
        selected: Bool
    ) {
        self.selected = selected
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    public func body(content: Content) -> some View {
        content
            .frame(minWidth: 22, minHeight: 22)
            .contentShape([.focusEffect, .interaction], shape)
            .background {
                if selected {
                    // The opaque base keeps the panel's glass from refracting behind the selected row.
                    shape
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay { Color.clear.thawGlass(.selection(Color.primary, strength: .selected), in: shape) }
                } else if isHovering {
                    Color.clear.thawGlass(.selection(Color.primary, strength: .hover), in: shape)
                }
            }
            // Under Differentiate Without Color the accent wash alone is not a mark.
            .thawSelectionCue(isSelected: selected)
            .modifier(PointerHover(isHovering: $isHovering))
    }
}

extension EnvironmentValues {
    /// A control's radius, unless the container says what keeps a row's corners concentric with its own.
    @Entry public var searchRowCornerRadius: CGFloat = ThawRadius.control
}

/// A flat key cap: glass per cap on the panel's glass refracts.
public struct KeyCapView: View {
    private let text: String?
    private let systemImage: String?
    private let font: Font?

    public init(text: String, font: Font? = nil) {
        self.text = text
        systemImage = nil
        self.font = font
    }

    public init(systemImage: String) {
        text = nil
        self.systemImage = systemImage
        font = nil
    }

    public var body: some View {
        Group {
            if let text {
                Text(verbatim: text)
                    .font(font)
                    .padding(.horizontal, ThawSpacing.tight)
                    .padding(.vertical, ThawSpacing.hairline)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .bold()
                    .padding(.horizontal, ThawSpacing.compact)
                    .padding(.vertical, ThawSpacing.tight)
            }
        }
        .foregroundStyle(.secondary)
        .background(keyShape.fill(.quaternary))
        .overlay(keyShape.strokeBorder(.separator, lineWidth: 0.5))
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }
}

public struct ShortcutHintButton<Hint: View>: View {
    public let title: String
    public let action: () -> Void
    @ViewBuilder public let hint: () -> Hint

    public init(
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder hint: @escaping () -> Hint
    ) {
        self.title = title
        self.action = action
        self.hint = hint
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .padding(.leading, 5)
                hint()
            }
        }
    }
}

/// Compact, uniformly sized styling shared by every bottom bar button.
public struct SearchPanelButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 22)
            .frame(minWidth: 22)
            .padding(ThawSpacing.capsuleInset)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
