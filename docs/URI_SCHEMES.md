# Thaw URI Schemes & Deep Linking

Trigger Thaw actions and read/write settings from `thaw://` URLs. Use it with Raycast, Alfred, Shortcuts, or shell scripts.

Thaw registers the `thaw://` scheme in `Info.plist` (`CFBundleURLTypes`).

## thaw:// URL Scheme

### Supported Actions

| URL                               | Action                | Description                              |
| --------------------------------- | --------------------- | ---------------------------------------- |
| `thaw://toggle-hidden`            | Toggle Hidden Section | Shows/hides the hidden menu bar section  |
| `thaw://toggle-always-hidden`     | Toggle Always-Hidden  | Shows/hides the always-hidden section    |
| `thaw://search`                   | Open Search Panel     | Displays the menu bar item search panel  |
| `thaw://toggle-swap`              | Toggle Swap           | Trades the shown and hidden items; a second call trades them back |
| `thaw://toggle-thawbar`           | Toggle Thaw Bar       | Toggles the Thaw Bar on the active display and saves it; needs Settings URI on and an approved app |
| `thaw://toggle-application-menus` | Toggle App Menus      | Shows/hides application menus            |
| `thaw://toggle-zen-mode`          | Toggle Zen Mode       | Turns Zen Mode on or off. Zen Mode locks reveal gestures and conceals sections until toggled back |
| `thaw://toggle-layout-editor`     | Toggle Layout Editor  | Opens or closes the Layout editor        |
| `thaw://item-hints`               | Item Hints            | Puts a letter under every menu bar item; typing a letter opens that item |
| `thaw://open-settings`            | Open Settings         | Opens the Thaw settings window           |
| `thaw://authorize`                | Authorize App         | Triggers auth dialog to grant an app whitelist access to settings |

### Usage Examples

```bash
open "thaw://toggle-hidden"
open "thaw://search"
open "thaw://open-settings"
```

```swift
NSWorkspace.shared.open(URL(string: "thaw://search")!)
```

```applescript
tell application "System Events"
    open location "thaw://toggle-hidden"
end tell
```

### Raycast Integration

Quicklink: create one with link `thaw://toggle-hidden` and assign a hotkey (e.g. `⌃⌥⌘H`).

Script command with a dropdown:

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Thaw Actions
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Action", "data": [{"title": "Toggle Hidden", "value": "toggle-hidden"}, {"title": "Search", "value": "search"}, {"title": "Settings", "value": "open-settings"}] }

open "thaw://${1}"
```

### Alfred Workflow

Add an `Open URL` object with `thaw://toggle-hidden` and connect it to a hotkey trigger.

## Info.plist URLs

Internal URLs configured in `Thaw/Resources/Info.plist`:

| Key                                   | Value                                 | Description                          |
| ------------------------------------- | ------------------------------------- | ------------------------------------ |
| `ThawRepositoryURL`                   | `https://github.com/thaw-app/Thaw`    | GitHub repository                    |
| `ThawDonateURL`                       | `https://github.com/sponsors/stonerl` | Sponsorship page                     |
| `ThawFloeURL`                         | `https://github.com/thaw-app/Floe`    | Floe, linked from About              |
| `ThawMenuBarItemSpacingExecutableURI` | `file:///usr/bin/env`                 | Executable path for spacing commands |

## System URLs

macOS Settings URLs Thaw opens:

| URL                                                                             | Opens                     |
| ------------------------------------------------------------------------------- | ------------------------- |
| `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` | Accessibility settings    |
| `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` | Screen Recording settings |

## Settings URI

Read and write Thaw settings via `thaw://` URLs, gated by a security whitelist. Automation tools like Droppy use this to control Thaw settings.

### Security Model

