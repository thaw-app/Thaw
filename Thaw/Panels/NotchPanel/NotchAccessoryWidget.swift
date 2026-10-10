//
//  NotchAccessoryWidget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// The long form of whatever a menu bar item is already saying, read from the
/// item's own accessibility strings.
///
/// Many status items show a short form and put the full sentence in
/// AXDescription or AXHelp (a weather extra showing a temperature often adds
/// the sky condition), so an item Thaw has no integration with can still get
/// a useful descender.
///
/// A readout that only repeats the item's name (say "Philips Hue") is thrown
/// away by NotchReadoutResolver and the widget reports itself unavailable.
/// This is best effort: items that expose nothing worth reading get no
/// descender, and nothing is invented or borrowed from another item.
@MainActor
@Observable
final class NotchAccessoryWidget: NotchWidget {
    let id = "accessory"
    let refreshPolicy: NotchWidgetRefreshPolicy = .onDemand

    private static let detailFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let sourceFont = NSFont.systemFont(ofSize: 12, weight: .regular)

    private static let bodyHeight: CGFloat = 34
    private static let horizontalPadding: CGFloat = 16
    private static let interitemSpacing: CGFloat = 7
    private static let symbolWidth: CGFloat = 17
    private static let widthLimits: ClosedRange<CGFloat> = 96 ... 380

    private(set) var detail: String?
    /// A second reading from the same item, when it published one that is not
    /// a restatement of the first. Never the app's name.
    private(set) var secondary: String?
    private(set) var symbolName: String?

    /// Sized to its text rather than to a fixed card, so a two-word readout
    /// stays a short tab instead of padding itself out to a panel.
    var bodySize: CGSize {
        var width = Self.horizontalPadding * 2
        width += Self.measure(detail ?? "", in: Self.detailFont)
        if symbolName != nil {
            width += Self.interitemSpacing + Self.symbolWidth
        }
        if let secondary {
            width += Self.interitemSpacing + Self.measure(secondary, in: Self.sourceFont)
        }
        return CGSize(
            width: width.clamped(to: Self.widthLimits),
            height: Self.bodyHeight
        )
    }

    /// Matches anything: whether there is something to show is decided in
    /// isAvailable, once the item's accessibility strings have been read.
    func matches(_ item: MenuBarItem) -> Bool {
        guard case let .string(bundleID) = item.tag.namespace else {
            return false
        }
        return !ThawMenuBarIdentity.owns(bundleIdentifier: bundleID)
    }

    /// Reads the item's accessibility strings once per hover.
    ///
    /// Five attributes are collected because status items are inconsistent
    /// about which one carries the state: AXDescription and AXHelp are
    /// preferred, AXValueDescription is where level-style items put the number
    /// their glyph only implies, and AXTitle comes last because it is usually
    /// the same short text already visible in the bar.
    ///
    /// The read is a synchronous round trip to the owning app, which AXHelpers
    /// bounds with a messaging timeout; it happens after the hover debounce,
    /// once, and not while the descender is showing.
    func prepare(for item: MenuBarItem) {
        detail = nil
        secondary = nil
        symbolName = nil

        let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        guard bounds.width > 0, let element = AXHelpers.element(at: CGPoint(x: bounds.midX, y: bounds.midY)) else {
            return
        }

        let readout = NotchReadoutResolver.resolve(
            candidates: [
                AXHelpers.description(for: element),
                AXHelpers.help(for: element),
                AXHelpers.valueDescription(for: element),
                AXHelpers.stringValue(for: element),
                AXHelpers.title(for: element),
            ],
            names: Self.names(of: item)
        )
        detail = readout?.primary
        secondary = readout?.secondary
        symbolName = detail.flatMap(Self.symbol(for:))
    }

    /// Every name this item is known by, so the resolver can recognize a
    /// candidate that only repeats one of them. The bundle identifier's last
    /// component is included because it is often the app name in lowercase
    /// with the spaces removed, which no other name here would match.
    private static func names(of item: MenuBarItem) -> [String?] {
        var names = [
            item.autoDetectedName,
            item.tag.title,
            item.owningApplication?.localizedName,
        ]
        if case let .string(bundleID) = item.tag.namespace {
            names.append(contentsOf: bundleID.split(separator: ".").map(String.init))
        }
        return names
    }

    func isAvailable() -> Bool {
        detail != nil
    }

    var body: AnyView {
        AnyView(WidgetBody(widget: self))
    }

    /// A real view rather than an inline tree, so that reading the readout
    /// establishes a dependency on the widget. This widget refreshes on demand
    /// and its strings are settled before the descender is built, so it is not
    /// exposed the way the media transport was, the shape is shared for the
    /// same reason the other two now hold it.
    private struct WidgetBody: View {
        let widget: NotchAccessoryWidget

        var body: some View {
            HStack(spacing: NotchAccessoryWidget.interitemSpacing) {
                Text(widget.detail ?? "")
                    .font(ThawType.label)
                    .foregroundStyle(.primary)
                if let symbolName = widget.symbolName {
                    Image(systemName: symbolName)
                        .font(ThawType.detail)
                        .foregroundStyle(.secondary)
                        .frame(width: NotchAccessoryWidget.symbolWidth)
                }
                if let secondary = widget.secondary {
                    Text(secondary)
                        .font(ThawType.detail)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, NotchAccessoryWidget.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func refresh() {}

    // MARK: Presentation helpers

    /// A glyph for the condition the text describes, when it names one plainly
    /// enough to be sure. Keyword matching only holds for English, and an
    /// unrecognized string gets no glyph rather than a wrong one.
    private static func symbol(for detail: String) -> String? {
        let conditions: [(keyword: String, symbol: String)] = [
            ("thunder", "cloud.bolt.fill"),
            ("snow", "cloud.snow.fill"),
            ("sleet", "cloud.sleet.fill"),
            ("hail", "cloud.hail.fill"),
            ("drizzle", "cloud.drizzle.fill"),
            ("rain", "cloud.rain.fill"),
            ("fog", "cloud.fog.fill"),
            ("haze", "sun.haze.fill"),
            ("wind", "wind"),
            ("partly cloudy", "cloud.sun.fill"),
            ("mostly clear", "cloud.sun.fill"),
            ("overcast", "cloud.fill"),
            ("cloud", "cloud.fill"),
            ("clear", "sun.max.fill"),
            ("sunny", "sun.max.fill"),
        ]
        return conditions.first { detail.localizedCaseInsensitiveContains($0.keyword) }?.symbol
    }

    private static func measure(_ string: String, in font: NSFont) -> CGFloat {
        guard !string.isEmpty else {
            return 0
        }
        return ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }
}
