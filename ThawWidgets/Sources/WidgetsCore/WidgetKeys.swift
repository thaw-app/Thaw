//
//  WidgetKeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Where the widget icon's settings are saved. The names keep the prefix
/// Thaw used before widgets became a module, so imported settings still read.
enum WidgetKeys {
    static let prefix = "StatusIconPrototype."
    static let live = prefix + "live"
    static let samples = prefix + "samples"
    static let outer = prefix + "outer"
    static let outerSource = prefix + "outerSource"
    static let center = prefix + "center"
    static let bottom = prefix + "bottom"
    static let bottomSource = prefix + "bottomSource"
}
