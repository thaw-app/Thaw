//
//  DiagnosticLogger+Rotation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

public extension DiagnosticLogger {
    /// How log files rotate and how long they are kept: Thaw 2's settings.
    struct RotationPolicy: Equatable, Sendable {
        /// Rotate once the file reaches this size; 0 turns size rotation off.
        public var maxFileSizeBytes: UInt64
        /// Rotate this long after the file was opened; 0 turns time rotation off.
        public var rotationInterval: TimeInterval
        /// Delete files older than this many days.
        public var retentionDays: Int
        /// Never keep more files than this, so a small size limit can't pile up hundreds.
        public var maxFileCount: Int

        public init(maxFileSizeBytes: UInt64 = 0, rotationInterval: TimeInterval = 0, retentionDays: Int = 2, maxFileCount: Int = 50) {
            self.maxFileSizeBytes = maxFileSizeBytes
            self.rotationInterval = rotationInterval
            self.retentionDays = retentionDays
            self.maxFileCount = maxFileCount
        }

        /// Far above what Settings offers: they only keep stored values from overflowing.
        static let maxRetentionDays = 3650
        static let maxRetainedFileCount = 10000
        static let maxRotationInterval: TimeInterval = 365 * 86400
        static let maxSizeBytes: UInt64 = 1 << 40

        /// A negative retention or a zero count would delete every log, so each field is held in range.
        public func sanitized() -> RotationPolicy {
            var policy = self
            policy.retentionDays = min(max(1, retentionDays), Self.maxRetentionDays)
            policy.maxFileCount = min(max(1, maxFileCount), Self.maxRetainedFileCount)
            policy.maxFileSizeBytes = min(maxFileSizeBytes, Self.maxSizeBytes)
            policy.rotationInterval = rotationInterval.isFinite ? min(max(0, rotationInterval), Self.maxRotationInterval) : 0
            return policy
        }
    }
}

nonisolated extension DiagnosticLogger {
    static func shouldRotate(policy: RotationPolicy, fileSize: UInt64, openFor: TimeInterval) -> Bool {
        (policy.maxFileSizeBytes > 0 && fileSize >= policy.maxFileSizeBytes)
            || (policy.rotationInterval > 0 && openFor >= policy.rotationInterval)
    }

    /// The files retention no longer covers, newest first: older than retentionDays,
    /// or past maxCount. protected files may still be open, so they stay and count.
    static func filesToPrune(
        _ files: [(url: URL, created: Date)],
        retentionDays: Int,
        maxCount: Int,
        now: Date,
        protected: Set<URL>
    ) -> [URL] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        let cap = max(0, maxCount)
        let allowance = cap > protected.count ? cap - protected.count : 0
        let candidates = files
            .filter { !protected.contains($0.url) }
            .sorted { lhs, rhs in
                lhs.created == rhs.created ? lhs.url.path < rhs.url.path : lhs.created > rhs.created
            }
        var kept = 0
        var stale: [URL] = []
        for file in candidates {
            if file.created < cutoff || kept >= allowance {
                stale.append(file.url)
            } else {
                kept += 1
            }
        }
        return stale
    }

    /// directory/baseName.log, or baseName_2.log and on when that is taken.
    static func uniqueLogFileURL(in directory: URL, baseName: String, exists: (URL) -> Bool) -> URL {
        let base = directory.appendingPathComponent("\(baseName).log")
        guard exists(base) else { return base }
        var suffix = 2
        while exists(directory.appendingPathComponent("\(baseName)_\(suffix).log")) {
            suffix += 1
        }
        return directory.appendingPathComponent("\(baseName)_\(suffix).log")
    }
}
