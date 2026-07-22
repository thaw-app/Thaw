//
//  KeyCapView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

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
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .bold()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
            }
        }
        .foregroundStyle(.secondary)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
