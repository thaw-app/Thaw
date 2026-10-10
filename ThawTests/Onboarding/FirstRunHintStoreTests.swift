//
//  FirstRunHintStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization for FirstRunHintStore run against an in-memory
/// array instead of the defaults domain: every hint starts pending, a
/// dismissal is written once and never again, raw values the current build
/// does not recognise survive every write, and the first-hide confirmation
/// fires exactly once.
@Suite("First-run hint store")
@MainActor
struct FirstRunHintStoreTests {
    /// Stands in for the defaults domain and the HUD: holds the stored
    /// array, records every write, and counts first-hide confirmations.
    @MainActor
    private final class Recorder {
        var stored: [String]
        var writes: [[String]] = []
        var firstHideCount = 0

        init(stored: [String] = []) {
            self.stored = stored
        }

        func makeStore() -> FirstRunHintStore {
            FirstRunHintStore(
                read: { self.stored },
                write: {
                    self.stored = $0
                    self.writes.append($0)
                },
                onFirstHide: { self.firstHideCount += 1 }
            )
        }
    }

    @Test("a fresh store has every hint pending and writes nothing")
    func freshStoreIsAllPending() {
        let recorder = Recorder()
        let store = recorder.makeStore()
        for hint in FirstRunHint.allCases {
            #expect(store.isPending(hint), "\(hint) should be pending")
        }
        #expect(store.dismissed.isEmpty)
        #expect(recorder.writes.isEmpty)
    }

    @Test("a stored dismissal is read back as not pending")
    func storedDismissalIsReadBack() {
        let recorder = Recorder(stored: [FirstRunHint.hideByDrag.rawValue])
        let store = recorder.makeStore()
        #expect(!store.isPending(.hideByDrag))
        #expect(store.isPending(.firstHideConfirmed))
        #expect(recorder.writes.isEmpty)
    }

    @Test("dismiss persists the hint and is idempotent")
    func dismissPersistsOnce() {
        let recorder = Recorder()
        let store = recorder.makeStore()

        store.dismiss(.hideByDrag)
        #expect(!store.isPending(.hideByDrag))
        #expect(recorder.writes == [[FirstRunHint.hideByDrag.rawValue]])
        #expect(recorder.stored == [FirstRunHint.hideByDrag.rawValue])

        store.dismiss(.hideByDrag)
        #expect(recorder.writes.count == 1)
    }

    @Test("each new dismissal writes once, in declaration order")
    func dismissalsWriteInDeclarationOrder() {
        let recorder = Recorder()
        let store = recorder.makeStore()

        for hint in FirstRunHint.allCases.reversed() {
            store.dismiss(hint)
        }

        #expect(recorder.writes.count == FirstRunHint.allCases.count)
        #expect(recorder.stored == FirstRunHint.allCases.map(\.rawValue))
        for hint in FirstRunHint.allCases {
            #expect(!store.isPending(hint))
        }
    }

    @Test("unknown raw values already in storage survive a write")
    func unknownRawValuesSurvive() {
        let unknown = "someHintFromANewerBuild"
        let recorder = Recorder(stored: [unknown])
        let store = recorder.makeStore()

        // The unknown string is not a current case, so nothing is dismissed.
        for hint in FirstRunHint.allCases {
            #expect(store.isPending(hint))
        }

        store.dismiss(.hideByDrag)
        #expect(recorder.stored == [FirstRunHint.hideByDrag.rawValue, unknown])
    }

    @Test("markFirstHide fires once and reports whether it did")
    func markFirstHideFiresOnce() {
        let recorder = Recorder()
        let store = recorder.makeStore()
        #expect(recorder.firstHideCount == 0)

        #expect(store.markFirstHide())
        #expect(recorder.firstHideCount == 1)

        #expect(!store.markFirstHide())
        #expect(recorder.firstHideCount == 1)
    }

    @Test("markFirstHide retires the confirmation hint and persists it")
    func markFirstHideDismissesConfirmation() {
        let recorder = Recorder()
        let store = recorder.makeStore()

        store.markFirstHide()
        #expect(!store.isPending(.firstHideConfirmed))
        #expect(store.isPending(.hideByDrag))
        #expect(recorder.writes == [[FirstRunHint.firstHideConfirmed.rawValue]])
    }

    @Test("markFirstHide does not fire when the confirmation was stored earlier")
    func markFirstHideSkipsStoredConfirmation() {
        let recorder = Recorder(stored: [FirstRunHint.firstHideConfirmed.rawValue])
        let store = recorder.makeStore()

        #expect(!store.markFirstHide())
        #expect(recorder.firstHideCount == 0)
        #expect(recorder.writes.isEmpty)
    }
}
