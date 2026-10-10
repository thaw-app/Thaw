//
//  BundledStatusIcon.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Bundle images provide icons for items that never appear on the bar and cannot be captured.
/// List small images for manual selection; automatically pick only status-like names without app-specific rules.
enum BundledStatusIcon {
    struct Candidate: Identifiable {
        /// The file name or asset name, which is also how it is shown.
        let name: String
        let image: NSImage
        /// A file in Resources rather than an asset catalog entry.
        let isLoose: Bool
        var id: String {
            name
        }
    }

    /// A name that reads as a status item image, listed first in the picker.
    private static let statusName = /(?i)(status|menu.?bar|tray)/

    /// A name that can only mean the status item image, safe to pick without
    /// asking: StatusBarIcon, statusIconTemplate, <App>Status, MenuBarImage.
    private static let statusItemName = /(?i)(status.?(bar|item|icon)|status(template)?$|menu.?bar|tray)/

    /// A loose file named as the app's small icon, like fluxicon.tiff.
    private static let iconName = /(?i)icon/

    /// Heights in points that fit a menu bar slot, with room for a 2x asset
    /// that reports its pixel size.
    private static let pointHeights: ClosedRange<CGFloat> = 10 ... 48

    /// How many images a picker lists, so a large catalog stays browsable.
    private static let candidateLimit = 240

    @MainActor
    private static var candidateCache: [URL: [Candidate]] = [:]

    /// Pick a status-named candidate or loose icon file; leave uncertain matches to the user.
    @MainActor
    static func image(forBundleAt url: URL?) -> NSImage? {
        let candidates = candidates(forBundleAt: url)
        return (candidates.first { $0.name.contains(statusItemName) }
            ?? candidates.first { $0.isLoose && $0.name.contains(iconName) })?.image
    }

    /// Every small image the app ships, status-named ones first.
    @MainActor
    static func candidates(forBundleAt url: URL?) -> [Candidate] {
        guard let url else { return [] }
        if let cached = candidateCache[url] {
            return cached
        }
        let found = find(in: url)
        candidateCache[url] = found
        return found
    }

    private static func find(in bundleURL: URL) -> [Candidate] {
        guard let bundle = Bundle(url: bundleURL) else { return [] }
        let appIconNames = Set(
            [
                bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            ]
            .compactMap { $0.map { ($0 as NSString).deletingPathExtension.lowercased() } }
        )
        var seen = Set<String>()
        var result = [Candidate]()
        let looseNames = looseImageNames(in: bundle)
        for name in looseNames + CoreUICatalog.imageNames(in: bundle) {
            let key = (name as NSString).deletingPathExtension.lowercased()
            guard !appIconNames.contains(key), !key.contains("appicon"), seen.insert(key).inserted else { continue }
            guard let image = bundle.image(forResource: name) ?? looseImage(named: name, in: bundle),
                  fitsMenuBar(image)
            else { continue }
            markTemplateIfSingleInk(image)
            result.append(Candidate(name: name, image: image, isLoose: looseNames.contains(name)))
            if result.count >= candidateLimit {
                break
            }
        }
        return result.sorted { lhs, rhs in
            let lhsItem = lhs.name.contains(statusItemName), rhsItem = rhs.name.contains(statusItemName)
            if lhsItem != rhsItem {
                return lhsItem
            }
            let lhsStatus = lhs.name.contains(statusName), rhsStatus = rhs.name.contains(statusName)
            if lhsStatus != rhsStatus {
                return lhsStatus
            }
            if lhs.image.isTemplate != rhs.image.isTemplate {
                return lhs.image.isTemplate
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Image files in Resources itself, not in a localization.
    private static func looseImageNames(in bundle: Bundle) -> [String] {
        guard let resources = bundle.resourceURL,
              let files = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { ["png", "pdf", "tiff", "tif"].contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
    }

    private static func looseImage(named name: String, in bundle: Bundle) -> NSImage? {
        bundle.resourceURL.flatMap { NSImage(contentsOf: $0.appending(path: name)) }
    }

    /// Files omit code-assigned template flags; infer them for single-grey-ink images while preserving coloured icons.
    private static func markTemplateIfSingleInk(_ image: NSImage) {
        guard !image.isTemplate,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil,
                  width: cgImage.width,
                  height: cgImage.height,
                  bitsPerComponent: 8,
                  bytesPerRow: cgImage.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let data = context.data
        else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: cgImage.width * cgImage.height * 4)
        var inked = 0
        for index in stride(from: 0, to: cgImage.width * cgImage.height * 4, by: 4) where pixels[index + 3] > 32 {
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            guard max(red, green, blue) - min(red, green, blue) <= 24 else { return }
            inked += 1
        }
        image.isTemplate = inked > 0
    }

    /// A menu bar slot's height, and no wider than a short title.
    private static func fitsMenuBar(_ image: NSImage) -> Bool {
        let size = image.size
        guard pointHeights.contains(size.height) else { return false }
        return size.width / size.height <= 3
    }
}

/// AppKit cannot list catalog names, so use the private CoreUI reader; failures leave only loose-file candidates.
private enum CoreUICatalog {
    private typealias InitWithURL = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutablePointer<NSError?>?) -> AnyObject?

    private static let catalogClass: NSObject.Type? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW) != nil else {
            return nil
        }
        return NSClassFromString("CUICatalog") as? NSObject.Type
    }()

    static func imageNames(in bundle: Bundle) -> [String] {
        guard let catalogClass,
              let url = bundle.url(forResource: "Assets", withExtension: "car")
        else { return [] }
        let initSelector = NSSelectorFromString("initWithURL:error:")
        let namesSelector = NSSelectorFromString("allImageNames")
        guard let allocated = catalogClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              allocated.responds(to: initSelector),
              let implementation = allocated.method(for: initSelector)
        else { return [] }
        var error: NSError?
        let initialize = unsafeBitCast(implementation, to: InitWithURL.self)
        guard let catalog = initialize(allocated, initSelector, url as NSURL, &error) as? NSObject,
              catalog.responds(to: namesSelector)
        else { return [] }
        return catalog.value(forKey: "allImageNames") as? [String] ?? []
    }
}
