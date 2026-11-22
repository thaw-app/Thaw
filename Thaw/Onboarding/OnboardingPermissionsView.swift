//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// The permissions window's list, for first-launch onboarding and for startup recovery when a grant went
/// missing. Onboarding lists what Thaw needs; recovery adds the optional ones.
struct ThawPermissionsView: View {
    enum Mode {
        /// First launch: the required permissions only.
        case onboarding
        /// Startup recovery: every permission, the optional ones in their own group.
        case recovery
    }

    @Environment(AppPermissions.self) private var permissions

    private let mode: Mode
    private let onContinue: () -> Void
    private let chooseReducedMode: (() -> Void)?

    /// - Parameters:
    ///   - mode: Defaults to Mode.recovery.
    ///   - chooseReducedMode: Replaces the Reduced mode choice, for previews.
    ///   - onContinue: Called once the user has finished with the step.
    init(mode: Mode = .recovery, chooseReducedMode: (() -> Void)? = nil, onContinue: @escaping () -> Void) {
        self.mode = mode
        self.chooseReducedMode = chooseReducedMode
        self.onContinue = onContinue
    }

    private var requiredGranted: Bool {
        permissions.permissionsState != .missing
    }

    private var headerMessage: LocalizedStringResource {
        switch mode {
        case .onboarding:
            "\(Constants.displayName) needs these to see and arrange your menu bar items. Permission checks stay on your Mac."
        case .recovery:
            "\(Constants.displayName) needs the required ones to see and arrange your menu bar items. Permission checks stay on your Mac."
        }
    }

    private var optionalPermissions: [Permission] {
        permissions.allPermissions.filter { !$0.isRequired }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ThawSpacing.gutter) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                OnboardingHeader(title: Text("Allow access"), message: Text(headerMessage))

                lists

                if !permissions.accessibility.hasPermission {
                    Text(ReducedModeOfferButton.offer)
                        .font(ThawType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(ThawSpacing.section)
            .frame(maxHeight: .infinity)

            Divider()

            footer
        }
        .thawAnimation(ThawMotion.settle, value: permissions.accessibility.hasPermission)
        .background(VisualEffectBackground())
        .onAppear {
            // Preflight only: appearing must never raise a Screen Recording
            // prompt. The async probe is for the continue button.
            permissions.refreshPermissionsState()
        }
    }

    @ViewBuilder
    private var lists: some View {
        switch mode {
        case .onboarding:
            PermissionList(permissions: permissions.requiredPermissions)
        case .recovery:
            VStack(alignment: .leading, spacing: ThawSpacing.compact) {
                groupTitle("Required")
                PermissionList(permissions: permissions.requiredPermissions)
                groupTitle("Optional")
                    .padding(.top, ThawSpacing.base)
                PermissionList(permissions: optionalPermissions)
            }
        }
    }

    private func groupTitle(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(ThawType.sublabel.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.leading, ThawSpacing.inset)
            .accessibilityAddTraits(.isHeader)
    }

    private var footer: some View {
        HStack(spacing: ThawSpacing.base) {
            // The window has no close button while access is missing.
            Button("Quit \(Constants.displayName)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
            .help("Quit \(Constants.displayName) without granting access")

            Spacer(minLength: ThawSpacing.base)

            if !permissions.accessibility.hasPermission {
                ReducedModeOfferButton(choose: chooseReducedMode)
            }

            Button("Continue", action: finish)
                .buttonStyle(.thawProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!requiredGranted)
        }
        .controlSize(.large)
        .padding(.horizontal, ThawSpacing.section)
        .padding(.vertical, ThawSpacing.gutter)
    }

    private func finish() {
        switch mode {
        case .onboarding:
            // Preflight only: the async probe can raise a Screen Recording
            // prompt this page never mentioned.
            permissions.refreshPermissionsState()
            onContinue()
        case .recovery:
            Task {
                await permissions.refreshPermissionsState()
                onContinue()
            }
        }
    }
}

/// Permissions as rows in one rounded group, as a grouped form draws them.
private struct PermissionList: View {
    let permissions: [Permission]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                if index > 0 {
                    Divider()
                        .padding(.leading, ThawSpacing.inset + 24 + ThawSpacing.inset)
                }
                PermissionRow(permission: permission)
            }
        }
        .onboardingCard()
    }
}

