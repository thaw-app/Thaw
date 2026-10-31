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
        // Centred between matched spacers, as the welcome screen is; the
        // minimum spacing handles Larger Text with no spare height.
        VStack(spacing: 0) {
            Spacer(minLength: ThawSpacing.section)
            switch mode {
            case .onboarding:
                onboardingLayout
            case .recovery:
                recoveryLayout
            }
            Spacer(minLength: ThawSpacing.section)
        }
        .padding(.horizontal, ThawSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    // MARK: - Recovery

    private var recoveryLayout: some View {
        VStack(spacing: ThawSpacing.gutter) {
            OnboardingHeader(
                title: Text("Enable Permissions"),
                message: Text("\(Constants.displayName) uses the permissions below to manage your menu bar. Permission checks happen on your Mac.")
            )

            // Two cards a row, as the bento lays out its cards: four across
            // left each one too narrow for its details.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ThawSpacing.inset, alignment: .top), count: 2),
                spacing: ThawSpacing.inset
            ) {
                ForEach(permissions.allPermissions) { permission in
                    PermissionCard(permission: permission)
                }
            }
            .frame(maxWidth: 620)

            privacyRow

            VStack(spacing: ThawSpacing.base) {
                OnboardingPrimaryButton {
                    Task {
                        await permissions.refreshPermissionsState()
                        onContinue()
                    }
                } label: {
                    Text(requiredGranted && !allGranted ? "Continue Without Screen Recording" : "Continue")
                }
                .disabled(!requiredGranted)

                Text("Accessibility is required to continue.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(requiredGranted ? 0 : 1)
            }
            .padding(.top, ThawSpacing.base)
        }
    }

    // MARK: - Onboarding

    private var onboardingLayout: some View {
        VStack(spacing: ThawSpacing.gutter) {
            OnboardingHeader(title: Text("Allow access"), message: Text(onboardingHeaderBody))

            // The page's primary action is below, so no second Grant button.
            PermissionCard(permission: focusPermission, showsRequestButton: false)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            privacyRow

            onboardingActions(for: focusPermission)
                .padding(.top, ThawSpacing.base)
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

    private var onboardingHeaderBody: LocalizedStringResource {
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
        VStack(spacing: ThawSpacing.base) {
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
                .frame(maxWidth: 520)
                .transition(.opacity)
            }

            OnboardingPrimaryButton {
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
            }

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
        .thawAnimation(ThawMotion.settle, value: permission.wasDeclined)
        .thawAnimation(ThawMotion.settle, value: permission.hasPermission)
    }

    private func onboardingActionTitle(for permission: Permission) -> LocalizedStringResource {
        if !permission.hasPermission {
            return "Grant Access"
        }
        return finishesFlow ? "Open \(Constants.displayName)" : "Continue"
    }

    private var quitButton: some View {
        OnboardingQuietButton(
            title: Text("Quit \(Constants.displayName)"),
            help: Text("Quit \(Constants.displayName) without granting access"),
            shortcut: KeyboardShortcut("q")
        ) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Shared

    /// The privacy facts as the welcome screen's capsules, in one row.
    private var privacyRow: some View {
        OnboardingFactRow {
            OnboardingFactCapsule(
                symbol: "hand.raised",
                label: Text("No analytics or tracking"),
                spoken: Text("No analytics or usage tracking")
            )
            OnboardingFactCapsule(
                symbol: "lock",
                label: Text("Permission checks stay on your Mac"),
                spoken: Text("Permission checks stay on your Mac")
            )
            OnboardingFactCapsule(
                symbol: "lock.open",
                label: Text("Open source"),
                spoken: Text("Open source under GPL; inspect how it works")
            )
        }
    }
}

private struct PermissionCard: View {
    let permission: Permission

    /// Off in onboarding, where the page's primary action grants instead.
    var showsRequestButton = true

    var body: some View {
        OnboardingPermissionCard(surface: .glass, isGranted: permission.hasPermission) {
            PermissionLabel(
                permission: permission,
                titleFont: ThawType.heading,
                badgePlacement: .below
            )
        } details: {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(permission.onboardingDetails, id: \.self) { detail in
                    HStack(alignment: .top, spacing: ThawSpacing.compact) {
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
        } control: {
            if showsRequestButton || permission.hasPermission {
                PermissionStatusControl(permission: permission, layout: .filled)
            }
        }
    }
}
