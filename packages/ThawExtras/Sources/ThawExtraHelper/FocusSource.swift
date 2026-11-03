//
//  Adapted from Barometer (https://github.com/mackid1993/Barometer)
//  Copyright (Barometer) © 2026 mackid1993. Used with permission.
//  Licensed under the GNU GPLv3
//
//  FocusSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation
import Intents
import OSLog

/// One user-configured Focus mode exposed by macOS.
struct FocusMode: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let symbolName: String?

    init(id: String, name: String, symbolName: String? = nil) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }
}

/// Current Focus state and the modes macOS permits the user to select.
enum FocusSnapshot: Equatable, Sendable {
    /// Neither the private service nor an already-authorized public Focus status is readable.
    case unavailable
    /// Focus is off.
    case inactive(availableModes: [FocusMode])
    /// Focus is on. The mode is nil when the public API proves activity but withholds its identity.
    case active(mode: FocusMode?, availableModes: [FocusMode])

    /// Whether Focus is currently active, when state is available.
    var isActive: Bool? {
        switch self {
        case .unavailable: nil
        case .inactive: false
        case .active: true
        }
    }

    /// Active mode when macOS exposes its identity.
    var activeMode: FocusMode? {
        guard case let .active(mode, _) = self else { return nil }
        return mode
    }

    /// Modes available for explicit selection.
    var availableModes: [FocusMode] {
        switch self {
        case .unavailable: []
        case let .inactive(modes), let .active(_, modes): modes
        }
    }
}

/// Result of a user-requested Focus change.
enum FocusControlResult: Equatable, Sendable {
    case applied
    case unavailable
    case failed
}

/// Uses DoNotDisturb when allowed, then a read-only database fallback with existing Full Disk Access.
/// The final Intents fallback requires prior authorization and exposes activity, not mode identity; never requests permission.
actor FocusSource {
    private let runtime: DoNotDisturbRuntime?
    private let publicStatus: @Sendable () -> FocusSnapshot
    private let logger = Logger(subsystem: "com.stonerl.Thaw.extra.focus", category: "focus")

    /// Creates a source over the installed system framework.
    init() {
        runtime = DoNotDisturbRuntime(clientIdentifier: "com.stonerl.Thaw.extra.focus")
        publicStatus = Self.currentPublicStatus
    }

    /// Whether current Focus state is readable without requesting authorization.
    var isAvailable: Bool {
        read() != .unavailable
    }

    /// Reads the current state without requesting Focus authorization or modifying the Focus database.
    func read() -> FocusSnapshot {
        if let runtime {
            switch runtime.read() {
            case let .success(snapshot): return snapshot
            case let .failure(message):
                logger.debug("DoNotDisturb read unavailable: \(message, privacy: .public)")
            }
        }
        return publicStatus()
    }

    /// Activates a mode selected by the user.
    func activate(_ mode: FocusMode) -> FocusControlResult {
        guard let runtime else { return .unavailable }
        return runtime.activate(modeIdentifier: mode.id)
    }

    /// Turns off the current Focus at the user's request.
    func deactivate() -> FocusControlResult {
        guard let runtime else { return .unavailable }
        return runtime.deactivate()
    }

    static func publicSnapshot(
        authorizationStatus: INFocusStatusAuthorizationStatus,
        isFocused: Bool?
    ) -> FocusSnapshot {
        guard authorizationStatus == .authorized, let isFocused else { return .unavailable }
        return isFocused ? .active(mode: nil, availableModes: []) : .inactive(availableModes: [])
    }

    private static func currentPublicStatus() -> FocusSnapshot {
        let center = INFocusStatusCenter.default
        return publicSnapshot(
            authorizationStatus: center.authorizationStatus,
            isFocused: center.focusStatus.isFocused
        )
    }

    static func databaseSnapshot(configurationsData: Data, assertionsData: Data) -> FocusSnapshot? {
        DoNotDisturbRuntime.databaseSnapshot(
            configurationsData: configurationsData,
            assertionsData: assertionsData
        )
    }
}

// MARK: - Private framework boundary

/// The only type that loads or calls the private DoNotDisturb framework.
private final class DoNotDisturbRuntime {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb"

    private let service: NSObject?
    private var canReadService = true
    private let configurationsURL: URL
    private let assertionsURL: URL

    init(clientIdentifier: String) {
        let databaseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
        configurationsURL = databaseURL.appendingPathComponent("ModeConfigurations.json")
        assertionsURL = databaseURL.appendingPathComponent("Assertions.json")

        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let serviceType = NSClassFromString("DNDModeSelectionService") as? NSObject.Type
        else {
            service = nil
            return
        }
        let selector = NSSelectorFromString("serviceForClientIdentifier:")
        service = serviceType.responds(to: selector)
            ? serviceType.perform(selector, with: clientIdentifier)?.takeUnretainedValue() as? NSObject
            : nil
    }