1. Feature toggle: Settings URI is disabled by default (enable in Settings → Privacy)
2. Whitelist: only approved apps can modify settings
3. First-time authorization: new apps trigger a confirmation dialog with app name and permissions. Apps can proactively request authorization via `thaw://authorize` without reading or writing settings
4. Silent failures: unauthorized requests fail without user interruption
5. Signature pinning: the sending app is identified by its own code signature, not only by its bundle ID. An approval is tied to the app's signing team, or for an app signed without a team, to that exact build, so a rebuilt unsigned app is asked again
6. Diagnostics: `thaw://proxy-press` and `thaw://dump-items` need the same switch and approval. `dump-items` writes its report to `~/Library/Logs/Thaw` and sends the report path only to a `callback` whose URL scheme the requesting app handles itself, never to a web address

### Supported Settings Keys

#### Global Settings (All Displays)

| Key                                       | Type | Description                                  |
| ----------------------------------------- | ---- | -------------------------------------------- |
| `autoRehide`                              | Bool | Hide shown items again; `false` is Never in Hide items again |
| `showOnClick`                             | Bool | Show hidden items when clicking the menu bar |
| `showOnHover`                             | Bool | Show hidden items on hover                   |
| `showOnScroll`                            | Bool | Show hidden items on scroll                  |
| `showAlwaysHiddenOnIconDoubleClick`       | Bool | Double-click the Thaw icon to show always-hidden items (default: true) |
| `useThawBarOnlyOnNotchedDisplay`          | Bool | Thaw Bar only on Macs with notch             |
| `useThawBarOnNotchOverflow`               | Bool | Open items the notch pushes out in the Thaw Bar (default: true) |
| `thawBarLocationOnHotkey`                 | Bool | When opened by a shortcut: `true` is "Centered on the pointer", `false` is "Use Location" |
| `lockThawBarPosition`                     | Bool | Keep the Thaw Bar where it opens; `false` lets you drag it by its background (default: true) |
| `openHiddenItemsInMenuBar`                | Bool | Show an item opened from the Thaw Bar or search in the menu bar and open its menu under its icon |
| `hideApplicationMenus`                    | Bool | Hide application menu titles                 |
| `enableDesktopMenuHiding`                 | Bool | Cover the Finder's menu titles while the desktop is frontmost |
| `enableAlwaysHiddenSection`               | Bool | Enable the always-hidden section             |
| `enableSecondaryContextMenu`              | Bool | Right-click shows alternate menu             |
| `showAllSectionsOnUserDrag`               | Bool | Reveal all sections during drag              |
| `showMenuBarTooltips`                     | Bool | Show hover tooltips on menu bar items        |
| `enableMenuBarItemDescenders`             | Bool | Show a small readout below a menu bar item while the pointer rests on it |
| `enableDiagnosticLogging`                 | Bool | Enable debug logging                         |
| `customThawIconIsTemplate`                | Bool | Custom icon renders as template              |
| `showThawIcon`                            | Bool | Show the Thaw icon in menu bar               |
| `simpleMode`                              | Bool | Show only the essential settings in Settings |
| `showSettingDescriptions`                 | Bool | Explain each setting beneath it in Settings (default: true) |
| `showDockIconWithSettings`                | Bool | Show the Dock icon while Settings is open (default: true) |
| `enableMenuBarItemOverflow`               | Bool | Eject items that would fall behind the notch |
| `enableExperimentalOverflowPrevention`    | Bool | Experimental. Give hidden items extreme weights so native overflow collapses them first on notched displays. Not in Settings |
| `enableExperimentalSystemItemHiding`      | Bool | Read-only. `true` when the hiding method can hide Apple's own items |
| `alwaysUseAppIconForMenuBarItems`         | Bool | Show each item's app icon in the Thaw Bar and Layout instead of a live screenshot |
| `enableSwapBar`                           | Bool | Show the Swap Bar, a strip under the menu bar that trades shown and hidden items in one click |
| `swapOnThawIconClick`                     | Bool | Clicking the Thaw icon swaps shown and hidden items |
| `enableControlItemPanel`                  | Bool | Right-click the Thaw icon for a panel of controls instead of a text menu |
| `showSpaceIndicator`                      | Bool | Add a menu bar item with the name of the current Space |
| `enableRecordingWatch`                    | Bool | Show a short notice when the camera or microphone turns on |
| `zenModeWhileRecording`                   | Bool | Turn on Zen Mode while any app uses the camera or microphone |
| `autoZenWhileSharingScreen`               | Bool | Turn on Zen Mode while you share your screen or mirror a display |
| `fetchReleaseNotes`                       | Bool | Fetch the latest release notes when you open What's New (default: true) |
| `showReleaseNotesAfterUpdate`             | Bool | Open What's New the first time Thaw starts after an update (default: true) |

