//
//  MenuBarItemImageCacheDiskStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import ImageIO
import MenuBarModel
import os.lock
import UniformTypeIdentifiers

/// The disk half of MenuBarItemImageCache: the cache file, its format,
/// and the save queue that writes it.
///
/// Owns nothing the live cache reads; the cache decides what to persist and
/// what a load may restore.
final class MenuBarItemImageCacheDiskStore: @unchecked Sendable {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemImageCacheDiskStore")

    init() {}

    // MARK: File Location

    /// Path to the cache file in Caches directory.
    nonisolated var cacheFileURL: URL? {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return Self.cacheFileURL(
            cachesDirectory: cacheDirectory,
            bundleIdentifier: Constants.bundleIdentifier
        )
    }

    nonisolated var legacyCacheFileURL: URL? {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return Self.legacyCacheFileURL(
            cachesDirectory: cacheDirectory,
            bundleIdentifier: Constants.bundleIdentifier
        )
    }

    static nonisolated func cacheFileURL(
        cachesDirectory: URL,
        bundleIdentifier: String
    ) -> URL {
        cachesDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "imageCache.plist", directoryHint: .notDirectory)
    }

    /// The pre-plist JSON file. Read once for migration, then deleted by the
    /// next successful save; never written again.
    static nonisolated func legacyCacheFileURL(
        cachesDirectory: URL,
        bundleIdentifier: String
    ) -> URL {
        cachesDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "imageCache.json", directoryHint: .notDirectory)
    }

    // MARK: Age Policy

    /// Maximum age of a disk-cached image for items with no (or an untrusted)
    /// volatility classification (30 seconds). Classified items get longer
    /// TTLs, so a relaunch does not fall back to app icons for all of them.
    private static nonisolated let maxCacheAgeSeconds: TimeInterval = 30

    /// Maximum age for items classified occasional (10 minutes).
    private static nonisolated let occasionalCacheAgeSeconds: TimeInterval = 10 * 60

    /// Maximum age for items classified stable (7 days). An item only earns
    /// stable after 24+ consecutive unchanged observations with zero changes
    /// ever, so serving its cached glyph across relaunches is safe; the live
    /// refresh loop still replaces it the moment it actually changes.
    static nonisolated let stableCacheAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// The per-item TTL ladder.
    ///
    /// A concealed item gets the stable age: it is too rarely observed to earn
    /// a class, and an old glyph beats an app icon until the prewarm replaces it.
    nonisolated func diskCacheTTL(
        for volatility: MenuBarItemVolatilityIndex.Volatility?,
        wasConcealed: Bool = false
    ) -> TimeInterval {
        if wasConcealed {
            return Self.stableCacheAgeSeconds
        }
        return switch volatility {
        case .stable: Self.stableCacheAgeSeconds
        case .occasional: Self.occasionalCacheAgeSeconds
        case .live, .unknown, nil: Self.maxCacheAgeSeconds
        }
    }

    /// Bump when the capture/display semantics change enough that old images
    /// can be misleading. Files from another version self-delete through the
    /// version gate below and the live refresh loop refills them. This matters
    /// because concealed items keep their prior image rather than recropping,
    /// and disk entries survive "Reset all settings", so a bad persisted crop
    /// would otherwise never be replaced.
    private static nonisolated let cacheVersion = 12

    /// How long an unchanged cache may go without its file being re-stamped.
    ///
    /// The saved timestamp is what loadFromDisk() ages every entry
    /// against, so skipping the write of an unchanged cache would quietly
    /// expire entries the process knows are current. An item classified
    /// unknown carries a 30-second TTL whether or not its glyph moved. Half
    /// the shortest TTL keeps the recorded age honest while still collapsing
    /// the encode, which is the cost worth avoiding.
    private static nonisolated let timestampRefreshInterval: TimeInterval = maxCacheAgeSeconds / 2

    // MARK: Save State

    /// A save PNG-encodes the whole cache, so the question worth asking before
    /// paying for one is whether the pixels differ from what is already on
    /// disk. Image identity answers it: a pass that reads an unchanged glyph
    /// does not republish it, so an entry whose
    /// CGImage is still the same object is an entry the file already holds.
    /// The dimensions ride along because an address freed by one image and
    /// reused by the next would otherwise read as unchanged.
    private nonisolated struct DiskCacheDigest: Equatable {
        private nonisolated struct Entry: Equatable {
            let image: ObjectIdentifier
            let scale: CGFloat
            let width: Int
            let height: Int
        }

        private let entries: [String: Entry]

        init(_ snapshot: [MenuBarItemTag: MenuBarItemGlyphCapture]) {
            entries = snapshot.reduce(into: [:]) { result, element in
                result[element.key.tagIdentifier] = Entry(
                    image: ObjectIdentifier(element.value.cgImage),
                    scale: element.value.scale,
                    width: element.value.cgImage.width,
                    height: element.value.cgImage.height
                )
            }
        }
    }

    /// The save queue's own state: the newest save still owed, and what the
    /// last one actually wrote.
    ///
    /// Lock-guarded rather than queue-confined because the requesting cache
    /// folds a new request into pending from the main actor while the drain
    /// block may already be encoding on queue.
    private nonisolated struct DiskSaveState {
        /// The most recent snapshot a caller asked to be written, cleared by
        /// the drain block that takes it.
        var pending: [MenuBarItemTag: MenuBarItemGlyphCapture]?
        /// Identifiers in pending that were concealed, written as a flag
        /// on each entry.
        var pendingConcealed = Set<String>()
        /// Whether a drain block is queued or running. One is enough: it
        /// writes whatever pending holds when it gets there, so requests
        /// arriving in the meantime coalesce into that single write.
        var isDrainScheduled = false
        /// The digest and wall-clock time of the last write that landed, or
        /// nil when the file's contents are unknown to this process.
        var lastWritten: (digest: DiskCacheDigest, concealed: Set<String>, at: Date)?
    }

    private let diskSaveState = OSAllocatedUnfairLock(initialState: DiskSaveState())

    /// False after the user requests a cache reset. Protected by a lock because
    /// disk encoding runs on queue while the reset action runs on MainActor.
    private let diskPersistenceState = OSAllocatedUnfairLock(initialState: true)

    nonisolated var isEnabled: Bool {
        diskPersistenceState.withLock { $0 }
    }

    /// Serial queue for disk I/O. Background QoS: nothing on screen waits for a
    /// save, and serialization is what makes the reset barrier in
    /// suspendForReset() reliable.
    private let queue = DispatchQueue(
        label: "MenuBarItemImageCacheDiskStore",
        qos: .background
    )

    // MARK: Saving

    /// Parks the newest snapshot and schedules the one drain that writes it.
    ///
    /// Requests coalesce: several passes can finish while one encode is still
    /// on the queue, so only the newest snapshot is parked, and a single drain
    /// block writes whichever one is parked when it runs.
    nonisolated func enqueueSave(
        _ snapshot: [MenuBarItemTag: MenuBarItemGlyphCapture],
        concealedIdentifiers: Set<String> = []
    ) {
        guard isEnabled, !snapshot.isEmpty else { return }
        guard let url = cacheFileURL else { return }
        // The file locations are resolved before parking, so the drain block
        // never has to reach for the search API from the queue.
        let legacyURL = legacyCacheFileURL

        let needsDrain = diskSaveState.withLock { state -> Bool in
            state.pending = snapshot
            state.pendingConcealed = concealedIdentifiers
            guard !state.isDrainScheduled else { return false }
            state.isDrainScheduled = true
            return true
        }
        guard needsDrain else { return }

        queue.async {
            self.drainPendingSave(to: url, legacyURL: legacyURL)
        }
    }

    /// Writes the parked snapshot, on queue.
    ///
    /// A cache that has not changed since the last write costs nothing here,
    /// unless its file has been sitting long enough for the recorded age to
    /// start mattering, in which case it needs a new timestamp and nothing
    /// else. Only a cache that actually changed pays for the encode.
    private nonisolated func drainPendingSave(to url: URL, legacyURL: URL?) {
        let (snapshot, concealed) = diskSaveState.withLock { state in
            state.isDrainScheduled = false
            defer {
                state.pending = nil
                state.pendingConcealed = []
            }
            return (state.pending, state.pendingConcealed)
        }
        guard let snapshot, !snapshot.isEmpty, isEnabled else { return }

        let digest = DiskCacheDigest(snapshot)
        let now = Date()
        let unchangedSince = diskSaveState.withLock { state -> Date? in
            guard let last = state.lastWritten, last.digest == digest, last.concealed == concealed else {
                return nil
            }
            return last.at
        }

        if let unchangedSince {
            guard now.timeIntervalSince(unchangedSince) >= Self.timestampRefreshInterval else {
                return
            }
            if restampCacheFile(at: url, to: now) {
                diskSaveState.withLock { $0.lastWritten = (digest, concealed, now) }
                return
            }
            // The re-stamp could not read back what it was told is there, so
            // the recorded digest is describing a file this process no longer
            // knows. Fall through and write the whole thing.
        }

        let cacheData = snapshot.map { tag, image -> (String, Data, CGFloat)? in
            let png = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    png, UTType.png.identifier as CFString, 1, nil
                )
            else { return nil }
            CGImageDestinationAddImage(destination, image.cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }

            let tagString = tag.tagIdentifier
            return (tagString, png as Data, image.scale)
        }.compactMap(\.self)

        guard cacheData.count == snapshot.count else { return }
        guard isEnabled else { return }

        do {
            let directoryURL = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            // Binary property list, not JSON: PNG bytes are stored as
            // native plist Data instead of base64 strings, dropping the
            // ~33% base64 inflation and the base64 encode/decode of every
            // image on each save/load.
            // The persistable-capture collapse already guarantees one entry
            // per identifier; uniquingKeysWith keeps a future collision a
            // last-one-wins overwrite rather than a trap on this queue.
            let images: [String: [String: Any]] = Dictionary(
                cacheData.map { identifier, png, scale in
                    var entry: [String: Any] = ["png": png, "scale": scale]
                    if concealed.contains(identifier) {
                        entry["concealed"] = true
                    }
                    return (identifier, entry)
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let writtenAt = Date()
            let plist: [String: Any] = [
                "version": Self.cacheVersion,
                "timestamp": writtenAt.timeIntervalSince1970,
                "images": images,
            ]
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .binary,
                options: 0
            )
            try plistData.write(to: url)

            // The old JSON file is superseded; drop it so the stale copy
            // cannot sit in Caches indefinitely.
            if let legacyURL {
                try? FileManager.default.removeItem(at: legacyURL)
            }

            diskSaveState.withLock { $0.lastWritten = (digest, concealed, writtenAt) }
            Self.diagLog.debug("Saved \(cacheData.count) images to disk cache")
        } catch {
            // Leave lastWritten alone: the file is not what this digest
            // describes, so the next request must encode rather than skip.
            Self.diagLog.error("Failed to save image cache to disk: \(error)")
        }
    }

    /// Rewrites an unchanged cache file's timestamp, on queue.
    ///
    /// Reads the plist back and replaces one key rather than rebuilding it.
    /// The PNG bytes travel as opaque Data either way, so this costs a file
    /// round trip against the whole-cache encode it stands in for. Returns
    /// false when the file is gone or was written by another version, which
    /// leaves the caller to write it out in full.
    private nonisolated func restampCacheFile(at url: URL, to date: Date) -> Bool {
        guard let fileData = try? Data(contentsOf: url),
              var root = try? PropertyListSerialization.propertyList(
                  from: fileData,
                  format: nil
              ) as? [String: Any],
              root["version"] as? Int == Self.cacheVersion,
              root["images"] != nil
        else {
            return false
        }
        root["timestamp"] = date.timeIntervalSince1970
        guard let plistData = try? PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        ) else {
            return false
        }
        do {
            try plistData.write(to: url)
        } catch {
            Self.diagLog.error("Failed to re-stamp disk image cache: \(error)")
            return false
        }
        return true
    }

    /// Blocks queued and future saves while a reset deletes the cache file,
    /// and forgets the parked write so a later save cannot skip recreating it.
    nonisolated func suspendForReset() async {
        diskPersistenceState.withLock { $0 = false }
        diskSaveState.withLock { state in
            state.pending = nil
            state.lastWritten = nil
        }
        await withCheckedContinuation { continuation in
            self.queue.async {
                continuation.resume()
            }
        }
    }

    /// Restores normal persistence when cache deletion fails and the app stays
    /// running to present the maintenance error.
    nonisolated func resumeAfterFailedReset() {
        diskPersistenceState.withLock { $0 = true }
    }

    // MARK: Loading

    /// The decoded shell of a save file: its entries, how old the save is,
    /// and whether it came from the pre-plist JSON.
    nonisolated struct SaveFileContents {
        let entries: [String: [String: Any]]
        let age: TimeInterval
        let isLegacyJSON: Bool
    }

    /// Reads the save file, deleting it when another version wrote it or every
    /// classification it could serve has expired; reads the legacy JSON once.
    nonisolated func readSaveFile() -> SaveFileContents? {
        guard let url = cacheFileURL, let legacyURL = legacyCacheFileURL else {
            return nil
        }
        let readFile: URL
        let isLegacyJSON: Bool
        if FileManager.default.fileExists(atPath: url.path) {
            readFile = url
            isLegacyJSON = false
        } else if FileManager.default.fileExists(atPath: legacyURL.path) {
            readFile = legacyURL
            isLegacyJSON = true
        } else {
            return nil
        }

        do {
            let fileData = try Data(contentsOf: readFile)
            let root: [String: Any] = if isLegacyJSON {
                try JSONSerialization.jsonObject(with: fileData) as? [String: Any] ?? [:]
            } else {
                try PropertyListSerialization.propertyList(
                    from: fileData,
                    format: nil
                ) as? [String: Any] ?? [:]
            }
            guard let timestamp = root["timestamp"] as? TimeInterval,
                  let imagesDict = root["images"] as? [String: [String: Any]] else { return nil }

            if root["version"] as? Int != Self.cacheVersion {
                let version = root["version"] as? Int
                Self.diagLog.debug("Disk cache version \(version ?? -1) is stale, deleting cache")
                try? FileManager.default.removeItem(at: readFile)
                return nil
            }

            // A file older than the most generous TTL cannot serve anything.
            let age = Date().timeIntervalSince1970 - timestamp
            if age > Self.stableCacheAgeSeconds {
                Self.diagLog.debug("Disk cache is \(Int(age))s old, deleting stale cache")
                try? FileManager.default.removeItem(at: readFile)
                return nil
            }

            return SaveFileContents(entries: imagesDict, age: age, isLegacyJSON: isLegacyJSON)
        } catch {
            Self.diagLog.error("Failed to load image cache from disk: \(error)")
            return nil
        }
    }

    /// Decodes one file entry into a capture, or nil when its pixels cannot
    /// be read.
    nonisolated func decodeEntry(_ entry: [String: Any], legacyJSON: Bool) -> MenuBarItemGlyphCapture? {
        // The plist stores PNG bytes natively; the legacy JSON stored them
        // base64-encoded. JSONSerialization hands back Double for the stored
        // scale, never CGFloat, so cast through it either way.
        let pngData: Data? = if legacyJSON {
            (entry["png"] as? String).flatMap { Data(base64Encoded: $0) }
        } else {
            entry["png"] as? Data
        }
        guard let scale = entry["scale"] as? Double,
              let data = pngData,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return MenuBarItemGlyphCapture(cgImage: cgImage, scale: CGFloat(scale))
    }
}