    func read() -> RuntimeReadResult {
        if canReadService, service != nil {
            switch readService() {
            case let .success(snapshot): return .success(snapshot)
            case .failure: canReadService = false
            }
        }
        do {
            let configurationsData = try Data(contentsOf: configurationsURL, options: .mappedIfSafe)
            let assertionsData = try Data(contentsOf: assertionsURL, options: .mappedIfSafe)
            guard let snapshot = Self.databaseSnapshot(
                configurationsData: configurationsData,
                assertionsData: assertionsData
            ) else {
                return .failure("Focus database format was not recognized")
            }
            return .success(snapshot)
        } catch {
            return .failure("Focus database could not be read: \(error.localizedDescription)")
        }
    }

    private func readService() -> RuntimeReadResult {
        let modesResult = objectWithError(selectorName: "availableModesWithError:")
        guard modesResult.error == nil, let array = modesResult.value as? NSArray else {
            return .failure(modesResult.error?.localizedDescription ?? "available modes were not returned")
        }
        let objects = array.compactMap { $0 as? NSObject }
        let modes = objects.compactMap(Self.mode(from:))

        let assertionResult = objectWithError(selectorName: "activeModeAssertionWithError:")
        guard assertionResult.error == nil else {
            return .failure(assertionResult.error?.localizedDescription ?? "active mode was not returned")
        }
        guard let assertion = assertionResult.value else {
            return .success(.inactive(availableModes: modes))
        }
        guard let details = Self.objectProperty("details", of: assertion),
              let identifier = Self.stringProperty("modeIdentifier", of: details)
        else {
            return .failure("active assertion had no mode identifier")
        }
        return .success(.active(mode: modes.first { $0.id == identifier }, availableModes: modes))
    }

    func activate(modeIdentifier: String) -> FocusControlResult {
        guard service != nil,
              let lifetimeType = NSClassFromString("DNDModeAssertionLifetime") as? NSObject.Type,
              let detailsType = NSClassFromString("DNDModeAssertionDetails") as? NSObject.Type,
              let lifetime = Self.classObject(lifetimeType, selectorName: "lifetimeForUserRequest"),
              let details = Self.classObject(
                  detailsType,
                  selectorName: "userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:",
                  arguments: [UUID().uuidString as NSString, modeIdentifier as NSString, lifetime]
              )
        else {
            return .unavailable
        }
        return boolWithObjectAndError(selectorName: "activateModeWithDetails:error:", object: details)
    }

    func deactivate() -> FocusControlResult {
        guard service != nil else { return .unavailable }
        let assertionResult = objectWithError(selectorName: "activeModeAssertionWithError:")
        guard assertionResult.error == nil else { return .failed }
        guard let assertion = assertionResult.value else { return .applied }
        guard let identifier = Self.objectProperty("UUID", of: assertion) else { return .failed }
        return boolWithObjectAndError(selectorName: "invalidateModeAssertionWithUUID:error:", object: identifier)
    }

    private func objectWithError(selectorName: String) -> (value: NSObject?, error: NSError?) {
        guard let service else { return (nil, NSError(domain: "FocusSource", code: 1)) }
        let selector = NSSelectorFromString(selectorName)
        guard service.responds(to: selector), let implementation = service.method(for: selector) else {
            return (nil, NSError(domain: "FocusSource", code: 1))
        }
        typealias Function = @convention(c) (
            AnyObject,
            Selector,
            AutoreleasingUnsafeMutablePointer<NSError?>?
        ) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(implementation, to: Function.self)
        var error: NSError?
        let value = function(service, selector, &error)?.takeUnretainedValue() as? NSObject
        return (value, error)
    }

    private func boolWithObjectAndError(selectorName: String, object: NSObject) -> FocusControlResult {
        guard let service else { return .unavailable }
        let selector = NSSelectorFromString(selectorName)
        guard service.responds(to: selector), let implementation = service.method(for: selector) else {
            return .unavailable
        }
        typealias Function = @convention(c) (
            AnyObject,
            Selector,
            AnyObject,
            AutoreleasingUnsafeMutablePointer<NSError?>?
        ) -> Bool
        let function = unsafeBitCast(implementation, to: Function.self)
        var error: NSError?
        return function(service, selector, object, &error) && error == nil ? .applied : .failed
    }

