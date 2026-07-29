//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The permissions step shown at the end of the glass onboarding tour.
struct ThawPermissionsView: View {
    @Environment(AppPermissions.self) private var permissions

    var onContinue: () -> Void

    @State private var appeared = false

    private var requiredGranted: Bool {
        permissions.permissionsState != .missing
    }

    private var allGranted: Bool {
        permissions.permissionsState == .hasAll
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("Enable Permissions")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    Text("Almost there! \(Constants.displayName) needs the permissions below to manage your menu bar.")
                    Text("Your data stays on your Mac — nothing is ever collected or shared.")
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)

            HStack(alignment: .top, spacing: 14) {
                ForEach(permissions.allPermissions) { permission in
                    OnboardingPermissionCard(permission: permission)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

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
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                appeared = true
            }
        }
    }
}

private struct OnboardingPermissionCard: View {
    @Environment(AppState.self) private var appState
    let permission: Permission

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: permission.iconName)
                    .foregroundStyle(permission.iconColor)

                Text(permission.title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
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

            if permission.hasPermission {
                Label("Permission Granted", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            } else {
                Button {
                    permission.performRequest()
                } label: {
                    Text("Grant Permission")
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
        .animation(.easeOut(duration: 0.3), value: permission.hasPermission)
        .onChange(of: permission.hasPermission) { _, hasPermission in
            // Granting a permission sends the user off to System Settings;
            // once the grant lands, bring the app (and this window) back to
            // the front — same recovery the standalone PermissionsView does.
            guard hasPermission else {
                return
            }
            appState.activate(withPolicy: .regular)
            appState.openWindow(.permissions)
        }
    }
}
