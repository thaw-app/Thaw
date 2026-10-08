//
//  ReducedModeURLCommand.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What a thaw:// URL asks of the reduced mode.
///
///     thaw://toggle-hidden                 show the hidden apps, or hide them again
///     thaw://hide-app?bundle=com.example   add an app to the hidden ones
///     thaw://show-app?bundle=com.example   take it out again
///     thaw://list-apps                     log the apps on offer
enum ReducedModeURLCommand: Equatable {
    case toggleHidden
    case hideApp(String)
    case showApp(String)
    case listApps

    init?(_ url: URL) {
        let bundle = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "bundle" }?.value
            .flatMap { $0.isEmpty ? nil : $0 }
        switch (url.host?.lowercased(), bundle) {
        case ("toggle-hidden", _): self = .toggleHidden
        case ("list-apps", _): self = .listApps
        case let ("hide-app", bundle?): self = .hideApp(bundle)
        case let ("show-app", bundle?): self = .showApp(bundle)
        default: return nil
        }
    }
}