Older Ice-era names still work: `showIceIcon`, `customIceIconIsTemplate`, `useIceBarOnlyOnNotchedDisplay`, `iceBarLocationOnHotkey`, `useIceBar`, `iceBarLocation` and `iceBarLayout` are accepted for `showThawIcon`, `customThawIconIsTemplate`, `useThawBarOnlyOnNotchedDisplay`, `thawBarLocationOnHotkey`, `useThawBar`, `thawBarLocation` and `thawBarLayout`. Responses use the current names.

#### Double/Time Interval Settings

| Key                      | Type | Range | Description |
| ------------------------ | ---- | ----- | ----------- |
| `rehideInterval`         | Double | 1-300 seconds | The delay for After N seconds in Hide items again (default: 15) |
| `tempShowInterval`       | Double | 0-30 seconds | Keep opened items in the menu bar for: how long an item opened from search or the Thaw Bar stays (default: 15) |
| `showOnHoverDelay`       | Double | 0-5 seconds | Delay before hover reveals items (default: 0.2) |
| `tooltipDelay`           | Double | 0-5 seconds | Delay before showing tooltips (default: 0.5) |
| `iconRefreshInterval`    | Double | 0-5 seconds | Interval between icon refreshes in panels; `0` means Off (default: 0.25) |
| `menuBarOrderFulfillmentTimeout` | Double | 1-15 seconds | How long Thaw waits for the system to apply a menu bar reorder before it carries on (default: 3). The Layout setting for it is hidden because the timeout has no effect on macOS 27 |

Values outside the valid range are clamped to the nearest boundary.

#### Enum Settings

| Key            | Type | Valid Values | Description |
| -------------- | ---- | ------------ | ----------- |
| `rehideStrategy` | String/Int | `smart` (0), `timed` (1), `focusedApp`/`focused_app` (2) | Hide items again: When I click elsewhere (`smart`), After N seconds (`timed`) or When I switch apps (`focusedApp`) (default: smart) |
| `settingsAppearance` | String/Int | `system` (3), `light` (0), `dark` (1), `black` (2) | How Settings and onboarding look. `system` follows macOS. Black is dark on pure black, for OLED displays |

The older `blackSettingsBackground` boolean still works: `true` chooses Black, and `false` changes Black to Dark and leaves Light and Dark alone.

#### Per-Display Settings

These settings affect specific displays based on context. The **Scope** column is the default; `display=<UUID>` overrides it to target one display by UUID and fails silently if that display is not connected.

| Key                      | Type | Scope | Description |
| ------------------------ | ---- | ----- | ----------- |
| `useThawBar`              | Bool | Active display only | Enable/disable Thaw Bar on the display with the active menu bar |
| `useThawBarForAlwaysHidden` | Bool | All displays without Thaw Bar | Open only the always-hidden section in the Thaw Bar, leaving hidden items to expand inline |
| `thawBarLocation`         | String | All displays with Thaw Bar enabled | Where the Thaw Bar opens: `dynamic` (Pointer or Thaw icon), `mousePointer` (Under the pointer), `thawIcon` or `iceIcon` (Under the Thaw icon), `leftAligned` (Left edge) or `rightAligned` (Right edge). Numbers 0 to 4 work too |
| `alwaysShowHiddenItems`  | Bool | All displays without Thaw Bar | Show hidden items inline when Thaw Bar is disabled |
| `thawBarLayout`           | String | All displays with Thaw Bar enabled | Thaw Bar layout: `horizontal`, `vertical`, or `grid` |
| `gridColumns`            | Int | All displays with Thaw Bar enabled | Maximum items per row in grid layout (2 to 10) |
| `thawBarItemScale`       | Double | All displays with Thaw Bar enabled | How large the Thaw Bar draws items: 0.6 to 1, where 1 is the menu bar's size |
| `itemSpacingOffset`      | Double | Active display only | Menu bar item spacing for the display, from -16 to 16 points; applied when it has the active menu bar. A link can't ask first, so while **When spacing changes** is set to **Ask before restarting menu bar apps**, the value is saved and each app picks it up when it next starts |

