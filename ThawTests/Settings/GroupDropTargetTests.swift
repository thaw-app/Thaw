//
//  GroupDropTargetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Group drop target")
struct GroupDropTargetTests {
    private let group = UUID()
    private let other = UUID()

    @Test("A row that gains the pointer becomes the target, whatever was before")
    func gainingThePointer() {
        #expect(GroupDropTarget.after(true, on: group, current: nil) == group)
        #expect(GroupDropTarget.after(true, on: group, current: other) == group)
    }

    @Test("A row that loses the pointer clears the target only if it was the target")
    func losingThePointer() {
        #expect(GroupDropTarget.after(false, on: group, current: group) == nil)
        #expect(GroupDropTarget.after(false, on: group, current: other) == other, "another row took over in the meantime")
        #expect(GroupDropTarget.after(false, on: group, current: nil) == nil)
    }
}
