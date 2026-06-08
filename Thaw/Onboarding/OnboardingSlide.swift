//
//  OnboardingSlide.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A single page of the onboarding tour, in the order it's presented.
enum OnboardingSlide: Int, CaseIterable, Identifiable {
    case welcome
    case menuBarManagement
    case menuBarAppearance
    case hotkeysAutomation
    case profiles
    case permissions

    var id: Int {
        rawValue
    }

    /// The slide's headline, shown beneath its mockup.
    var title: LocalizedStringResource {
        switch self {
        case .welcome: "Welcome to Thaw"
        case .menuBarManagement: "Menu Bar Management"
        case .menuBarAppearance: "Menu Bar Appearance"
        case .hotkeysAutomation: "Hotkeys & Automation"
        case .profiles: "Profiles"
        case .permissions: "Permissions"
        }
    }

    /// The slide's body copy, shown beneath its title.
    var description: LocalizedStringResource {
        switch self {
        case .welcome:
            "Thaw gives you complete control over your menu bar — hide clutter, customize the look, and automate your workflow."
        case .menuBarManagement:
            "Hide or show menu bar items on demand. Drag items between sections, keep your favorites always visible, and tuck the rest away in the always-hidden section."
        case .menuBarAppearance:
            "Paint your menu bar your way. Choose solid colors, gradients, and custom shapes, then add shadows and borders for a polished finish."
        case .hotkeysAutomation:
            "Trigger any action with a keystroke. Combine auto-rehide timers and Focus Filter integration so Thaw adapts to whatever you're doing."
        case .profiles:
            "Save your current configuration as a named profile. Switch between layouts instantly, or let Thaw switch automatically when you change your frontmost app."
        case .permissions:
            "Thaw needs a couple of permissions to manage your menu bar. You can grant them now, or skip and grant them later from Settings."
        }
    }
}