Find display UUIDs in System Settings → Displays, or via `system_profiler SPDisplaysDataType`.

### Settings URL Format

Set a boolean:

```text
thaw://set?key=<setting>&value=<true|false>
```

```bash
open "thaw://set?key=autoRehide&value=true"
open "thaw://set?key=useThawBar&value=true&display=37D8832A-2D66-02CA-B9F7-8F30A301B230"
```

Toggle a boolean:

```text
thaw://toggle?key=<setting>
```

```bash
open "thaw://toggle?key=autoRehide"
open "thaw://toggle?key=useThawBar&display=XYZ789-..."
```

Set a non-boolean (enum, double, location, layout) with `thaw://set`:

```bash
open "thaw://set?key=thawBarLocation&value=mousePointer"
open "thaw://set?key=thawBarLayout&value=grid"
open "thaw://set?key=gridColumns&value=5"
open "thaw://set?key=rehideInterval&value=10"
open "thaw://set?key=showOnHoverDelay&value=0.5"
open "thaw://set?key=rehideStrategy&value=timed"   # or numeric: value=1
```

### Authorizing an App

External apps can proactively request authorization via `thaw://authorize`, which triggers the macOS permission dialog for the calling app without reading or writing any settings.

```bash
open "thaw://authorize"
open "thaw://get?key=all&callback=myapp://response&requestId=1"
```

- If the app is already whitelisted: silent no-op.
- If not whitelisted: shows the authorization dialog with app name, bundle ID, and signing info. After approval, the app can use all settings URIs.

### Getting Settings (Read Operations)

Read settings via `thaw://get`. Provide a response mechanism: a `callback` URL (recommended, receives full data) or `broadcast=true` (acknowledgement only).

For security, full settings data is only sent via callback. `broadcast=true` returns only an acknowledgement.

```bash
open "thaw://get?key=all&callback=droppy://thaw-response&requestId=abc123"
open "thaw://get?key=autoRehide&callback=droppy://thaw-response"
open "thaw://get?key=useThawBar&display=37D8832A-...&callback=droppy://thaw-response"
open "thaw://get?key=displays&callback=droppy://thaw-response"
open "thaw://get?key=display&display=37D8832A-...&callback=droppy://thaw-response"
```

App version is read-only and needs no whitelist auth; it works with `broadcast=true` too:

```bash
open "thaw://get?key=version&callback=droppy://thaw-response&requestId=abc123"
open "thaw://get?key=version&broadcast=true&requestId=abc123"
```

#### Response shapes

All-settings (via callback):

```json
{
  "requestId": "abc123",
  "status": "success",
  "data": {
    "appVersion": {"value": "1.2.3", "build": "42"},
    "global": {
      "autoRehide": {"value": true, "type": "boolean"},
      "rehideInterval": {"value": 5.0, "type": "double", "range": {"min": 1, "max": 300}},
      "rehideStrategy": {"value": "timed", "rawValue": 1, "type": "enum", "validValues": {"smart": 0, "timed": 1, "focusedApp": 2}}
    },
    "displays": {
      "37D8832A-2D66-02CA-B9F7-8F30A301B230": {
        "name": "Built-in Retina Display",
        "isConnected": true,
        "isPrimary": true,
        "hasNotch": true,
        "resolution": "2560x1600",
        "useThawBar": true,
        "useThawBarForAlwaysHidden": false,
        "thawBarLocation": "mousePointer",
        "alwaysShowHiddenItems": false
      }
    }
  }
}
```

Single setting:

```json
{
  "requestId": "uuid",
  "status": "success",
  "key": "autoRehide",
  "data": {"value": true, "type": "boolean"}
}
```

Displays:

