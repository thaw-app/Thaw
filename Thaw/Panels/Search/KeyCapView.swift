//
//  KeyCapView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct KeyCapView: View {
    private let text: String?
    private let systemImage: String?
    private let font: Font?

    init(text: String, font: Font? = nil) {
        self.text = text
        systemImage = nil
        self.font = font
    }

    init(systemImage: String) {
        text = nil
        self.systemImage = systemImage
        font = nil
    }

    var body: some View {
        Group {
            if let text {
                Text(verbatim: text)
                    .font(font)
                    .padding(.horizontal, ThawSpacing.tight)
                    .padding(.vertical, ThawSpacing.hairline)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .bold()
                    .padding(.horizontal, ThawSpacing.compact)
                    .padding(.vertical, ThawSpacing.tight)
            }
        }
        .foregroundStyle(.secondary)
        // A flat cap, not glass: glass per cap on the panel's glass refracts.
        .background(keyShape.fill(.quaternary))
        .overlay(keyShape.strokeBorder(.separator, lineWidth: 0.5))
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }
}