    private static func mode(from object: NSObject) -> FocusMode? {
        guard let identifier = stringProperty("modeIdentifier", of: object),
              let name = stringProperty("name", of: object)
        else {
            return nil
        }
        return FocusMode(id: identifier, name: name, symbolName: stringProperty("symbolImageName", of: object))
    }

    static func databaseSnapshot(configurationsData: Data, assertionsData: Data) -> FocusSnapshot? {
        guard let configurationsRoot = try? JSONSerialization.jsonObject(with: configurationsData) as? [String: Any],
              (configurationsRoot["header"] as? [String: Any])?["version"] as? Int == 3,
              let configurationPartitions = configurationsRoot["data"] as? [[String: Any]],
              !configurationPartitions.isEmpty,
              let assertionsRoot = try? JSONSerialization.jsonObject(with: assertionsData) as? [String: Any],
              (assertionsRoot["header"] as? [String: Any])?["version"] as? Int == 8,
              let assertionPartitions = assertionsRoot["data"] as? [[String: Any]],
              !assertionPartitions.isEmpty
        else {
            return nil
        }

        var modesByIdentifier: [String: FocusMode] = [:]
        for partition in configurationPartitions {
            guard let configurations = partition["modeConfigurations"] as? [String: Any] else { return nil }
            for (key, value) in configurations {
                guard let configuration = value as? [String: Any],
                      let mode = configuration["mode"] as? [String: Any],
                      let identifier = mode["modeIdentifier"] as? String,
                      identifier == key,
                      let name = mode["name"] as? String,
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      modesByIdentifier[identifier] == nil
                else {
                    return nil
                }
                modesByIdentifier[identifier] = FocusMode(
                    id: identifier,
                    name: name,
                    symbolName: mode["symbolImageName"] as? String
                )
            }
        }
        let modes = modesByIdentifier.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        // Database version 8 separates active assertions from invalidation history; invalidation records can describe an inactive mode.
        let knownKeys: Set = [
            "storeAssertionRecords", "storeInvalidationRecords", "storeInvalidationRequestRecords",
            "storeLastCompleteInvalidationTimestamp", "storeLastCompleteInvalidationReason",
            "storeLastCompleteInvalidationSourceClientIdentifier",
            "storeLastCompleteInvalidationSourceDeviceIdentifier", "storeLastUpdateDate",
        ]
        var records: [[String: Any]] = []
        for partition in assertionPartitions {
            guard Set(partition.keys).isSubset(of: knownKeys), !partition.keys.isEmpty else { return nil }
            if let storedRecords = partition["storeAssertionRecords"] {
                guard let typedRecords = storedRecords as? [[String: Any]] else { return nil }
                records.append(contentsOf: typedRecords)
            }
        }
        // Accept assertion details at the record's top level or wrapped under an assertion key.
        let identifiers = records.compactMap { record -> String? in
            let assertion = record["assertion"] as? [String: Any] ?? record
            guard let details = assertion["assertionDetails"] as? [String: Any],
                  let identifier = details["assertionDetailsModeIdentifier"] as? String,
                  !identifier.isEmpty
            else {
                return nil
            }
            return identifier
        }
        guard identifiers.count == records.count else { return nil }

        guard let activeIdentifier = identifiers.first else { return .inactive(availableModes: []) }
        // Keep read-only mode metadata for the pill, but expose no controls for the unavailable service.
        let activeMode = identifiers.allSatisfy { $0 == activeIdentifier }
            ? modes.first { $0.id == activeIdentifier }
            : nil
        return .active(mode: activeMode, availableModes: [])
    }

    private static func stringProperty(_ name: String, of object: NSObject) -> String? {
        guard let value = objectProperty(name, of: object) as? NSString else { return nil }
        let text = (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func objectProperty(_ name: String, of object: NSObject) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    private static func classObject(
        _ type: NSObject.Type,
        selectorName: String,
        arguments: [NSObject] = []
    ) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard arguments.count <= 3,
              let method = class_getClassMethod(type, selector)
        else {
            return nil
        }
        let implementation = method_getImplementation(method)
        switch arguments.count {
        case 0:
            typealias Function = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            return unsafeBitCast(implementation, to: Function.self)(type, selector)?.takeUnretainedValue()
                as? NSObject
        case 3:
            typealias Function = @convention(c) (
                AnyObject, Selector, AnyObject, AnyObject, AnyObject
            ) -> Unmanaged<AnyObject>?
            return unsafeBitCast(implementation, to: Function.self)(
                type, selector, arguments[0], arguments[1], arguments[2]
            )?.takeUnretainedValue() as? NSObject
        default:
            return nil
        }
    }
}

private enum RuntimeReadResult {
    case success(FocusSnapshot)
    case failure(String)
}
