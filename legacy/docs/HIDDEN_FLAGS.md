# Thaw Hidden Diagnostic Flags

Thaw has a small number of behavioural switches that are read from
`UserDefaults` but are **not exposed in Settings**. They exist as escape
hatches for diagnosing menu-bar reorder issues on hardware or setups the
default behaviour does not handle well. Most users will never need them.

These flags are registered as ordinary cases in `Defaults.Key` (see
`Thaw/Utilities/Defaults.swift`), so their storage goes through the same
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
| `discardStrayMoveEvents`          | Bool | `true`  | Whether stray echoes of synthetic move events are discarded before they can be delivered against the wrong window. Set to `NO` only if this ever misfires. |
| `failFastOnEventWindowMismatch`   | Bool | `false` | Whether a synthetic event that comes back addressed to a different window than it was posted with fails its operation immediately rather than running to timeout. Opt-in; the mismatch is always logged regardless. |

### Usage Examples

```bash
# Widen the input-pause window to 150 ms.
defaults write com.stonerl.Thaw inputPauseThresholdMs -int 150

# Disable discarding of stray move-event echoes.
defaults write com.stonerl.Thaw discardStrayMoveEvents -bool NO

# Fail fast on a window mismatch instead of waiting for a timeout.
defaults write com.stonerl.Thaw failFastOnEventWindowMismatch -bool YES
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
