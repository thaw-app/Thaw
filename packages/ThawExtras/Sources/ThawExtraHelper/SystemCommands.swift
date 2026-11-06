//
//  SystemCommands.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Darwin

/// Resolves a C function from a private framework, or nil when the framework
/// or the symbol is missing on this macOS.
private func privateFunction<T>(_ name: String, in path: String, as _: T.Type) -> T? {
    guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
          let symbol = dlsym(handle, name)
    else {
        return nil
    }
    return unsafeBitCast(symbol, to: T.self)
}

/// Playback commands for the Now Playing stand-in.
///
/// Only commands: since macOS 15.4 the now-playing information is withheld
/// from processes without Apple's entitlement, so the stand-in cannot show
/// the track. Sending commands is not restricted.
enum NowPlayingCommands {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let send = privateFunction(
        "MRMediaRemoteSendCommand",
        in: "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        as: SendCommand.self
    )

    /// MediaRemote's command numbers.
    private enum Command: UInt32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    @MainActor
    static func populate(_ menu: NSMenu) {
        guard send != nil else {
            let item = NSMenuItem(title: String(localized: "Playback controls are unavailable"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        menu.addItem(item(String(localized: "Play/Pause"), symbol: "playpause.fill", .togglePlayPause))
        menu.addItem(item(String(localized: "Next Track"), symbol: "forward.fill", .nextTrack))
        menu.addItem(item(String(localized: "Previous Track"), symbol: "backward.fill", .previousTrack))
    }

    @MainActor
    private static func item(_ title: String, symbol: String, _ command: Command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Target.perform(_:)), keyEquivalent: "")
        item.target = Target.shared
        item.tag = Int(command.rawValue)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @MainActor
    private final class Target: NSObject {
        static let shared = Target()

        @objc func perform(_ sender: NSMenuItem) {
            _ = NowPlayingCommands.send?(UInt32(sender.tag), nil)
        }
    }
}

/// Session commands for the Fast User Switching stand-in, through the same
/// login framework calls the original menu uses.
enum UserSessionCommands {
    private typealias SessionCall = @convention(c) () -> Int32
    private static let loginFramework = "/System/Library/PrivateFrameworks/login.framework/login"
    private static let lockScreen = privateFunction("SACLockScreenImmediate", in: loginFramework, as: SessionCall.self)
    private static let loginWindow = privateFunction("SACSwitchToLoginWindow", in: loginFramework, as: SessionCall.self)

    @MainActor
    static func populate(_ menu: NSMenu) {
        let name = NSFullUserName()
        let header = NSMenuItem(title: name.isEmpty ? NSUserName() : name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        if lockScreen != nil {
            menu.addItem(item(String(localized: "Lock Screen"), #selector(Target.lock)))
        }
        if loginWindow != nil {
            menu.addItem(item(String(localized: "Login Window…"), #selector(Target.showLoginWindow)))
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Users & Groups Settings…"), #selector(Target.openSettings)))
    }

    @MainActor
    private static func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = Target.shared
        return item
    }

    @MainActor
    private final class Target: NSObject {
        static let shared = Target()

        @objc func lock() {
            _ = UserSessionCommands.lockScreen?()
        }

        @objc func showLoginWindow() {
            _ = UserSessionCommands.loginWindow?()
        }

        @objc func openSettings() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
