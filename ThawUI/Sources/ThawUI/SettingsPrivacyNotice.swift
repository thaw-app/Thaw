//
//  SettingsPrivacyNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The green promise at the top of a Privacy page, on the page's ground.
public struct SettingsPrivacyNotice: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    public init(title: LocalizedStringResource, message: LocalizedStringResource) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        // Footer-only section: the one placement where a pill renders
        // without the grouped form's section card around it.
        ThawSection {
            EmptyView()
        } footer: {
            SettingsWarningPill(
                title: title,
                message: message,
                systemImage: "hand.raised.fill",
                tint: .green
            )
        }
    }
}
