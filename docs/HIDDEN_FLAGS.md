# Thaw Hidden Diagnostic Flags

Thaw has a small number of behavioural switches that are read from
`UserDefaults` but are **not exposed in Settings**. They exist as escape
hatches for diagnosing menu-bar reorder issues on hardware or setups the
default behaviour does not handle well. Most users will never need them.

These flags are registered as ordinary cases in `Defaults.Key` (see
`Thaw/System/Defaults.swift`), so their storage goes through the same
`UserDefaults.standard` domain as every other Thaw setting. They are just
not surfaced in the UI.

## Overview

All commands below use `defaults write` against Thaw's bundle identifier,
`com.stonerl.Thaw`. Changes take effect the next time the relevant code
path runs; a relaunch of Thaw is the simplest way to guarantee that.

## Available Flags

| Key                              | Type | Default | Effect |
| --------------------------------- | ---- | ------- | ------ |
| `inputPauseThresholdMs`           | Int  | `50`    | Milliseconds of input inactivity required before a menu-bar item reorder move proceeds. Widen this if repeated cursor "kidnapping" during reordering is an issue. |
| `disableNotificationCenterBridge` | Bool | `false` | Turns off the bridge that lets a Clock click or the system shortcut open Notification Center while items are hidden. Those clicks then go to macOS untouched and do not open it until the hidden items are shown. Set this only if Clock clicks misbehave. |
| `axMessagingTimeout`              | Float | `1.0`  | Seconds an accessibility message may block before it fails, applied to every accessibility element as it is wrapped. `0` restores the system default of six seconds. |
| `useNativeAlwaysHide`             | Bool | `false` | Hides Always-Hidden items natively, by writing `NSStatusItem VisibleCC <label> = false` into the owning app's preference domain so the host stops publishing the item. It touches other apps' domains, so it stays off until validated. |
| `Thaw.debugOverflowSpacerWidth`   | Float | unset  | Width in points of a debug spacer item used to experiment with where the macOS 27 overflow chevron lands. `0` or unset removes it. Relaunch Thaw the first time you set it. |

### Usage Examples

```bash
# Widen the input-pause window to 150 ms.
defaults write com.stonerl.Thaw inputPauseThresholdMs -int 150

# Leave Clock clicks to macOS while items are hidden.
defaults write com.stonerl.Thaw disableNotificationCenterBridge -bool YES
```

To restore the default behaviour for a flag, remove the key:

```bash
defaults delete com.stonerl.Thaw inputPauseThresholdMs
```

## Notes for Contributors

- Every static (non-computed-key) `UserDefaults` flag should be registered
  as a case in `Defaults.Key`, with a raw value identical to any string
  literal previously used to read it. A raw `UserDefaults.standard` read
  with a string literal in new code should not pass review.
- These flags are deliberately hidden diagnostics, not user-facing
  settings. Do not add Settings UI for them without a separate decision
  to do so.
