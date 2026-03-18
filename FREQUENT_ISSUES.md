# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Thaw removed an item](#thaw-removed-an-item)
- [Thaw does not remember the order of items](#thaw-does-not-remember-the-order-of-items)
- [How do I solve the `Thaw cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-thaw-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)

## Items are moved to the always-hidden section

~By default, macOS adds new items to the far left of the menu bar, which is also the location of Thaw's always-hidden section. Most apps are configured
to remember the positions of their items, but some are not. macOS treats the items of these apps as new items each time they appear. This results in
these items appearing in the always-hidden section, even if they have been previously been moved.~

~Thaw does not currently manage individual items, and in fact cannot, as of the current release. Once issues
[#6](https://github.com/jordanbaird/Thaw/issues/6) and [#26](https://github.com/jordanbaird/Thaw/issues/26) are implemented, Thaw will be able to
monitor the items in the menu bar, and move the ones it recognizes to their previous locations, even if macOS rearranges them.~

This issue should be resolved with commit: [1d77308](https://github.com/stonerl/Thaw/commit/1d77308e330afc8235884931e86574eccf9d3924)

## Thaw removed an item

Thaw does not have the ability to move or remove items. It likely got placed in the always-hidden section by macOS. Option + click the Thaw icon to show
the always-hidden section, then Command + drag the item into a different section.

## Thaw does not remember the order of items

Order restoration works for single-icon apps. Apps that register multiple menu bar icons from the same process (e.g. iStat Menus, Stats, MenuMeters) are treated as opaque blocks — their internal ordering is left to macOS, but they no longer prevent other items from being restored to their saved positions.

## How do I solve the `Thaw cannot arrange menu bar items in automatically hidden menu bars` error?

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Thaw`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)