```json
{
  "requestId": "uuid",
  "status": "success",
  "data": {
    "displays": [
      {
        "uuid": "37D8832A-...",
        "name": "Built-in Retina Display",
        "isConnected": true,
        "isPrimary": true,
        "hasNotch": true,
        "resolution": "2560x1600",
        "useThawBar": true,
        "useThawBarForAlwaysHidden": false,
        "thawBarLocation": "mousePointer",
        "alwaysShowHiddenItems": false
      }
    ]
  }
}
```

Broadcast (ack only):

```json
{
  "requestId": "abc123",
  "status": "ack",
  "message": "Use callback URL to receive full settings data"
}
```

Error:

```json
{
  "requestId": "uuid",
  "status": "error",
  "error": "Display not found",
  "details": "UUID: INVALID-UUID"
}
```

#### Response mechanisms

Callback URL (recommended): Thaw opens `yourapp://thaw-response?data=<url-encoded-json>` with the full payload. Your app must implement a URI handler.

Distributed notification (ack only): Thaw broadcasts on `DistributedNotificationCenter`, notification name `com.stonerl.Thaw.settingsURIGetResponse`. Returns only an acknowledgement, not the full payload.

```bash
open "thaw://get?key=all&broadcast=true&requestId=abc123"
```

#### Testing from Terminal (DEBUG builds only)

Sender detection fails from `open`, so DEBUG builds support a manual `bundleId` override:

```bash
open "thaw://set?key=showOnHover&value=true&bundleId=com.apple.Terminal"
```

The `bundleId` parameter is stripped/ignored in release builds. Remove it in production scripts.

### Launcher Operations

Five operations let a launcher list, drive and arrange menu bar items and profiles. The launcher queries, ranks, and picks an identifier; Thaw resolves it, acts, and reports the outcome. They pass the same feature toggle and whitelist as the settings URLs, and take the same `callback`, `broadcast`, and `requestId` parameters as `thaw://get`.

Floe (`com.thaw.floe`) and Thaw's own modules (bundle IDs that start with Thaw's bundle ID followed by `.module.`) are trusted without the authorization prompt and work while the Settings URI feature is off, provided they are signed by the same team as Thaw. Any other sender needs the feature enabled and an approved app in Privacy.

| URL | Parameters | Description |
| --- | ---------- | ----------- |
| `thaw://list-items` | `callback` or `broadcast` | Menu bar items that can be activated |
| `thaw://activate-item` | `item-id` | Opens an item's menu, revealing it first if hidden |
| `thaw://list-profiles` | `callback` or `broadcast` | Saved profiles and which one is active |
| `thaw://apply-profile` | `profile-id` | Applies a saved profile and waits for its layout |
| `thaw://move-item` | `item-id` (repeatable), `section`, optional `after-id` | Moves items into a section as a drop in Layout does |

```bash
open "thaw://list-items?callback=myapp://thaw-response&requestId=1"
open "thaw://activate-item?item-id=com.example.app%3AItem-0&callback=myapp://thaw-response&requestId=2"
open "thaw://list-profiles?callback=myapp://thaw-response&requestId=3"
open "thaw://apply-profile?profile-id=1B4E28BA-2FA1-11D2-883F-0016D3CCA427&callback=myapp://thaw-response&requestId=4"
```

`item-id` is an `id` from `list-items`, percent-encoded; `profile-id` is an `id` from `list-profiles`. The actions run with or without a response mechanism. The lists need one.

Responses use the `thaw://get` envelope plus an `operation` field. `data` always carries a `version` (currently `1`); fields may be added without changing it. As with `thaw://get`, the full response goes only to the callback, and `broadcast=true` returns an acknowledgement.

`list-items`:

```json
{
  "requestId": "1",
  "operation": "list-items",
  "status": "success",
  "data": {
    "version": 1,
    "items": [
      {"id": "com.example.app:Item-0", "name": "Example", "section": "hidden", "bundleId": "com.example.app"}
    ]
  }
}
```

`section` is `visible`, `hidden`, or `alwaysHidden`. `bundleId` is omitted when the owner is unknown.

`activate-item`:

