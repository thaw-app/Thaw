//
//  UpdateConsentSheet.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct UpdateConsentSheet: View {
    var onEnable: (_ autoDownload: Bool) -> Void
    var onDisable: () -> Void

    @State private var isProcessing = false
    @State private var autoDownload = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check for updates automatically?")
                .font(.title2.bold())

            Text("Should \(Constants.displayName) automatically check for updates? You can always check manually from the \(Constants.displayName) menu bar icon or Settings \(Constants.menuArrow) About.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            Toggle(isOn: $autoDownload) {
                Text("Automatically download and install updates")
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Don't Check") {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onDisable()
                }
                .disabled(isProcessing)
                Button("Check Automatically") {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onEnable(autoDownload)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
