//
//  DistributedNotificationCenter+Theme.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension DistributedNotificationCenter {
    /// Posted system-wide whenever the user switches between light and dark
    /// appearance.
    static let interfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")

    /// Posted system-wide when "Automatically hide and show the menu bar"
    /// changes; _HIHideMenuBar already holds the new value.
    static let menuBarHidingChangedNotification = Notification.Name("AppleInterfaceMenuBarHidingChangedNotification")
}
