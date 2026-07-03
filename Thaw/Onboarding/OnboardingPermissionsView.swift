//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

/// One permission this screen tracks — mirrors the real Thaw app's
/// `Permission` type (title, icon, detail bullets, required vs. optional,
/// and a read-only check function).
private struct DemoPermission: Identifiable {
    let id = UUID()
    let title: String
    let iconName: String
    let iconColor: Color
    let details: [String]
    let isRequired: Bool
    let settingsURL: URL
    let checkGranted: () -> Bool
}

/// Real Thaw needs both Accessibility (required — it can't move or detect
/// menu bar items without it) and Screen Recording (optional — used for live
/// previews, color sampling, and visual search; Thaw runs in a limited mode
/// without it). Copy and detail bullets are taken directly from Thaw's own
/// `AccessibilityPermission`/`ScreenRecordingPermission` definitions.
@MainActor
private let demoPermissions: [DemoPermission] = [
    DemoPermission(
        title: "Accessibility",
        iconName: "accessibility",
        iconColor: .blue,
        details: [
            "Detect the menu bar items on your Mac and where they're positioned.",
            "Move menu bar items to rearrange or hide them.",
        ],
        isRequired: true,
        settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
        checkGranted: { AXIsProcessTrusted() }
    ),
    DemoPermission(
        title: "Screen Recording",
        iconName: "record.circle",
        iconColor: .red,
        details: [
            "Show live previews of your menu bar items.",
            "Sample colors from the menu bar to adjust its tint.",
        ],
        isRequired: false,
        settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!,
        // Preflight only checks status — unlike CGRequestScreenCaptureAccess(),
        // it never triggers the system permission prompt on its own.
        checkGranted: { CGPreflightScreenCaptureAccess() }
    ),
]

/// The permissions screen shown after the tour finishes — mirrors the real
/// Thaw app's separate `PermissionsWindow` (two permission cards: required
/// Accessibility, optional Screen Recording), reskinned with this design's
/// glass panels. Each status check is read-only and permission-free — it
/// reflects this demo app's *actual* trust state, live-updating if the user
/// grants access in System Settings while this screen is open.
struct ThawPermissionsView: View {
    var onContinue: () -> Void

    @State private var appeared = false
    @State private var grantedByID: [DemoPermission.ID: Bool] = [:]

    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var requiredGranted: Bool {
        demoPermissions.filter(\.isRequired).allSatisfy { grantedByID[$0.id] ?? false }
    }

    private var allGranted: Bool {
        demoPermissions.allSatisfy { grantedByID[$0.id] ?? false }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("Enable Permissions")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Thaw needs the permissions below to manage your menu bar. Nothing leaves your Mac; everything here runs locally.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)

            HStack(alignment: .top, spacing: 14) {
                ForEach(demoPermissions) { permission in
                    permissionCard(permission)
                }
            }
            // Each card's own maxHeight: .infinity (needed so they match each
            // other) would otherwise expand to fill the whole top-aligned
            // VStack's leftover height. Pinning the row to its natural
            // content height first, then equalizing the two cards *within*
            // that bounded height, is what keeps them both the same size
            // without also inflating them.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            privacyPanel

            VStack(spacing: 12) {
                Button {
                    onContinue()
                } label: {
                    Text(requiredGranted && !allGranted ? "Continue in Limited Mode" : "Continue")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glassProminent)
                .disabled(!requiredGranted)

                if !requiredGranted {
                    Text("Accessibility is required to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear {
            refreshStatuses()
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appeared = true }
        }
        .onReceive(pollTimer) { _ in refreshStatuses() }
    }

    private func permissionCard(_ permission: DemoPermission) -> some View {
        let granted = grantedByID[permission.id] ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: permission.iconName)
                    .foregroundStyle(permission.iconColor)
                Text(permission.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !permission.isRequired {
                    Text("Optional")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(permission.details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 3))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 5)
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button {
                    NSWorkspace.shared.open(permission.settingsURL)
                } label: {
                    Text("Grant Access")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeOut(duration: 0.3), value: granted)
    }

    /// Three concrete, checkable privacy facts rather than vague reassurance.
    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            privacyFact("No analytics or usage tracking")
            privacyFact("No network requests; everything stays on this Mac")
            privacyFact("Open source (GPL); you can audit exactly what it does")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 30)
    }

    private func privacyFact(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 1.5)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshStatuses() {
        for permission in demoPermissions {
            grantedByID[permission.id] = permission.checkGranted()
        }
    }
}
