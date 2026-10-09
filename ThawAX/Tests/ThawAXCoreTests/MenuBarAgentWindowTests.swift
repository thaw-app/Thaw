//
//  MenuBarAgentWindowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import ThawAXCore

struct MenuBarAgentWindowTests {
    private func entry(_ pid: pid_t, x: CGFloat = 100, width: CGFloat = 24) -> MenuBarAgentWindow.Entry {
        .init(ownerPID: pid, frame: CGRect(x: x, y: 0, width: width, height: 30))
    }

    @Test
    func `names each app once, however many items it has on the bar`() {
        let owners = MenuBarAgentWindow.drawnOwners(in: [entry(10), entry(10, x: 140), entry(20), entry(30)])
        #expect(owners == [10, 20, 30])
    }

    @Test
    func `counts a one point divider as drawn`() {
        #expect(MenuBarAgentWindow.drawnOwners(in: [entry(10, width: 1), entry(20)]) == [10, 20])
    }

    @Test
    func `refuses a read holding the empty child a departing item leaves behind`() {
        let leaving = MenuBarAgentWindow.Entry(ownerPID: 1, frame: .zero)
        #expect(MenuBarAgentWindow.drawnOwners(in: [entry(10), leaving, entry(20)]) == nil)
    }

    @Test
    func `refuses an empty read`() {
        #expect(MenuBarAgentWindow.drawnOwners(in: []) == nil)
    }

    /// A stand-in for an accessibility element: who owns it and what is under it.
    private final class Node {
        let pid: pid_t?
        let kids: [Node]
        var wasAskedForChildren = false
        init(_ pid: pid_t?, _ kids: [Node] = []) {
            self.pid = pid
            self.kids = kids
        }
    }

    private func owner(of child: Node, agent: pid_t = 1) -> pid_t {
        MenuBarAgentWindow.ownerPID(of: child, agentPID: agent, pid: { $0.pid }, children: {
            $0.wasAskedForChildren = true
            return $0.kids
        })
    }

    @Test
    func `the owner is the first element under the wrappers that is not the agent's`() {
        let button = Node(42)
        #expect(owner(of: Node(1, [Node(1, [button])])) == 42)
    }

    @Test
    func `the item itself is never asked for its children`() {
        // An item of this app's own is answered on the calling thread; asking it anything from a background walk crashed.
        let inside = Node(42)
        let button = Node(42, [inside])
        let wrapper = Node(1, [button])
        #expect(owner(of: wrapper) == 42)
        #expect(wrapper.wasAskedForChildren)
        #expect(!button.wasAskedForChildren)
        #expect(!inside.wasAskedForChildren)
    }

    @Test
    func `one of Apple's own items, owned by the agent all the way down, belongs to the agent`() {
        #expect(owner(of: Node(1, [Node(1, [Node(1)])])) == 1)
    }

    @Test
    func `a child that is itself another app's element is that app's`() {
        let child = Node(42, [Node(7)])
        #expect(owner(of: child) == 42)
        #expect(!child.wasAskedForChildren)
    }

    @Test
    func `an element whose owner cannot be read counts as the agent's`() {
        #expect(owner(of: Node(1, [Node(nil, [Node(42)])])) == 1)
    }
}
