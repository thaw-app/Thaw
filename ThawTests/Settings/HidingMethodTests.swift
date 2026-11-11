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
    @Test("There are two methods, Native and Standard")
    func twoMethods() {
        #expect(HidingMethod.allCases == [.native, .standard])
    }

    @Test("The native switch picks the method")
    func nativeSwitchPicksTheMethod() {
        #expect(HidingMethod(nativeAppHidingEnabled: true) == .native)
        #expect(HidingMethod(nativeAppHidingEnabled: false) == .standard)
    }

    @Test("Each method writes the switch it was read from", arguments: HidingMethod.allCases)
    func methodRoundTrips(method: HidingMethod) {
        #expect(HidingMethod(nativeAppHidingEnabled: method.usesNativeAppHiding) == method)
    }

    @Test("Standard hides Clock, Control Center and Siri, and Native cannot")
    func standardHidesAppleItems() {
        #expect(HidingMethod.standard.hidesAppleItems)
        #expect(!HidingMethod.native.hidesAppleItems)
    }

    @Test("The Apple-items switch reads what each method needs", .scratchDefaults, arguments: HidingMethod.allCases)
    func appleItemsSwitchFollowsTheMethod(method: HidingMethod) {
        withPrivateSettingsChangeCenter {
            let settings = LayoutSettings()
            settings.enableNativeAppHiding = method.usesNativeAppHiding
            #expect(settings.enableExperimentalSystemItemHiding == method.hidesAppleItems)
        }
    }

    @Test("Every method has its own identity, name and explanation")
    func methodsAreTellableApart() {
        let methods = HidingMethod.allCases
        #expect(Set(methods.map(\.id)).count == methods.count)
        #expect(Set(methods.map { "\($0.localized)" }).count == methods.count)
        #expect(Set(methods.map { "\($0.explanation)" }).count == methods.count)
    }

    @Test("Each explanation is one line, with the costs left to the limitations popover", arguments: HidingMethod.allCases)
    func explanationIsOneLine(method: HidingMethod) {
        let text = "\(method.explanation)"
        #expect(!text.contains("\\n") && !text.contains("\n"))
    }
}
