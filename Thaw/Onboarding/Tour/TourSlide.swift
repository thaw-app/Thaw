//
//  TourSlide.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A single page of the onboarding tour, in the order it's presented.
enum ThawTourSlide: Int, CaseIterable, Identifiable {
    case welcome
    case menuBarManagement
    case menuBarAppearance
    case hotkeysAutomation
    case profiles

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome to Thaw")
        case .menuBarManagement: String(localized: "Menu Bar Management")
        case .menuBarAppearance: String(localized: "Menu Bar Appearance")
        case .hotkeysAutomation: String(localized: "Hotkeys & Automation")
        case .profiles: String(localized: "Profiles")
        }
    }

    var description: String {
        switch self {
        case .welcome:
            String(localized: "Thaw gives you complete control over your menu bar — hide clutter, customize the look, and automate your workflow.")
        case .menuBarManagement:
            String(localized: "Hide or show menu bar items on demand. Drag items between sections, keep your favorites always visible, and tuck the rest away in the always-hidden section.")
        case .menuBarAppearance:
            String(localized: "Paint your menu bar your way. Choose solid colors, gradients, and custom shapes, then add shadows and borders for a polished finish.")
        case .hotkeysAutomation:
            String(localized: "Trigger any action with a keystroke. Combine auto-rehide timers and Focus Filter integration so Thaw adapts to whatever you're doing.")
        case .profiles:
            String(localized: "Save your current configuration as a named profile. Switch between layouts instantly, or let Thaw switch automatically when you change your frontmost app.")
        }
    }

    /// The delay, in seconds, this slide's demo plays before auto-advancing
    /// to the next one. The welcome slide's value is unused — the tour never
    /// auto-advances off it — and the last looping slide wraps back around
    /// to the first looping slide, so the remaining slides loop forever until
    /// the user taps "Get Started".
    var autoAdvanceDelay: Double {
        switch self {
        case .welcome: 0
        case .menuBarManagement: 3.0
        case .menuBarAppearance: 3.8
        case .hotkeysAutomation: 3.0
        case .profiles: 3.7
        }
    }
}
