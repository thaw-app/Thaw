//
//  PermissionViewsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Permission views")
struct PermissionViewsTests {
    private final class Stub: PermissionPresentable {
        var titleText = Text(verbatim: "Reading")
        var iconName = "eye"
        let iconColor = Color.blue
        var isRequired = true
        var hasPermission = false
        var wasDeclined = false
        var hasSettingsPane = true
        private(set) var calls: [String] = []

        func performRequest() {
            calls.append("request")
        }

        func openSettingsPane() {
            calls.append("settings")
        }
    }

    private static let strings = PermissionStrings(
        optional: "Extra",
        granted: "Allowed",
        grantAccess: "Allow",
        openSettings: "Go to Settings"
    )

    private func control(_ permission: Stub, layout: PermissionStatusControl.Layout = .inline) -> PermissionStatusControl {
        PermissionStatusControl(permission: permission, strings: Self.strings, layout: layout)
    }

    private func label(_ permission: Stub, placement: PermissionLabel.BadgePlacement) -> NSHostingView<PermissionLabel> {
        NSHostingView(rootView: PermissionLabel(permission: permission, strings: Self.strings, badgePlacement: placement))
    }

    @Test("A first request asks the system")
    func firstRequest() {
        let permission = Stub()
        let view = control(permission)
        #expect(view.requestTitle == "Allow")
        view.request()
        #expect(permission.calls == ["request"])
    }

    @Test("After a decline the control leads to System Settings")
    func afterDecline() {
        let permission = Stub()
        permission.wasDeclined = true
        let view = control(permission)
        #expect(view.requestTitle == "Go to Settings")
        view.request()
        #expect(permission.calls == ["settings"])
    }

    @Test("A declined permission with no settings pane keeps asking")
    func declinedWithoutPane() {
        let permission = Stub()
        permission.wasDeclined = true
        permission.hasSettingsPane = false
        let view = control(permission)
        #expect(view.requestTitle == "Allow")
        view.request()
        #expect(permission.calls == ["request"])
    }

    @Test("The label and status control draw for each state", arguments: [false, true])
    func viewsDraw(granted: Bool) {
        let permission = Stub()
        permission.hasPermission = granted
        permission.isRequired = granted
        let view = VStack {
            PermissionLabel(permission: permission, strings: Self.strings, titleFont: .headline, badgePlacement: .adjacent)
            PermissionLabel(permission: permission, strings: Self.strings, badgePlacement: .trailing)
            PermissionLabel(permission: permission, strings: Self.strings, badgePlacement: .below)
            control(permission, layout: .inline)
            control(permission, layout: .filled)
        }
        #expect(NSHostingView(rootView: view).fittingSize.height > 0)
    }

    @Test("The optional badge makes the label taller only when it sits below")
    func badgeBelowIsTaller() {
        let optional = Stub()
        optional.isRequired = false
        let adjacent = label(optional, placement: .adjacent).fittingSize.height
        #expect(label(optional, placement: .below).fittingSize.height > adjacent)

        let required = Stub()
        #expect(label(required, placement: .below).fittingSize.height == label(required, placement: .adjacent).fittingSize.height)
    }

    @Test("A wide icon and a narrow one leave the title in the same place")
    func iconBox() {
        let narrow = Stub()
        narrow.iconName = "exclamationmark"
        let wide = Stub()
        wide.iconName = "rectangle.and.hand.point.up.left.filled"
        #expect(label(narrow, placement: .adjacent).fittingSize.width == label(wide, placement: .adjacent).fittingSize.width)
    }
}
