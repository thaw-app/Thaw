//
//  TourSlide.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A single page of the onboarding tour, in the order it's presented.
/// Titles and descriptions mirror the real Thaw app's onboarding copy.
enum ThawTourSlide: Int, CaseIterable, Identifiable {
    case welcome
    case menuBarManagement
    case menuBarAppearance
    case hotkeysAutomation
    case profiles
    case integrations

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .welcome: "Welcome to your menu bar"
        case .menuBarManagement: "Menu Bar Management"
        case .menuBarAppearance: "Menu Bar Appearance"
        case .hotkeysAutomation: "Hotkeys & Automation"
        case .profiles: "Profiles"
        case .integrations: "Works With Your Tools"
        }
    }

    var description: String {
        switch self {
        case .welcome:
            "Thaw tucks the clutter away and keeps the icons you care about front and center. Click the icon anytime to show or hide them."
        case .menuBarManagement:
            "Hide or show menu bar items on demand. Drag items between sections, keep your favorites always visible, and tuck the rest away in the always-hidden section."
        case .menuBarAppearance:
            "Paint your menu bar your way. Choose solid colors, gradients, and custom shapes, then add shadows and borders for a polished finish."
        case .hotkeysAutomation:
            "Trigger any action with a keystroke. Combine auto-rehide timers and Focus Filter integration so Thaw adapts to whatever you're doing."
        case .profiles:
            "Save your current configuration as a named profile. Switch between layouts instantly, or let Thaw switch automatically when you change your frontmost app."
        case .integrations:
            "Install Thaw straight from Droppy's Droplets and it stays updated automatically, or toggle hidden items and search your menu bar without leaving the keyboard, right from Raycast."
        }
    }

    /// How long this slide plays before auto-advancing to the next one.
    /// Welcome is static (its value here is unused — the tour never
    /// auto-advances off it); every looping slide has a real delay, and
    /// Integrations advances back around to Management, so the loop runs
    /// forever until the user taps "Get Started".
    var autoAdvanceDelay: Double {
        switch self {
        case .welcome: 0
        case .menuBarManagement: 3.0
        case .menuBarAppearance: 3.8
        case .hotkeysAutomation: 3.0
        case .profiles: 3.7
        case .integrations: 3.5
        }
    }
}
