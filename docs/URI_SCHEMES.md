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
| `thaw://toggle-thawbar`           | Toggle Thaw Bar       | Toggles the Thaw Bar on the active display |
| `thaw://toggle-application-menus` | Toggle App Menus      | Shows/hides application menus            |
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
| `ThawMenuBarItemSpacingExecutableURI` | `file:///usr/bin/env`                 | Executable path for spacing commands |

## System URLs

macOS Settings URLs Thaw opens:

| URL                                                                             | Opens                     |
| ------------------------------------------------------------------------------- | ------------------------- |
| `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` | Accessibility settings    |
| `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` | Screen Recording settings |

## Settings URI (Automation)

Read and write Thaw settings via `thaw://` URLs, gated by a security whitelist. Automation tools like Droppy use this to control Thaw settings.

### Security Model

1. Feature toggle: Settings URI is disabled by default (enable in Settings → Automation)
2. Whitelist: only approved apps can modify settings
3. First-time authorization: new apps trigger a confirmation dialog with app name and permissions. Apps can proactively request authorization via `thaw://authorize` without reading or writing settings
4. Silent failures: unauthorized requests fail without user interruption

### Supported Settings Keys

#### Global Settings (All Displays)

| Key                                       | Type | Description                                  |
| ----------------------------------------- | ---- | -------------------------------------------- |
| `autoRehide`                              | Bool | Auto-rehide hidden items after interval      |
| `showOnClick`                             | Bool | Show hidden items when clicking the menu bar |
| `showOnDoubleClick`                       | Bool | Show hidden items on double-click            |
| `showOnHover`                             | Bool | Show hidden items on hover                   |
| `showOnScroll`                            | Bool | Show hidden items on scroll                  |
| `useIceBarOnlyOnNotchedDisplay`           | Bool | Thaw Bar only on Macs with notch             |
| `hideApplicationMenus`                    | Bool | Hide application menu titles                 |
| `enableAlwaysHiddenSection`               | Bool | Enable the always-hidden section             |
| `useOptionClickToShowAlwaysHiddenSection` | Bool | Option-click shows always-hidden items       |
| `useDoubleClickToShowAlwaysHiddenSection` | Bool | Double-click Thaw icon shows always-hidden   |
| `enableSecondaryContextMenu`              | Bool | Right-click shows alternate menu             |
| `showAllSectionsOnUserDrag`               | Bool | Reveal all sections during drag              |
| `showMenuBarTooltips`                     | Bool | Show hover tooltips on menu bar items        |
| `enableDiagnosticLogging`                 | Bool | Enable debug logging                         |
| `customIceIconIsTemplate`                 | Bool | Custom icon renders as template              |
| `showIceIcon`                             | Bool | Show the Thaw icon in menu bar               |
| `hideDockIconWhenToggling`                | Bool | Hide Dock icon on menu-bar toggle; overflow uses Thaw Bar |
| `iceBarLocationOnHotkey`                  | Bool | Thaw Bar appears at mouse location on hotkey     |
| `enableMenuBarItemOverflow`                | Bool | Eject items that would fall behind the notch |
| `useThawBarOnNotchOverflow`                | Bool | Send ejected overflow items to the Thaw Bar  |
| `moveCursorToRevealedItem`                 | Bool | Move the cursor onto an item once revealed   |
| `searchIncludeVisible`                     | Bool | Include visible items in search results      |
| `searchIncludeHidden`                      | Bool | Include hidden items in search results       |
| `searchIncludeAlwaysHidden`                | Bool | Include always-hidden items in search        |

#### Double/Time Interval Settings

| Key                      | Type | Range | Description |
| ------------------------ | ---- | ----- | ----------- |
| `rehideInterval`         | Double | 1-300 seconds | Time before auto-rehide (default: 15) |
| `showOnHoverDelay`       | Double | 0-5 seconds | Delay before hover reveals items (default: 0.2) |
| `tooltipDelay`           | Double | 0-5 seconds | Delay before showing tooltips (default: 0.5) |
| `iconRefreshInterval`    | Double | 0-1 seconds | Interval between icon refreshes in panels; `0` means Off; positive values snap to `1/n` seconds for integer `n` in 1–30 (default: 0.25 ≈ 4 fps) |

Values outside the valid range are clamped to the nearest boundary. `iconRefreshInterval` is additionally snapped onto the discrete fps grid above before it is stored.

#### Enum Settings

| Key            | Type | Valid Values | Description |
| -------------- | ---- | ------------ | ----------- |
| `rehideStrategy` | String/Int | `smart` (0), `timed` (1), `focusedApp`/`focused_app` (2) | Strategy for auto-rehiding items (default: smart) |

