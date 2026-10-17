//
//  ThawRowLabel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// A plain row's title with its one line of detail under it. The detail
/// follows the setting that hides descriptions, like annotations do.
struct ThawRowLabel: View {
    @Environment(\.settingsDescriptionsVisible) private var descriptionsVisible

    private let title: Text
    private let detail: Text?

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.detail = detail.map { Text($0) }
    }

    init(_ title: LocalizedStringKey, verbatimDetail: String) {
        self.title = Text(title)
        detail = Text(verbatim: verbatimDetail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
            title
            if descriptionsVisible, let detail {
                detail
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
