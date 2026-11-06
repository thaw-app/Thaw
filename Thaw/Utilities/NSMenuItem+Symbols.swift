//
//  NSMenuItem+Symbols.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

extension NSMenuItem {
    /// Menu-item symbol image visibility preference for macOS 27+.
    ///
    /// Maps to NSMenuItem.ImageVisibility. Applied by key, so it is ignored
    /// rather than fatal if the key is absent.
    enum PreferredSymbolImageVisibility {
        /// Follow AppKit policy (hides symbol images on macOS 27 by default).
        case automatic
        /// Prefer showing the image; AppKit may still hide it in some contexts.
        case visible
        /// Prefer hiding the image.
        case hidden
    }

    /// Assigns an SF Symbol image and opts into macOS 27's menu-image visibility policy.
    ///
    /// On macOS 27, .automatic hides symbol images unless AppKit treats the
    /// item as a common system action (Settings, Share, Print, …). Pass
    /// .visible only for actions that should keep an icon on Golden Gate.
    ///
    /// On macOS 27 a symbol image is only assigned when visibility is
    /// .visible. Under .automatic or .hidden AppKit still runs the
    /// _NSSimpleImageView updateLayer path, then hides the image, and leaks
    /// small NSMutableDictionary and NSAffineTransform pairs per item on each
    /// popUp. Common system actions keep any system-provided icons.
    ///
    /// preferredImageVisibility is applied via KVC so this file compiles
    /// against the macOS 26 SDK used by CI.
    func setSymbolImage(
        systemName: String,
        accessibilityDescription: String?,
        preferredVisibility: PreferredSymbolImageVisibility = .automatic
    ) {
        applyPreferredImageVisibility(preferredVisibility)
        switch preferredVisibility {
        case .visible:
            image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibilityDescription)
        case .automatic, .hidden:
            image = nil
        }
    }

    /// Soft-sets AppKit's macOS 27 preferredImageVisibility without requiring
    /// the 27 SDK at compile time. Raw values match NSMenuItemImageVisibility.
    private func applyPreferredImageVisibility(_ preferredVisibility: PreferredSymbolImageVisibility) {
        let setter = NSSelectorFromString("setPreferredImageVisibility:")
        guard responds(to: setter) else { return }
        let rawValue = switch preferredVisibility {
        case .automatic: 0 // NSMenuItemImageVisibilityAutomatic
        case .visible: 1 // NSMenuItemImageVisibilityVisible
        case .hidden: 2 // NSMenuItemImageVisibilityHidden
        }
        setValue(rawValue, forKey: "preferredImageVisibility")
    }
}
