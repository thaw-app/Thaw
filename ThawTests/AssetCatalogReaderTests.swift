//
//  AssetCatalogReaderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class AssetCatalogReaderTests: XCTestCase {
    // MARK: - Manifest Tests

    func testManifestLoadsSuccessfully() {
        // The manifest should load from AppIcons.json bundled with the app
        let manifest = AssetCatalogReader.manifest

        // Should not be empty if AppIcons.json exists and is valid
        // Note: This test will fail if AppIcons.json is missing or malformed
        XCTAssertFalse(manifest.isEmpty, "Manifest should load at least one app mapping")
    }

    func testManifestContainsExpectedStructure() {
        let manifest = AssetCatalogReader.manifest

        // Pick any entry and verify it has the expected structure
        if let (bundleID, mapping) = manifest.first {
            XCTAssertFalse(bundleID.isEmpty, "Bundle ID should not be empty")
            XCTAssertFalse(mapping.defaultIcon.isEmpty, "Default icon should not be empty")
            // allowPersonalization, hint, and forceTemplate are optional
        }
    }

    // MARK: - Override Tests

    private let testBundleID = "com.test.assetcatalogreader.testapp"
    private let testIconName = "TestStatusBarIcon"

    override func tearDown() {
        // Clean up any test overrides
        AssetCatalogReader.setOverride(nil, for: testBundleID)
        super.tearDown()
    }

    func testSetOverrideAddsEntry() {
        // Ensure clean state
        AssetCatalogReader.setOverride(nil, for: testBundleID)
        XCTAssertNil(AssetCatalogReader.overrides[testBundleID])

        // Set override
        AssetCatalogReader.setOverride(testIconName, for: testBundleID)

        // Verify it was added
        XCTAssertEqual(AssetCatalogReader.overrides[testBundleID], testIconName)
    }

    func testSetOverrideRemovesEntryWhenNil() {
        // Set an override first
        AssetCatalogReader.setOverride(testIconName, for: testBundleID)
        XCTAssertNotNil(AssetCatalogReader.overrides[testBundleID])

        // Remove it by setting nil
        AssetCatalogReader.setOverride(nil, for: testBundleID)

        // Verify it was removed
        XCTAssertNil(AssetCatalogReader.overrides[testBundleID])
    }

    func testSetOverrideUpdatesExistingEntry() {
        let newIconName = "UpdatedIcon"

        // Set initial override
        AssetCatalogReader.setOverride(testIconName, for: testBundleID)
        XCTAssertEqual(AssetCatalogReader.overrides[testBundleID], testIconName)

        // Update it
        AssetCatalogReader.setOverride(newIconName, for: testBundleID)

        // Verify it was updated
        XCTAssertEqual(AssetCatalogReader.overrides[testBundleID], newIconName)
    }

    func testOverridesPersistAcrossAccesses() {
        // Set override
        AssetCatalogReader.setOverride(testIconName, for: testBundleID)

        // Access overrides multiple times
        let firstAccess = AssetCatalogReader.overrides[testBundleID]
        let secondAccess = AssetCatalogReader.overrides[testBundleID]

        XCTAssertEqual(firstAccess, secondAccess)
        XCTAssertEqual(firstAccess, testIconName)
    }

    func testOverridesDefaultsToEmptyDictionary() {
        // Use a unique key that definitely doesn't exist
        let uniqueBundleID = "com.test.nonexistent.\(UUID().uuidString)"

        // Should return nil for non-existent keys, not crash
        XCTAssertNil(AssetCatalogReader.overrides[uniqueBundleID])
    }

    // MARK: - AppMapping Structure Tests

    func testAppMappingDecoding() throws {
        let json = """
        {
            "defaultIcon": "StatusBarIcon",
            "allowPersonalization": true,
            "hint": "status",
            "forceTemplate": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let mapping = try JSONDecoder().decode(AppMapping.self, from: data)

        XCTAssertEqual(mapping.defaultIcon, "StatusBarIcon")
        XCTAssertEqual(mapping.allowPersonalization, true)
        XCTAssertEqual(mapping.hint, "status")
        XCTAssertEqual(mapping.forceTemplate, false)
    }

    func testAppMappingDecodingWithOptionalFieldsMissing() throws {
        let json = """
        {
            "defaultIcon": "MinimalIcon"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let mapping = try JSONDecoder().decode(AppMapping.self, from: data)

        XCTAssertEqual(mapping.defaultIcon, "MinimalIcon")
        XCTAssertNil(mapping.allowPersonalization)
        XCTAssertNil(mapping.hint)
        XCTAssertNil(mapping.forceTemplate)
    }
}
