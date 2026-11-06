//
//  ProjectLinksTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

struct ProjectLinksTests {
    @Test("About links stay in the configured repository", arguments: [
        "blob/development/FREQUENT_ISSUES.md",
        "graphs/contributors",
        "blob/development/CREDITS.md",
    ])
    func aboutLinks(path: String) throws {
        let links = [
            "blob/development/FREQUENT_ISSUES.md": Constants.frequentIssuesURL,
            "graphs/contributors": Constants.contributorsURL,
            "blob/development/CREDITS.md": Constants.translatorsURL,
        ]
        let url = try #require(links[path])
        #expect(url.scheme == "https")
        #expect(url.host() == Constants.repositoryURL.host())
        #expect(url.path() == Constants.repositoryURL.path() + "/" + path)
        #expect(url.query() == nil)
        #expect(url.fragment() == nil)
    }
}