/// A permission's name, what it is for, and its Grant Access button or granted mark.
private struct PermissionRow: View {
    let permission: Permission

    /// True once the permission is granted while this row is on screen, so the mark bounces only then.
    @State private var grantedWhileShown = false

    var body: some View {
        HStack(spacing: ThawSpacing.inset) {
            Image(systemName: permission.iconName)
                .font(ThawType.sidebarSymbol)
                .foregroundStyle(permission.iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(permission.title)
                    .font(ThawType.label)
                Text(permission.rowSubtitle(grantedWhileShown: grantedWhileShown))
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if permission.waitsAfterDecline {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Waiting for access"))
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: ThawSpacing.compact) {
                if permission.offersChoosingFileAgain {
                    Button("Choose File…", action: permission.performRequest)
                        .transition(.opacity)
                }
                control
            }
            .fixedSize()
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
        .accessibilityElement(children: .contain)
        .thawAnimation(ThawMotion.settle, value: permission.awaitingPromptAnswer)
        .thawAnimation(ThawMotion.settle, value: permission.offersChoosingFileAgain)
        .thawAnimation(ThawMotion.settle, value: permission.waitsAfterDecline)
        .onChange(of: permission.hasPermission) { _, granted in
            grantedWhileShown = granted
        }
    }

    /// Hidden rather than removed while waiting, so the row keeps its width and the granted bounce still fires.
    private var control: some View {
        let waiting = permission.awaitingPromptAnswer
        return PermissionStatusControl(permission: permission)
            .modifier(GrantedBounce(justGranted: grantedWhileShown))
            .opacity(waiting ? 0 : 1)
            .allowsHitTesting(!waiting)
            .accessibilityHidden(waiting)
            .overlay(alignment: .trailing) {
                if waiting {
                    HStack(spacing: ThawSpacing.compact) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting…")
                            .font(ThawType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                }
            }
    }
}

// MARK: - Row copy

extension Permission {
    /// After a declined file panel the request control opens System Settings, so the row keeps the panel too.
    var offersChoosingFileAgain: Bool {
        requestOpensFilePanel && wasDeclined && hasSettingsPane && !hasPermission
    }

    /// A declined prompt sends the person to System Settings, so the row keeps waiting beside Open System Settings.
    /// A dismissed file panel is a plain no, and the row offers the file again instead.
    var waitsAfterDecline: Bool {
        requestState == .declined(waiting: true) && hasSettingsPane && !offersChoosingFileAgain
    }

    /// The line under the row's title: what to turn on after a decline, or the relaunch note for a file granted here.
    func rowSubtitle(grantedWhileShown: Bool) -> String {
        if hasPermission {
            guard grantedWhileShown, requestOpensFilePanel else { return summary }
            return String(localized: "You may need to quit and reopen \(Constants.displayName) before it takes effect.")
        }
        return wasDeclined ? declinedHint ?? summary : summary
    }
}

#if DEBUG
    /// The access step and the recovery screen, on sample permissions.
    private struct PermissionsPreview: View {
        let mode: ThawPermissionsView.Mode
        @State var permissions: AppPermissions
        /// The Reduced mode button reads it, though the preview replaces its action.
        @State private var appState = OnboardingPreview.appState()

        var body: some View {
            ThawPermissionsView(
                mode: mode,
                chooseReducedMode: { /* Preview only. */ },
                onContinue: { /* Preview only. */ }
            )
            .environment(permissions)
            .environment(appState)
            .onboardingPreviewFrame()
        }
    }

    #Preview("Access") {
        PermissionsPreview(mode: .onboarding, permissions: OnboardingPreview.permissions())
    }

    #Preview("Access, declined") {
        PermissionsPreview(mode: .onboarding, permissions: OnboardingPreview.permissions(answer: .declines))
    }

    #Preview("Access, Accessibility granted") {
        PermissionsPreview(mode: .onboarding, permissions: OnboardingPreview.permissions(granted: [.accessibility]))
    }

    #Preview("Missing permissions") {
        PermissionsPreview(mode: .recovery, permissions: OnboardingPreview.permissions())
    }

    #Preview("Missing permissions, only optional ones") {
        PermissionsPreview(
            mode: .recovery,
            permissions: OnboardingPreview.permissions(granted: [.accessibility, .fullDiskAccess])
        )
    }
#endif