```json
{
  "requestId": "2",
  "operation": "activate-item",
  "status": "success",
  "data": {"version": 1, "itemId": "com.example.app:Item-0", "outcome": "completed", "reactionObserved": true}
}
```

| `outcome` | `status` | Meaning |
| --------- | -------- | ------- |
| `completed` | `success` | The press or click was delivered. `reactionObserved` says whether the app was then seen opening a menu or window; an item that acts without opening one reports `false` |
| `itemUnavailable` | `error` | No actionable item has that identifier, for example because its app quit |
| `permissionMissing` | `error` | Thaw lacks Accessibility permission |
| `activationFailed` | `error` | The item is present but did not respond to any activation method |

`list-profiles`:

```json
{
  "requestId": "3",
  "operation": "list-profiles",
  "status": "success",
  "data": {
    "version": 1,
    "activeProfileId": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427",
    "profiles": [
      {"id": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "name": "Work", "isActive": true}
    ]
  }
}
```

`activeProfileId` is omitted when no profile is active.

`apply-profile`:

```json
{
  "requestId": "4",
  "operation": "apply-profile",
  "status": "success",
  "data": {"version": 1, "profileId": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "outcome": "applied"}
}
```

`outcome` is `applied`, `appliedWithoutLayout` (settings applied, but the layout could not run), `profileUnavailable`, `applyFailed`, or `profilesOff` (Profiles is turned off, so nothing is applied). The last three have `status` `error`.

An error response puts a stable code in `error` and a readable explanation in `details`. Failed actions also keep `data`, so the outcome is in one place either way. Besides the outcomes above, the codes are `invalidRequest` (a missing `item-id` or `profile-id`) and `permissionMissing` (for `list-items`, in place of an empty list):

```json
{
  "requestId": "2",
  "operation": "activate-item",
  "status": "error",
  "error": "itemUnavailable",
  "details": "No actionable menu bar item has this identifier",
  "data": {"version": 1, "itemId": "com.example.app:Item-0", "outcome": "itemUnavailable"}
}
```

`move-item`:

```text
thaw://move-item?item-id=<id>[&item-id=<id>...]&section=<visible|hidden|alwaysHidden>[&after-id=<id>]
```

```bash
open "thaw://move-item?item-id=com.example.app%3AItem-0&section=hidden&callback=myapp://thaw-response&requestId=5"
open "thaw://move-item?item-id=com.example.a%3AItem-0&item-id=com.example.b%3AItem-0&section=visible&after-id=com.example.c%3AItem-0"
```

`item-id` is an `id` from `list-items`, percent-encoded. Repeat it to move several items in one call; they keep the order given. `section` is matched without regard to case. Without `after-id`, the items go to the right end of the section. With `after-id`, they go directly to the right of that item as the Layout pane shows the section. `after-id` must already be in the target section and must not be one of the moved items.

Thaw checks every item before it moves any. If one is unknown, is one of Thaw's own control items, belongs to a group whose other members aren't listed too, or can't go to that section, the whole call is refused and `details` names that item. Groups move as a whole, as in Layout, so list every member to move one. `alwaysHidden` is refused while that section is turned off. The items then move in one pass, the same way a drop in Layout does, so the bar is laid out once. Thaw counts the move as a user edit, so automatic layout passes waiting at the time give way to it.

```json
{
  "requestId": "5",
  "operation": "move-item",
  "status": "success",
  "data": {"version": 1, "itemIds": ["com.example.app:Item-0"], "section": "hidden", "outcome": "moved"}
}
```

`afterId` is included when `after-id` was given. `outcome` is `moved` (Thaw recorded the new order and started applying it; as with a drop in Layout, the bar can take a moment to catch up), `unchanged` (the items were already there), or one of these error codes:

| Code | Meaning |
| ---- | ------- |
| `invalidRequest` | No `item-id`, no or an unknown `section`, an item listed twice, or `after-id` naming a moved item |
| `itemUnavailable` | No item in Layout has that identifier |
| `itemNotMovable` | A control item, a group member listed without the rest of its group, or an item that cannot go to that section |
| `sectionDisabled` | The target section is turned off |
| `anchorUnavailable` | `after-id` is not in the target section |
| `notApplied` | A move to Visible was saved, but the bar still did not show the new order after about eight seconds, so `move-item` waits that long before answering. Moves to other sections do not wait and answer `moved` |
| `moveRefused` | The move path declined the move, for example because an item quit in the meantime or macOS would not assign it |

