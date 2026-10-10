//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Permission step for first-launch onboarding and for startup recovery when
/// a grant went missing. Onboarding asks for one required grant at a time;
/// recovery lists every permission and allows continuing without optional ones.
struct ThawPermissionsView: View {
    enum Mode {
        /// First launch: Accessibility only, one primary action, and a way
        /// out for a window that has no close button.
        case onboarding
        /// Startup recovery: every permission, with a limited-mode continue
        /// when only the optional ones are missing.
        case recovery
    }

    @Environment(AppPermissions.self) private var permissions

    private let mode: Mode
    /// Whether granting here ends onboarding, so the button offers to open the app.
    private let finishesFlow: Bool
    private let onContinue: () -> Void

    @State private var appeared = false

    /// Whether Grant Access was pressed on this visit; gates the waiting row.
    @State private var hasRequested = false

    /// - Parameters:
    ///   - mode: Defaults to Mode.recovery.
    ///   - onContinue: Called once the user has finished with the step.
    init(mode: Mode = .recovery, finishesFlow: Bool = false, onContinue: @escaping () -> Void) {
        self.mode = mode
        self.finishesFlow = finishesFlow
        self.onContinue = onContinue
    }

    private var requiredGranted: Bool {
        permissions.permissionsState != .missing
    }

    private var allGranted: Bool {
        permissions.permissionsState == .hasAll
    }

    var body: some View {
        Group {
            switch mode {
            case .onboarding:
                onboardingLayout
            case .recovery:
                recoveryLayout
            }
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The onboarding window has no close button, so offer a small way out.
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                ReducedModeOfferButton()
                if mode == .onboarding {
                    quitButton
                }
            }
        }
        .background(VisualEffectBackground())
        .onAppear {
            // Preflight only: appearing must never raise a Screen Recording
            // prompt. The async probe is for the continue button.
            permissions.refreshPermissionsState()
            // A local curve because ThawMotion has no bouncy one.
            withThawAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                appeared = true
            }
        }
    }

    // MARK: - Recovery

    private var recoveryLayout: some View {
        VStack(spacing: 18) {
            header(
                title: "Enable Permissions",
                body: "\(Constants.displayName) uses the permissions below to manage your menu bar. Permission checks happen on your Mac."
            )

            HStack(alignment: .top, spacing: 14) {
                ForEach(permissions.allPermissions) { permission in
                    OnboardingPermissionCard(permission: permission)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            privacyPanel

            VStack(spacing: 12) {
                Button {
                    Task {
                        await permissions.refreshPermissionsState()
                        onContinue()
                    }
                } label: {
                    Text(requiredGranted && !allGranted ? "Continue Without Screen Recording" : "Continue")
                        .font(ThawType.heading)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!requiredGranted)

                Text("Accessibility is required to continue.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(requiredGranted ? 0 : 1)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Onboarding

    private var onboardingLayout: some View {
        VStack(spacing: 18) {
            header(
                title: "Allow access",
                body: onboardingHeaderBody
            )

            // The page's primary action is below, so no second Grant button.
            OnboardingPermissionCard(permission: focusPermission, showsRequestButton: false)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)

            privacyPanel

            onboardingActions(for: focusPermission)
        }
    }

    /// The first required grant still missing, Accessibility first, so the
    /// step never gates on a permission it did not ask for.
    private var focusPermission: Permission {
        permissions.requiredPermissions.first { !$0.hasPermission } ?? permissions.accessibility
    }

    /// Copy branches on this instead of interpolating a permission name, so
    /// each sentence stays a literal the string catalog can extract.
    private var focusIsAccessibility: Bool {
        focusPermission === permissions.accessibility
    }

    private var onboardingHeaderBody: LocalizedStringKey {
        if focusIsAccessibility {
            return finishesFlow
                ? "One last thing: \(Constants.displayName) needs Accessibility to see and move your menu bar items. Permission checks stay on your Mac."
                : "\(Constants.displayName) needs Accessibility to see and move your menu bar items. Permission checks stay on your Mac."
        }
        return finishesFlow
            ? "One last thing: \(Constants.displayName) needs the menu bar layout table to reorder items without taking over your cursor. You choose that one file yourself."
            : "\(Constants.displayName) needs the menu bar layout table to reorder items without taking over your cursor. You choose that one file yourself."
    }

    /// The page's action, its waiting state, and the System Settings route
    /// after a declined prompt.
    private func onboardingActions(for permission: Permission) -> some View {
        VStack(spacing: 12) {
            if permission.wasDeclined {
                SettingsWarningPill(
                    title: focusIsAccessibility
                        ? "Accessibility was not turned on"
                        : "Access to the layout table was not granted",
                    message: focusIsAccessibility
                        ? "Open System Settings, go to Privacy & Security \(Constants.menuArrow) Accessibility, and turn on \(Constants.displayName)."
                        : "Choose the file again, or give \(Constants.displayName) Full Disk Access in System Settings instead.",
                    actionTitle: "Open System Settings",
                    action: { permission.openSettingsPane() }
                )
                .transition(.opacity)
            }

            Button {
                if permission.hasPermission {
                    // Preflight only: the async probe can raise a Screen
                    // Recording prompt this page never mentioned.
                    permissions.refreshPermissionsState()
                    onContinue()
                } else {
                    hasRequested = true
                    permission.performRequest()
                }
            } label: {
                Text(onboardingActionTitle(for: permission))
                    .font(ThawType.heading)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)

            if hasRequested, !permission.hasPermission {
                HStack(spacing: ThawSpacing.compact) {
                    ProgressView()
                        .controlSize(.small)
                    Text(focusIsAccessibility ? "Waiting for Accessibility…" : "Waiting for access…")
                }
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
        .thawAnimation(ThawMotion.settle, value: permission.wasDeclined)
        .thawAnimation(ThawMotion.settle, value: permission.hasPermission)
    }

    private func onboardingActionTitle(for permission: Permission) -> LocalizedStringKey {
        if !permission.hasPermission {
            return "Grant Access"
        }
        return finishesFlow ? "Open \(Constants.displayName)" : "Continue"
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit \(Constants.displayName)")
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q")
        .help("Quit \(Constants.displayName) without granting access")
        .accessibilityLabel(Text("Quit \(Constants.displayName)"))
        .padding(.trailing, ThawSpacing.gutter)
        .padding(.bottom, ThawSpacing.inset)
    }

    // MARK: - Shared

    private func header(title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(ThawType.display)
                .multilineTextAlignment(.center)

            Text(body)
                .font(ThawType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            privacyFact("No analytics or usage tracking")
            privacyFact("Permission checks stay on your Mac")
            privacyFact("Open source under GPL; inspect how it works")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .padding(.horizontal, 30)
    }

    private func privacyFact(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(ThawType.micro.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 1.5)

            Text(text)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingPermissionCard: View {
    let permission: Permission

    /// Off in onboarding, where the page's primary action grants instead.
    var showsRequestButton = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionLabel(
                permission: permission,
                titleFont: ThawType.heading,
                badgePlacement: .below
            )

            VStack(alignment: .leading, spacing: 5) {
                ForEach(permission.onboardingDetails, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        // A 3pt bullet, not type: no text style is this small.
                        Image(systemName: "circle.fill")
                            .font(.system(size: 3))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 5)

                        Text(detail)
                            .font(ThawType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if showsRequestButton || permission.hasPermission {
                PermissionStatusControl(permission: permission, layout: .filled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .thawAnimation(ThawMotion.settle, value: permission.hasPermission)
    }
}
