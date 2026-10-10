//
//  HidingMethodTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("One hiding method runs at a time")
struct HidingMethodTests {
    @Test("The two stored switches pick the method, and Native wins")
    func switchesPickTheMethod() {
        #expect(HidingMethod(nativeAppHidingEnabled: true, hidesAppleItems: false) == .native)
        #expect(HidingMethod(nativeAppHidingEnabled: true, hidesAppleItems: true) == .native)
        #expect(HidingMethod(nativeAppHidingEnabled: false, hidesAppleItems: false) == .standard)
        #expect(HidingMethod(nativeAppHidingEnabled: false, hidesAppleItems: true) == .everything)
    }

    @Test("Each method writes the switches it was read from", arguments: HidingMethod.allCases)
    func methodRoundTrips(method: HidingMethod) {
        #expect(HidingMethod(
            nativeAppHidingEnabled: method.usesNativeAppHiding, hidesAppleItems: method.hidesAppleItems
        ) == method)
    }

    @Test("Only Everything hides Clock, Control Center and Siri")
    func onlyEverythingHidesAppleItems() {
        #expect(HidingMethod.everything.hidesAppleItems)
        #expect(!HidingMethod.standard.hidesAppleItems)
        #expect(!HidingMethod.native.hidesAppleItems)
    }

    @Test("Every method has its own identity, name and explanation")
    func methodsAreTellableApart() {
        let methods = HidingMethod.allCases
        #expect(Set(methods.map(\.id)).count == methods.count)
        #expect(Set(methods.map { "\($0.localized)" }).count == methods.count)
        #expect(Set(methods.map { "\($0.explanation)" }).count == methods.count)
    }

    @Test("Each explanation is two lines: what it does, then what it costs", arguments: HidingMethod.allCases)
    func explanationHasTwoLines(method: HidingMethod) {
        let text = "\(method.explanation)"
        #expect(text.contains("\\n") || text.contains("\n"))
    }
}