#### Per-Display Settings

These settings affect specific displays based on context. The **Scope** column is the default; `display=<UUID>` overrides it to target one display by UUID and fails silently if that display is not connected.

| Key                      | Type | Scope | Description |
| ------------------------ | ---- | ----- | ----------- |
| `useIceBar`              | Bool | Active display only | Enable/disable Thaw Bar on the display with the active menu bar |
| `useThawBarForAlwaysHidden` | Bool | All displays without IceBar | Open only the always-hidden section in the Thaw Bar, leaving hidden items to expand inline |
| `iceBarLocation`         | String | All displays with IceBar enabled | Thaw Bar position: `dynamic`, `mousePointer`, `iceIcon`, `leftAligned`, or `rightAligned` |
| `alwaysShowHiddenItems`  | Bool | All displays without IceBar | Show hidden items inline when IceBar is disabled |
| `iceBarLayout`           | String | All displays with IceBar enabled | Thaw Bar layout: `horizontal`, `vertical`, or `grid` |
| `gridColumns`            | Int | All displays with IceBar enabled | Maximum items per row in grid layout (2–10) |

Find display UUIDs in System Settings → Displays, or via `system_profiler SPDisplaysDataType`.

### Settings URL Format

Set a boolean:

```text
thaw://set?key=<setting>&value=<true|false>
```

```bash
open "thaw://set?key=autoRehide&value=true"
open "thaw://set?key=useIceBar&value=true&display=37D8832A-2D66-02CA-B9F7-8F30A301B230"
```

Toggle a boolean:

```text
thaw://toggle?key=<setting>
```

```bash
open "thaw://toggle?key=autoRehide"
open "thaw://toggle?key=useIceBar&display=XYZ789-..."
```

Set a non-boolean (enum, double, location, layout) with `thaw://set`:

```bash
open "thaw://set?key=iceBarLocation&value=mousePointer"
open "thaw://set?key=iceBarLayout&value=grid"
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
open "thaw://get?key=useIceBar&display=37D8832A-...&callback=droppy://thaw-response"
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
        "useIceBar": true,
        "useThawBarForAlwaysHidden": false,
        "iceBarLocation": "mousePointer",
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
        "useIceBar": true,
        "useThawBarForAlwaysHidden": false,
        "iceBarLocation": "mousePointer",
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

Four operations let a launcher list and drive menu bar items and profiles. The launcher queries, ranks, and picks an identifier; Thaw resolves it, acts, and reports the outcome. They pass the same feature toggle and whitelist as the settings URLs, and take the same `callback`, `broadcast`, and `requestId` parameters as `thaw://get`.

Floe (`com.thaw.floe`) is trusted without the authorization prompt and works while the Settings URI feature is off, provided it is signed by the same team as Thaw. Any other sender needs the feature enabled and an approved entry in Automation.

| URL | Parameters | Description |
| --- | ---------- | ----------- |
| `thaw://list-items` | `callback` or `broadcast` | Menu bar items that can be activated |
| `thaw://activate-item` | `item-id` | Opens an item's menu, revealing it first if hidden |
| `thaw://list-profiles` | `callback` or `broadcast` | Saved profiles and which one is active |
| `thaw://apply-profile` | `profile-id` | Applies a saved profile and waits for its layout |

```bash
open "thaw://list-items?callback=myapp://thaw-response&requestId=1"
open "thaw://activate-item?item-id=com.example.app%3AItem-0&callback=myapp://thaw-response&requestId=2"
open "thaw://list-profiles?callback=myapp://thaw-response&requestId=3"
open "thaw://apply-profile?profile-id=1B4E28BA-2FA1-11D2-883F-0016D3CCA427&callback=myapp://thaw-response&requestId=4"
```

`item-id` is an `id` from `list-items`, percent-encoded; `profile-id` is an `id` from `list-profiles`. The two actions run with or without a response mechanism. The two lists need one.

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

`outcome` is `applied`, `appliedWithoutLayout` (settings applied, but the layout could not run), `profileUnavailable`, or `applyFailed`. The last two have `status` `error`.

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

A callback is a response, not a command. Any app can open your callback URL, so accept one only when its `requestId` and `operation` match a request you sent and are still waiting on, and never act on a callback beyond completing that request.

### Raycast Settings Integration

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Toggle Thaw Setting
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Setting", "data": [{"title": "Auto-Rehide", "value": "autoRehide"}, {"title": "Hover Reveal", "value": "showOnHover"}, {"title": "Thaw Bar", "value": "useIceBar"}] }

open "thaw://toggle?key=${1}"
```

### Whitelist Management

Manage authorized apps in **Settings → Automation**:

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
