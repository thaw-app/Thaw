//
//  UpdateChannel+WhatsNew.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A release belongs to the channel its version's prerelease tag names:
/// alpha is Alpha, beta or rc is Beta, and no tag is Stable.
nonisolated extension UpdateChannel {
    public init(version: String) {
        let tag = ReleaseVersionOrder.prereleaseTag(of: version)?.lowercased() ?? ""
        if tag.hasPrefix("alpha") {
            self = .alpha
        } else if tag.isEmpty {
            self = .stable
        } else {
            self = .beta
        }
    }

    public var systemImage: String {
        switch self {
        case .stable: "checkmark.seal"
        case .beta: "flask"
        case .alpha: "hammer"
        }
    }
}
