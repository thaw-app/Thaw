//
//  FirstRunHints.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

/// The things Thaw teaches once, in place, and never again.
///
/// Each case is one hint with one dismissal. The raw value is what persists,
/// so a case may be renamed only with a migration of the stored string.
enum FirstRunHint: String, CaseIterable, Sendable {
    /// The layout hint above the bars: drag an icon into Hidden.
    case hideByDrag
    /// The one-time confirmation after the first drop into Hidden.
    case firstHideConfirmed
    /// The launch prompt offering the beta native app hiding.
    case nativeAppHidingOffer
}

/// Which first-run hints have been retired, and the one place they retire.
///
/// A hint is pending until it is dismissed, and a dismissal is forever: it is
/// written through to the defaults store as the hint's raw value, so the
/// hint stays gone across launches and across the panes that show it. The
/// store is @Observable, so a pane that reads isPending(_:) in its body
/// drops the hint the moment a drop elsewhere dismisses it.
///
/// Reading and writing go through injected closures so tests can run the
/// store against an array instead of the user's defaults domain, and the
/// first-hide confirmation goes through a closure for the same reason: the
/// production closure shows the HUD, a test's records that it was asked to.
@MainActor
@Observable
final class FirstRunHintStore {
    static let shared = FirstRunHintStore()

    /// The hints that have been retired.
    private(set) var dismissed: Set<FirstRunHint>

    /// Raw values in the stored array that no current case claims, written
    /// by a newer build, most likely. Preserved on every write so running an
    /// older build never un-dismisses a hint the newer one retired.
    private let unknownRawValues: [String]

    private let write: ([String]) -> Void

    private let onFirstHide: () -> Void

    /// - Parameters:
    ///   - read: Returns the stored raw values. Called once, here.
    ///   - write: Persists the raw values after each dismissal.
    ///   - onFirstHide: Runs once, on the first drop into Hidden. Defaults to
    ///     the HUD's one-word confirmation.
    init(
        read: @escaping () -> [String],
        write: @escaping ([String]) -> Void,
        onFirstHide: @escaping () -> Void = { ThawHUD.show(symbol: "eye.slash", text: "Hidden") }
    ) {
        let stored = read()
        dismissed = Set(stored.compactMap(FirstRunHint.init(rawValue:)))
        unknownRawValues = stored.filter { FirstRunHint(rawValue: $0) == nil }
        self.write = write
        self.onFirstHide = onFirstHide
    }

    /// The production store, backed by Defaults.Key.dismissedFirstRunHints.
    convenience init() {
        self.init(
            read: { Defaults.stringArray(forKey: .dismissedFirstRunHints) ?? [] },
            write: { Defaults.set($0, forKey: .dismissedFirstRunHints) }
        )
    }

    /// Whether hint should still be shown.
    func isPending(_ hint: FirstRunHint) -> Bool {
        !dismissed.contains(hint)
    }

    /// Retires hint for good. Idempotent: a second dismissal writes nothing.
    func dismiss(_ hint: FirstRunHint) {
        guard dismissed.insert(hint).inserted else { return }
        persist()
    }

    /// Called on the first drop into Hidden: shows the HUD once and dismisses
    /// FirstRunHint.firstHideConfirmed. Returns true if it fired, and
    /// false on every call after that.
    @discardableResult
    func markFirstHide() -> Bool {
        guard isPending(.firstHideConfirmed) else { return false }
        dismiss(.firstHideConfirmed)
        onFirstHide()
        return true
    }

    /// Writes the retired hints in declaration order, so the stored array is
    /// stable across runs rather than following the set's iteration order.
    private func persist() {
        let known = FirstRunHint.allCases.filter(dismissed.contains).map(\.rawValue)
        write(known + unknownRawValues)
    }
}
