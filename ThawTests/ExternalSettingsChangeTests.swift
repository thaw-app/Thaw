//
//  ExternalSettingsChangeTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Combine
import Foundation
import Testing
@testable import Thaw

@Suite("External settings changes")
@MainActor
struct ExternalSettingsChangeTests {
    @Test("A setting key is required")
    func keyIsRequired() {
        let missingKey = Notification(name: .settingsDidChangeViaURI)
        let incorrectlyTypedKey = Notification(
            name: .settingsDidChangeViaURI,
            userInfo: ["key": 42]
        )

        #expect(ExternalSettingsChange(missingKey) == nil)
        #expect(ExternalSettingsChange(incorrectlyTypedKey) == nil)
    }

    @Test("Typed values are decoded from notification payloads")
    func typedValuesAreDecoded() throws {
        let notification = Notification(
            name: .settingsDidChangeViaURI,
            userInfo: [
                "key": "rehideInterval",
                "value": true,
                "doubleValue": 12.5,
                "rawEnumValue": 2,
            ]
        )

        let change = try #require(ExternalSettingsChange(notification))

        #expect(change.key == "rehideInterval")
        #expect(change.boolValue == true)
        #expect(change.doubleValue == 12.5)
        #expect(change.rawEnumValue == 2)
    }

    @Test("The observer ignores malformed notifications and delivers valid changes")
    func observerFiltersAndDelivers() async {
        var subscription: AnyCancellable?

        await confirmation("Delivered one valid settings change") { confirm in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                subscription = NotificationCenter.observeSettingsChangesViaURI { change in
                    #expect(change.key == "showOnHover")
                    #expect(change.boolValue == true)
                    confirm()
                    continuation.resume()
                }

                NotificationCenter.default.post(name: .settingsDidChangeViaURI, object: nil)
                NotificationCenter.default.post(
                    name: .settingsDidChangeViaURI,
                    object: nil,
                    userInfo: ["key": "showOnHover", "value": true]
                )
            }
        }

        subscription?.cancel()
    }
}
