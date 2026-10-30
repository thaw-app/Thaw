//
//  MenuBarPresentationProvider+ItemSession.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import MenuBarModel
import PlatformRuntimeKit

/// Retroactive so it needs no kit release and works against the published
/// binary.
extension RuntimeItemSessionController: @retroactive MenuBarItemSessionTracking {}
