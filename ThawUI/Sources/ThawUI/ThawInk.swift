//
//  ThawInk.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The foreground tones text is allowed to step down to.
///
/// SwiftUI's .secondary and .tertiary fall below the 4.5:1 text floor (as low
/// as 1.85:1), so secondary text goes through here.
///
/// .tertiary and .quaternary stay fine for non-text marks, where 3:1 applies.
public enum ThawInk {
    /// Supporting copy such as captions and annotations: 5.45:1 light,
    /// 6.02:1 dark.
    public static let supporting = Color.primary.opacity(0.7)
}