`move-item` is not available in reduced mode.

A callback is a response, not a command. Any app can open your callback URL, so accept one only when its `requestId` and `operation` match a request you sent and are still waiting on, and never act on a callback beyond completing that request.

### Showing One Item

`thaw://reveal-item` shows one hidden item without opening its section. Pass exactly one of `item-id` (an `id` from `list-items`) or `bundle` (an app with a single item). The item hides again on its own after a short delay, the same way an item opened from the Thaw Bar does.

With `hold=true` (only the literal `true` counts), the item stays shown until the same app sends `thaw://release-item` with the same `item-id` or `bundle`. A bundle in `release-item` is matched against the items that app holds. Several apps can hold one item; it hides once the last of them releases it. Clicking the item, or Thaw showing it for another reason, leaves it shown while it is held. Holds end when Thaw quits, and a module's holds end when the module stops running. The Triggers module uses this to show items while an app runs.

Both URLs pass the same feature toggle and whitelist as the settings URLs, need macOS 27, and send no callback.

```bash
open "thaw://reveal-item?item-id=com.example.app%3AItem-0&hold=true"
open "thaw://release-item?item-id=com.example.app%3AItem-0"
```

### Raycast Settings Integration

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Toggle Thaw Setting
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Setting", "data": [{"title": "Auto-Rehide", "value": "autoRehide"}, {"title": "Hover Reveal", "value": "showOnHover"}, {"title": "Thaw Bar", "value": "useThawBar"}] }

open "thaw://toggle?key=${1}"
```

### Whitelist Management

Manage authorized apps in **Settings → Privacy**:

- View all whitelisted applications with icons and names
- Remove apps to revoke their access
- Manually add bundle IDs for apps not yet authorized
- Test with Thaw itself (DEBUG builds only)

### Error Handling

Settings URI requests fail silently when the feature is disabled, the requesting app is not whitelisted (and the user denied authorization), the setting key is invalid, or the boolean value is not `true`/`false`/`1`/`0`/`yes`/`no`. Check Thaw's diagnostic logs for details.

#### get-appearance

`thaw://get-appearance?callback=<url>[&requestId=<id>]` returns the menu bar appearance resolved for the current color scheme, so a partner app can match it.

```
{"requestId":"5","operation":"get-appearance","status":"success",
 "data":{"version":1,"colorScheme":"dark","shape":"full","hasRoundedShape":true,"hasShadow":true,
  "border":{"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":1,"style":"solid"},
  "tint":{"kind":"solid","opacity":0.2,"color":{"red":0,"green":0,"blue":0,"alpha":1}},
  "background":{"kind":"none","opacity":1}}}
```

- `shape` is `none`, `full`, `split` or `notch`.
- A fill's `kind` is `none`, `solid`, `gradient`, `glass`, `adaptive` or (tint only) `adaptiveGradient`. The adaptive kinds follow the wallpaper and carry no color. `color` is present for `solid` and for colored glass, `stops` (each with `color` and `location` from 0 to 1) and `angle` (degrees: 0 runs top to bottom, 90 leading to trailing) for `gradient`, and `glassStyle` (`regular`, `clear`, `liquid`, `dynamic`) with `glassIsColored` for `glass`.
- Colors are sRGB components from 0 to 1.
- `border` is omitted when the border is off; its `style` is `solid`, `dashed` or `dotted`.

Thaw posts the distributed notification `com.stonerl.Thaw.appearanceDidChange` when the appearance changes. It carries no payload: fetch again. The values are for one color scheme, so also fetch again when the system switches between light and dark.

## Notes

- All `thaw://` URLs work even when Thaw is not in the foreground
- The app may activate itself depending on the action
- URL handling is case-insensitive for the host portion
- Invalid URLs are logged but silently ignored
- Settings changes via URI trigger the same UI updates as manual changes
