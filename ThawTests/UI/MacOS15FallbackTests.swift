//
//  MacOS15FallbackTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation
import Testing
@testable import Thaw

@MainActor
@Suite("macOS 15 fallbacks")
struct MacOS15FallbackTests {
    @Observable
    final class Counter {
        var value = 0
    }

    @Test("Without glass, the pickers leave out the glass background and tint")
    func glassIsHiddenWithoutSupport() {
        #expect(!MenuBarBackgroundKind.availableCases(supportsGlass: false).contains(.glass))
        #expect(!MenuBarTintKind.availableCases(supportsGlass: false).contains(.glass))
        #expect(MenuBarBackgroundKind.availableCases(supportsGlass: true) == MenuBarBackgroundKind.allCases)
        #expect(MenuBarTintKind.availableCases(supportsGlass: true) == MenuBarTintKind.allCases)
    }

    @Test("This host's cases follow its glass support")
    func hostCasesFollowSupport() {
        #expect(MenuBarBackgroundKind.availableCases(keeping: .none) == MenuBarBackgroundKind.availableCases(supportsGlass: ThawGlass.isSupported))
        #expect(MenuBarTintKind.availableCases(keeping: .noTint) == MenuBarTintKind.availableCases(supportsGlass: ThawGlass.isSupported))
    }

    @Test("A saved glass selection stays in the pickers without glass")
    func savedGlassStaysListed() {
        #expect(MenuBarBackgroundKind.availableCases(supportsGlass: false, keeping: .glass) == MenuBarBackgroundKind.allCases)
        #expect(MenuBarTintKind.availableCases(supportsGlass: false, keeping: .glass) == MenuBarTintKind.allCases)
        #expect(!MenuBarBackgroundKind.availableCases(supportsGlass: false, keeping: .solid).contains(.glass))
        #expect(!MenuBarTintKind.availableCases(supportsGlass: false, keeping: .solid).contains(.glass))
    }

    @Test("The tracking stream yields the current value, then each change")
    func trackedValuesYieldChanges() async {
        let counter = Counter()
        var iterator = trackedValues { counter.value }.makeAsyncIterator()

        #expect(await iterator.next() == 0)
        counter.value = 1
        #expect(await iterator.next() == 1)
        counter.value = 2
        #expect(await iterator.next() == 2)
    }

    @Test("A cancelled tracking stream stops")
    func trackedValuesStop() async {
        let counter = Counter()
        let task = Task { @MainActor in
            var seen = [Int]()
            for await value in trackedValues({ counter.value }) {
                seen.append(value)
                if seen.count == 2 {
                    break
                }
            }
            return seen
        }
        await Task.yield()
        counter.value = 5

        #expect(await task.value == [0, 5])
    }
}
