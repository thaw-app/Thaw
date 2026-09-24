# Changelog

All notable changes to Thaw 1.x (macOS 14 and 15) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Thaw 2.0 and later (macOS 26) keep their own changelog on `development`.

## [1.3.0] - Unreleased

**macOS 14 and 15 · Build 32**

A bug-fix release for the 1.x line. Clicking a hidden item in the Thaw Bar opens its menu again on macOS 15.

### Fixes

1. **Hidden items open their menus again.** On macOS 15, clicking a hidden item in the Thaw Bar made the Thaw icon shake, and the item's menu never opened. Thaw started each move drag at the destination, so macOS delivered it to Thaw's own icon instead of the hidden item. The drag now starts off-screen, so it reaches the item. [#748](https://github.com/thaw-app/Thaw/issues/748)
2. **Clicks stay fast after many uses.** After about ten clicks, a clash between a click and the timer that hides items again could leave every later move and click waiting out a 5-second timeout. Clicks landed 30–45 seconds late. They now open in about a quarter of a second.
3. **No more runaway logging with a menu open.** With a menu open, Thaw could reschedule its hide timer about once per millisecond, writing over 100,000 log lines in a few minutes.
4. **Reliable reveal under load.** Revealing a hidden item from the Thaw Bar waits for the bar to close instead of a fixed delay. When the item doesn't reach its spot, Thaw no longer clicks where it isn't, and it still puts the item back afterwards.
5. **Synthetic clicks no longer trigger hot corners.** Moving the cursor for a click could pass through a screen corner and set off a hot corner. The cursor is also restored more reliably afterwards.

### New

- **Keep cursor on clicked item.** A new option under Settings > Advanced > Other, off by default. After a Thaw Bar click, the cursor moves to where the item's menu just opened, over its first row, instead of going back to where it was.
