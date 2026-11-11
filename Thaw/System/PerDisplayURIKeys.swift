//
//  PerDisplayURIKeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// One per-display setting a thaw:// link can read and change: its default displays, how a value is
/// checked and applied, and what thaw://get reports. A new setting is one entry in PerDisplayURIKeys.all.
@MainActor
struct PerDisplayURIKey {
    typealias Configuration = DisplayThawBarConfiguration
    typealias Update = (Configuration) -> Configuration

    enum Kind {
        /// A Boolean, which a link sets or toggles: where it is read, and how it is written.
        case flag(KeyPath<Configuration, Bool>, (Configuration, Bool) -> Configuration)
        /// A value. accept turns the link's text into the text forwarded to the display settings, or nil
        /// when the value is bad; update turns that forwarded text into the change.
        case value(accept: (String) -> String?, update: (String) -> Update?, validValues: String?)
    }

    let name: String
    /// The displays a link changes when it names none.
    let defaultScope: SettingsURIHandler.PerDisplayScope
    let kind: Kind
    /// The thaw://get reply for the key. Its "value" is also what a display listing reports.
    let reading: (Configuration) -> [String: Any]

    var isFlag: Bool {
        if case .flag = kind { true } else { false }
    }

    /// What a thaw:// change does to one display's configuration, or nil for a bad or missing value.
    func update(toggles: Bool, flag: Bool?, text: String?) -> Update? {
        switch kind {
        case let .flag(keyPath, apply):
            if toggles {
                return { apply($0, !$0[keyPath: keyPath]) }
            }
            return Self.change(to: flag, apply)
        case let .value(_, update, _):
            return text.flatMap(update)
        }
    }
}

extension PerDisplayURIKey {
    /// The change that writes value, or nil when there is no value to write.
    static func change<Value>(to value: Value?, _ apply: @escaping (Configuration, Value) -> Configuration) -> Update? {
        guard let value else { return nil }
        return { apply($0, value) }
    }

    static func flag(
        _ name: String,
        scope: SettingsURIHandler.PerDisplayScope,
        _ keyPath: KeyPath<Configuration, Bool>,
        _ apply: @escaping (Configuration, Bool) -> Configuration
    ) -> PerDisplayURIKey {
        PerDisplayURIKey(name: name, defaultScope: scope, kind: .flag(keyPath, apply)) {
            ["value": $0[keyPath: keyPath], "type": "boolean"]
        }
    }

    /// A number: parse reads and clamps it, and the clamped number is what is forwarded and applied.
    static func number<Number>(
        _ name: String,
        scope: SettingsURIHandler.PerDisplayScope,
        parse: @escaping (String) -> Number?,
        apply: @escaping (Configuration, Number) -> Configuration,
        reading: @escaping (Configuration) -> [String: Any]
    ) -> PerDisplayURIKey {
        PerDisplayURIKey(
            name: name,
            defaultScope: scope,
            kind: .value(
                accept: { parse($0).map { String(describing: $0) } },
                update: { change(to: parse($0), apply) },
                validValues: nil
            ),
            reading: reading
        )
    }
}

/// The per-display keys, in the order thaw:// lists them.
@MainActor
enum PerDisplayURIKeys {
    static let gridColumnRange = 2 ... 10
    static let spacingOffsetRange = -16.0 ... 16.0

    static let all: [PerDisplayURIKey] = [
        .flag("useThawBar", scope: .activeDisplay, \.useThawBar) { $0.withUseThawBar($1) },
        PerDisplayURIKey(
            name: "thawBarLocation",
            defaultScope: .allEnabledDisplays,
            kind: .value(
                accept: { ThawBarLocation.fromString($0).map { String($0.rawValue) } },
                // The forwarded text is always the raw value, so names are not read again here.
                update: { PerDisplayURIKey.change(to: Int($0).flatMap(ThawBarLocation.init(rawValue:))) { $0.withThawBarLocation($1) } },
                validValues: "dynamic, mousePointer, thawIcon, leftAligned, rightAligned (or 0-4)"
            ),
            reading: {
                [
                    "value": String(describing: $0.thawBarLocation),
                    "rawValue": $0.thawBarLocation.rawValue,
                    "type": "enum",
                    "validValues": Dictionary(uniqueKeysWithValues: ThawBarLocation.allCases.map { (String(describing: $0), $0.rawValue) }),
                ]
            }
        ),
        .flag("alwaysShowHiddenItems", scope: .allNonThawBarDisplays, \.alwaysShowHiddenItems) { $0.withAlwaysShowHiddenItems($1) },
        PerDisplayURIKey(
            name: "thawBarLayout",
            defaultScope: .allEnabledDisplays,
            kind: .value(
                accept: { ThawBarLayout.fromString($0).map { String($0.rawValue) } },
                update: { PerDisplayURIKey.change(to: ThawBarLayout.fromString($0)) { $0.withThawBarLayout($1) } },
                validValues: "horizontal, vertical, grid (or 0, 1, 2)"
            ),
            reading: {
                [
                    "value": String(describing: $0.thawBarLayout),
                    "rawValue": $0.thawBarLayout.rawValue,
                    "type": "enum",
                    "validValues": ["horizontal": 0, "vertical": 1, "grid": 2],
                ]
            }
        ),
        .number(
            "gridColumns",
            scope: .allEnabledDisplays,
            parse: { Int($0).map { Swift.max(gridColumnRange.lowerBound, Swift.min($0, gridColumnRange.upperBound)) } },
            apply: { $0.withGridColumns($1) },
            reading: { ["value": $0.gridColumns, "type": "integer", "range": ["min": gridColumnRange.lowerBound, "max": gridColumnRange.upperBound]] }
        ),
        .number(
            "thawBarItemScale",
            scope: .allEnabledDisplays,
            parse: { DisplaySettingsManager.finite($0).map(ThawBarItemSize.clampedScale) },
            apply: { $0.withThawBarItemScale($1) },
            reading: { ["value": $0.thawBarItemScale, "type": "double", "range": ["min": ThawBarItemSize.minimumScale, "max": ThawBarItemSize.maximumScale]] }
        ),
        .number(
            "itemSpacingOffset",
            scope: .activeDisplay,
            parse: { DisplaySettingsManager.finite($0).map { Swift.max(spacingOffsetRange.lowerBound, Swift.min($0.rounded(), spacingOffsetRange.upperBound)) } },
            apply: { $0.withItemSpacingOffset($1) },
            reading: { ["value": $0.itemSpacingOffset, "type": "double", "range": ["min": -16, "max": 16]] }
        ),
        .flag("useThawBarForAlwaysHidden", scope: .allNonThawBarDisplays, \.useThawBarForAlwaysHidden) { $0.withUseThawBarForAlwaysHidden($1) },
    ]

    private static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static func key(_ name: String) -> PerDisplayURIKey? {
        byName[name]
    }

    /// Every key's current value on one display, as a display listing reports them.
    static func values(of configuration: DisplayThawBarConfiguration) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: all.compactMap { key in key.reading(configuration)["value"].map { (key.name, $0) } })
    }
}
