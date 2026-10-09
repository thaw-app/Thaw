//
//  UnseenMenuBarHosts.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Apps that had menu bar items when Thaw last ran, are running now, and
/// still show none.
///
/// After a login launch the walk can stay blind to some apps for the whole
/// session while those apps answer anyone else. Their items then sit outside
/// the menu bar look and never hide, and nothing says why. A relaunch clears
/// it, and the cause is still unknown, so this only detects it.
///
/// The baseline is the previous session's hosts, not every identifier ever
/// seen: plenty of apps show an item only some of the time. A host counts as
/// unseen after staying missing for confirmationDelay, so an app still
/// putting its item up after launch is not flagged. A host flagged in
/// maximumStrikes launches in a row is taken for one that stopped showing
/// an item, and dropped.
nonisolated struct UnseenMenuBarHosts: Equatable {
    static let confirmationDelay: TimeInterval = 30
    static let maximumStrikes = 3

    /// Where persisted() is kept between launches.
    static let defaultsKey = "MenuBarItemManager.expectedMenuBarHosts"

    /// The bundles that had menu bar items when Thaw last ran.
    static func formerHosts() -> Set<String> {
        Set(UserDefaults.standard.dictionary(forKey: defaultsKey)?.keys.map { $0 } ?? [])
    }

    /// Bundles expected to host items, with how many launches in a row each
    /// has been flagged.
    private(set) var expected: [String: Int]
    private var missingSince: [String: Date] = [:]
    private(set) var flagged: Set<String> = []

    /// Hosts from the baseline that are running and missing from seen: the ones worth asking about.
    func candidates(seen: Set<String>, running: Set<String>) -> Set<String> {
        Set(expected.keys).intersection(running).subtracting(seen)
    }

    init(expected: [String: Int]) {
        self.expected = expected
    }

    /// Updates from one settled inventory. seen and running are bundle
    /// identifiers. Returns whether flagged changed.
    ///
    /// quiet holds running apps that show nothing and are not being missed: switched off in the
    /// system's Menu Bar list, or asked and answering that they have no items. They are never flagged.
    mutating func update(seen: Set<String>, running: Set<String>, quiet: Set<String> = [], now: Date) -> Bool {
        let previous = flagged
        for bundle in seen {
            expected[bundle] = 0
            missingSince[bundle] = nil
        }
        for bundle in expected.keys where !seen.contains(bundle) {
            guard running.contains(bundle), !quiet.contains(bundle) else {
                missingSince[bundle] = nil
                continue
            }
            missingSince[bundle] = missingSince[bundle] ?? now
        }
        flagged = Set(missingSince.compactMap { bundle, since in
            now.timeIntervalSince(since) >= Self.confirmationDelay ? bundle : nil
        })
        return flagged != previous
    }

    /// What to carry into the next launch: every host seen this session, and
    /// every flagged one with one more strike, minus hosts out of strikes.
    func persisted() -> [String: Int] {
        var result = [String: Int]()
        for (bundle, strikes) in expected {
            if flagged.contains(bundle) {
                guard strikes + 1 < Self.maximumStrikes else { continue }
                result[bundle] = strikes + 1
            } else {
                result[bundle] = strikes
            }
        }
        return result
    }
}
