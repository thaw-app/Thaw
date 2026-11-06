//
//  ThawBarConfigurationControlsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("The Thaw Bar and always-show switches")
struct ThawBarConfigurationControlsTests {
    /// Two stored switches the controls write, kept in a class so the bindings can change them.
    private final class Switches {
        var useThawBar: Bool
        var alwaysShowHiddenItems: Bool

        init(useThawBar: Bool, alwaysShowHiddenItems: Bool) {
            self.useThawBar = useThawBar
            self.alwaysShowHiddenItems = alwaysShowHiddenItems
        }
    }

    private func controls(
        for switches: Switches,
        context: ThawBarConfigurationControls<EmptyView>.Context = .display
    ) -> ThawBarConfigurationControls<EmptyView> {
        ThawBarConfigurationControls(
            alwaysShowHiddenItems: Binding { switches.alwaysShowHiddenItems } set: { switches.alwaysShowHiddenItems = $0 },
            useThawBar: Binding { switches.useThawBar } set: { switches.useThawBar = $0 },
            location: .constant(.dynamic),
            layout: .constant(.grid),
            gridColumns: .constant(4),
            itemScale: .constant(1),
            context: context
        )
    }

    @Test("The Thaw Bar switch writes only the Thaw Bar setting")
    func thawBarSwitchWritesUseThawBar() {
        let switches = Switches(useThawBar: false, alwaysShowHiddenItems: true)
        let controls = controls(for: switches)
        controls.thawBarSwitch.wrappedValue = true
        #expect(switches.useThawBar)
        #expect(switches.alwaysShowHiddenItems)
        controls.thawBarSwitch.wrappedValue = false
        #expect(!switches.useThawBar)
        #expect(switches.alwaysShowHiddenItems)
    }

    @Test("The always-show switch writes only the always-show setting")
    func alwaysShowSwitchWritesAlwaysShow() {
        let switches = Switches(useThawBar: false, alwaysShowHiddenItems: false)
        let controls = controls(for: switches)
        controls.alwaysShowSwitch.wrappedValue = true
        #expect(switches.alwaysShowHiddenItems)
        #expect(!switches.useThawBar)
        controls.alwaysShowSwitch.wrappedValue = false
        #expect(!switches.alwaysShowHiddenItems)
        #expect(!switches.useThawBar)
    }

    @Test("The switches read the stored settings")
    func switchesReadSettings() {
        let switches = Switches(useThawBar: true, alwaysShowHiddenItems: true)
        let controls = controls(for: switches)
        #expect(controls.thawBarSwitch.wrappedValue)
        #expect(controls.alwaysShowSwitch.wrappedValue)
    }

    @Test("Always show is off limits only while the Thaw Bar is on")
    func alwaysShowDisabledWithThawBar() {
        #expect(controls(for: Switches(useThawBar: true, alwaysShowHiddenItems: false)).isAlwaysShowDisabled)
        #expect(!controls(for: Switches(useThawBar: false, alwaysShowHiddenItems: false)).isAlwaysShowDisabled)
    }

    @Test(
        "The controls draw for a display and for the template, with the Thaw Bar on and off",
        arguments: [ThawBarConfigurationControls<EmptyView>.Context.display, .globalTemplate], [true, false]
    )
    func controlsDraw(context: ThawBarConfigurationControls<EmptyView>.Context, useThawBar: Bool) throws {
        let switches = Switches(useThawBar: useThawBar, alwaysShowHiddenItems: !useThawBar)
        let view = Form {
            controls(for: switches, context: context)
        }
        .frame(width: 520, height: 600)
        let render = OffscreenRender(view, size: CGSize(width: 520, height: 600))
        #expect(try render.pixels().contains { $0 != 0 })
    }

    @Test("The shortcut placement row draws while the Thaw Bar is on")
    func shortcutPlacementDraws() throws {
        let view = Form {
            ThawBarConfigurationControls(
                alwaysShowHiddenItems: .constant(false),
                useThawBar: .constant(true),
                location: .constant(.dynamic),
                layout: .constant(.horizontal),
                gridColumns: .constant(4),
                itemScale: .constant(1),
                shortcutPlacement: .constant(.pointer),
                context: .display
            )
        }
        .frame(width: 520, height: 600)
        let render = OffscreenRender(view, size: CGSize(width: 520, height: 600))
        #expect(try render.pixels().contains { $0 != 0 })
    }
}
