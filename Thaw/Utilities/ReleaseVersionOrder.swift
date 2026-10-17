//
//  ReleaseVersionOrder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Orders Thaw's version strings, such as 3.0.0-alpha.9 and 3.0.0-alpha.10, by semantic-version precedence.
///
/// Numbers compare as numbers, so alpha.9 comes before alpha.10, and a prerelease comes before its release.
nonisolated enum ReleaseVersionOrder {
    /// Whether lhs is an earlier release than rhs.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = split(lhs)
        let right = split(rhs)
        if left.core != right.core {
            return left.core.lexicographicallyPrecedes(right.core)
        }
        switch (left.prerelease, right.prerelease) {
        case let (lhsPre?, rhsPre?):
            return identifiersPrecede(lhsPre, rhsPre)
        case (.some, nil):
            return true
        default:
            return false
        }
    }

    /// The numeric core padded to three parts, and the dot-separated prerelease identifiers if any.
    private static func split(_ version: String) -> (core: [Int], prerelease: [Substring]?) {
        let withoutBuild = version.split(separator: "+", maxSplits: 1).first ?? ""
        let parts = withoutBuild.split(separator: "-", maxSplits: 1)
        var core = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        while core.count < 3 {
            core.append(0)
        }
        let prerelease = parts.count > 1 ? parts[1].split(separator: ".") : nil
        return (core, prerelease)
    }

    /// Numeric identifiers compare as numbers and come before text ones; a shorter list that matches so far comes first.
    private static func identifiersPrecede(_ lhs: [Substring], _ rhs: [Substring]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return left < right
            }
        }
        return lhs.count < rhs.count
    }
}
