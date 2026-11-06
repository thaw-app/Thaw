//
//  Bridging+ManagedSpaces.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// What a Space holds, from the type field of its CGSCopyManagedDisplaySpaces entry.
public enum ManagedSpaceKind: Hashable, Sendable {
    case desktop
    case fullscreen
    /// A type Thaw doesn't know, kept so it is not numbered as a desktop.
    case other(Int)

    /// An entry without a type is a desktop.
    public init(rawType: Int?) {
        switch rawType.map({ CGSSpaceType(rawValue: UInt32(truncatingIfNeeded: $0)) }) {
        case nil, .user: self = .desktop
        case .fullscreen: self = .fullscreen
        default: self = .other(rawType ?? 0)
        }
    }
}

public extension Bridging {
    /// A space as the window server currently reports it.
    struct ManagedSpace: Hashable, Sendable {
        /// The space's identifier. Renumbered across logout.
        public let spaceID: CGSSpaceID
        /// A key that survives logout. Safe to persist.
        public let persistentKey: String
        /// The display the space belongs to.
        public let displayIdentifier: String
        /// The space's 1-based position within its display's list, full screen Spaces included.
        public let ordinal: Int
        public let kind: ManagedSpaceKind
        /// The app a full screen Space belongs to, when its entry names one.
        public let ownerPID: pid_t?

        public init(
            spaceID: CGSSpaceID,
            persistentKey: String,
            displayIdentifier: String,
            ordinal: Int,
            kind: ManagedSpaceKind = .desktop,
            ownerPID: pid_t? = nil
        ) {
            self.spaceID = spaceID
            self.persistentKey = persistentKey
            self.displayIdentifier = displayIdentifier
            self.ordinal = ordinal
            self.kind = kind
            self.ownerPID = ownerPID
        }
    }

    /// Returns every space the window server currently knows about.
    static func getManagedSpaces() -> [ManagedSpace] {
        guard let raw = cgsCopyManagedDisplaySpaces(cgsMainConnectionID()) else {
            managedSpacesLog.error("cgsCopyManagedDisplaySpaces returned nil")
            return []
        }
        guard let elements = arrayValue(of: raw.takeRetainedValue()) else {
            managedSpacesLog.error("cgsCopyManagedDisplaySpaces returned a value that is not an array")
            return []
        }
        let displays = elements.compactMap { element -> [String: Any]? in
            dictionaryValue(of: element as CFTypeRef)
        }
        if displays.count != elements.count {
            managedSpacesLog.error("cgsCopyManagedDisplaySpaces returned an array of unexpected type")
        }
        return managedSpaces(fromDisplays: displays)
    }

    /// The Spaces in entries shaped like CGSCopyManagedDisplaySpaces output, keyed by uuid.
    /// A display's default Space has an empty uuid, so its key comes from the display.
    static func managedSpaces(fromDisplays displays: [[String: Any]]) -> [ManagedSpace] {
        var result: [ManagedSpace] = []
        for display in displays {
            let displayIdentifier = display["Display Identifier"] as? String ?? "unknown"
            // Entries without a Spaces array are records for displays that are not attached.
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for (index, space) in spaces.enumerated() {
                guard let spaceID = space["id64"] as? CGSSpaceID else { continue }
                let uuid = space["uuid"] as? String ?? ""
                let kind = ManagedSpaceKind(rawType: space["type"] as? Int)
                result.append(ManagedSpace(
                    spaceID: spaceID,
                    persistentKey: uuid.isEmpty ? "display:\(displayIdentifier)#default" : uuid,
                    displayIdentifier: displayIdentifier,
                    ordinal: index + 1,
                    kind: kind,
                    ownerPID: kind == .fullscreen ? (space["pid"] as? Int).map { pid_t(truncatingIfNeeded: $0) } : nil
                ))
            }
        }
        return result
    }
}

private extension Bridging {
    static let managedSpacesLog = DiagLog(category: "ManagedSpaces")
}
