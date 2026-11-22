//
//  OnboardingPreviewSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

#if DEBUG
    import SwiftUI

    /// Only for the canvas: permissions with fixed answers and an unstarted AppState on its own
    /// preferences, so the onboarding previews never ask macOS for anything or start the app.
    @MainActor
    enum OnboardingPreview {
        /// How every permission answers Grant Access.
        enum Answer {
            case grants
            case declines
        }

        static let suiteName = "com.stonerl.Thaw.onboarding-previews"

        /// Real names and details, with the grants given here and no system checks.
        static func permissions(
            granted: Set<AppPermissions.PermissionKey> = [],
            answer: Answer = .grants
        ) -> AppPermissions {
            AppPermissions(
                accessibility: AccessibilityPermission(stub: stub(granted.contains(.accessibility), answer)),
                screenRecording: ScreenRecordingPermission(stub: stub(granted.contains(.screenRecording), answer)),
                fullDiskAccess: FullDiskAccessPermission(stub: stub(granted.contains(.fullDiskAccess), answer)),
                controlCenterAppList: ControlCenterAppListPermission(stub: stub(granted.contains(.controlCenterAppList), answer))
            )
        }

        /// Redirects process-wide defaults before creating the model, as VisibilityPreviewSettings does.
        static func appState() -> AppState {
            guard let store = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Could not create the onboarding preview preferences")
            }
            store.removePersistentDomain(forName: suiteName)
            Defaults.store = store
            return AppState()
        }

        /// Always on, and turning it off writes nothing.
        static func launchAtLogin() -> LaunchAtLoginSetting {
            LaunchAtLoginSetting(readStatus: { true }, writeStatus: { _ in /* Preview only. */ })
        }

        private static func stub(_ isGranted: Bool, _ answer: Answer) -> PermissionStub {
            let grant = PreviewGrant(isGranted: isGranted)
            return PermissionStub(
                check: { grant.isGranted },
                request: { completion in
                    switch answer {
                    case .grants:
                        grant.isGranted = true
                        completion(true, false)
                    case .declines:
                        // Reported as a prompt, so the next check marks it declined.
                        completion(false, true)
                    }
                }
            )
        }
    }

    extension View {
        /// The onboarding window's width, and the page's own height, as the window sizes itself.
        func onboardingPreviewFrame() -> some View {
            frame(width: ThawOnboardingWindowMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One stub's grant, which Grant Access can turn on.
    private final class PreviewGrant {
        var isGranted: Bool

        init(isGranted: Bool) {
            self.isGranted = isGranted
        }
    }
#endif
