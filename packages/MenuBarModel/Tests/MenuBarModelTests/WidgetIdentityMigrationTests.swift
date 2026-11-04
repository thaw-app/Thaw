//
//  WidgetIdentityMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// Thaw's widget was named by its label, which carries the live readings. It now has a fixed identifier.
@Suite("Widget identity migration")
struct WidgetIdentityMigrationTests {
    @Test(
        "A widget saved under its old label moves to the fixed identifier",
        arguments: ["com.stonerl.Thaw", "com.stonerl.Thaw.debug"]
    )
    func savedLabelsMigrate(bundle: String) {
        let saved = [
            "Thaw widget · Live readings. Connection: Wi-Fi. Battery level: 63%. Wi-Fi strength: 67%",
            "Thaw widget · Sample readings. Symbol: CPU. Battery level: 0%. Wi-Fi strength: 100%",
            "Thaw widget preview",
        ]
        for label in saved {
            #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\(label)") == "\(bundle):Thaw.Widget.Preview")
        }
    }

    @Test("A live widget that still reports its label gets the fixed identity")
    func liveLabelMigrates() {
        let tag = MenuBarItemTag(namespace: .string("com.stonerl.Thaw"), title: "Thaw widget · Live readings. Connection: Ethernet.")
        #expect(tag.tagIdentifier == "com.stonerl.Thaw:Thaw.Widget.Preview")
    }

    @Test("Thaw's other items and other apps' titles are left alone")
    func othersUntouched() {
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("com.stonerl.Thaw:Thaw.ControlItem.Hidden") == "com.stonerl.Thaw:Thaw.ControlItem.Hidden")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("com.example.app:Thaw widget · Live readings") == "com.example.app:Thaw widget · Live readings")
    }
}
