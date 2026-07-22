# Thaw URI Schemes & Deep Linking

Thaw supports custom URL schemes for deep linking, enabling integration with automation tools like Raycast, Alfred, and custom scripts.

## Overview

Thaw registers the `thaw://` URL scheme in `Info.plist` via `CFBundleURLTypes`. This allows external applications and scripts to trigger Thaw actions programmatically.

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

#### Terminal

```bash
open "thaw://toggle-hidden"
open "thaw://search"
open "thaw://open-settings"
```

#### Swift

```swift
NSWorkspace.shared.open(URL(string: "thaw://search")!)
```

#### AppleScript

```applescript
tell application "System Events"
    open location "thaw://toggle-hidden"
end tell
```

#### Bash Script

```bash
#!/bin/bash
# Toggle hidden section
open "thaw://toggle-hidden"
```

### Raycast Integration

#### Quicklink (Simple URL Trigger)

1. Open Raycast → Create Quicklink
2. Name: `Toggle Hidden Section`
3. Link: `thaw://toggle-hidden`
4. Assign a hotkey (e.g., `⌃⌥⌘H`)

#### Script Command (With Arguments)

```bash
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Thaw Actions
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Action", "data": [{"title": "Toggle Hidden", "value": "toggle-hidden"}, {"title": "Search", "value": "search"}, {"title": "Settings", "value": "open-settings"}] }

open "thaw://${1}"
```

### Alfred Workflow

#### URL Trigger

1. Create a new Workflow
2. Add `Open URL` object
3. URL: `thaw://toggle-hidden`
4. Connect to a hotkey trigger

#### Script Filter (Advanced)

```bash
# Keyword: thaw
# Action: Toggle hidden section
open "thaw://toggle-hidden"
```

## Info.plist URLs

The following URLs are configured in `Thaw/Resources/Info.plist` for internal use:

| Key                                   | Value                                 | Description                          |
| ------------------------------------- | ------------------------------------- | ------------------------------------ |
| `ThawRepositoryURL`                   | `https://github.com/stonerl/Thaw`     | GitHub repository                    |
| `ThawDonateURL`                       | `https://github.com/sponsors/stonerl` | Sponsorship page                     |
| `ThawMenuBarItemSpacingExecutableURI` | `file:///usr/bin/env`                 | Executable path for spacing commands |

## System URLs

Thaw uses the following system URLs to open macOS Settings:

| URL                                                                             | Opens                     |
| ------------------------------------------------------------------------------- | ------------------------- |
| `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` | Screen Recording settings |

## Settings URI (Automation)

Thaw supports programmatic settings manipulation via the `thaw://` URL scheme with a security whitelist. This allows automation tools like **Droppy** to control Thaw settings.

### Security Model

1. **Feature Toggle**: Settings URI is disabled by default (enable in Settings → Automation)
2. **Whitelist**: Only approved apps can modify settings
3. **First-Time Authorization**: New apps trigger a confirmation dialog with app name and permissions. Apps can proactively request authorization via `thaw://authorize` without reading or writing settings
4. **Silent Failures**: Unauthorized requests fail without user interruption

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
| `iceBarLocationOnHotkey`                  | Bool | Thaw Bar appears at mouse location on hotkey     |
| `useLCSSortingOnNotchedDisplays`          | Bool | Use LCS sorting on notched displays          |

#### Double/Time Interval Settings

| Key                      | Type | Range | Description |
| ------------------------ | ---- | ----- | ----------- |
| `rehideInterval`         | Double | 1-300 seconds | Time before auto-rehide (default: 15) |
| `showOnHoverDelay`       | Double | 0-5 seconds | Delay before hover reveals items (default: 0.2) |
| `tooltipDelay`           | Double | 0-5 seconds | Delay before showing tooltips (default: 0.5) |
| `iconRefreshInterval`    | Double | 0.1-5 seconds | Interval between icon refreshes (default: 0.1) |

**Note:** Values outside the valid range are automatically clamped to the nearest boundary.

#### Enum Settings

| Key            | Type | Valid Values | Description |
| -------------- | ---- | ------------ | ----------- |
| `rehideStrategy` | String/Int | `smart` (0), `timed` (1), `focusedApp`/`focused_app` (2) | Strategy for auto-rehiding items (default: smart) |

#### Per-Display Settings

These settings affect specific displays based on context:

| Key                      | Type | Scope | Description |
| ------------------------ | ---- | ----- | ----------- |
| `useIceBar`              | Bool | Active display only | Enable/disable Thaw Bar on the display with the active menu bar |
| `iceBarLocation`         | String | All displays with IceBar enabled | Thaw Bar position: `dynamic`, `mousePointer`, `iceIcon`, `leftAligned`, or `rightAligned` |
| `alwaysShowHiddenItems`  | Bool | All displays without IceBar | Show hidden items inline when IceBar is disabled |
| `iceBarLayout`           | String | All displays with IceBar enabled | Thaw Bar layout: `horizontal`, `vertical`, or `grid` |
| `gridColumns`            | Int | All displays with IceBar enabled | Maximum items per row in grid layout (2–10) |

**Per-Display Behavior:**

By default:
- `useIceBar`: Only affects the display with the currently active menu bar (where your cursor is)
- `iceBarLocation`: Updates all displays that currently have the IceBar enabled
- `alwaysShowHiddenItems`: Updates all displays that do NOT have the IceBar enabled

With `display=<UUID>` parameter:
- All per-display settings can target a specific display by its UUID
- Overrides the default scope behavior
- Fails silently if the specified display is not connected

### Settings URL Format

#### Set a Boolean Value

```text
thaw://set?key=<setting>&value=<true|false>
```

**Examples:**

```bash
# Enable auto-rehide
open "thaw://set?key=autoRehide&value=true"

# Disable hover reveal
open "thaw://set?key=showOnHover&value=false"

# Enable Thaw Bar
open "thaw://set?key=useIceBar&value=true"
```

#### Toggle a Boolean Value

```text
thaw://toggle?key=<setting>
```

**Examples:**

```bash
# Toggle auto-rehide (on → off, off → on)
open "thaw://toggle?key=autoRehide"

# Toggle Thaw Bar visibility (active display only)
open "thaw://toggle?key=useIceBar"

# Toggle application menu hiding
open "thaw://toggle?key=hideApplicationMenus"

# Set IceBar location (all displays with IceBar enabled)
open "thaw://set?key=iceBarLocation&value=mousePointer"

# Set IceBar aligned left (all displays with IceBar enabled)
open "thaw://set?key=iceBarLocation&value=leftAligned"

# Set IceBar aligned right (all displays with IceBar enabled)
open "thaw://set?key=iceBarLocation&value=rightAligned"

# Enable always-show-hidden-items (all displays without IceBar)
open "thaw://set?key=alwaysShowHiddenItems&value=true"

# Set Thaw Bar layout to grid (all displays with IceBar enabled)
open "thaw://set?key=iceBarLayout&value=grid"

# Set grid columns to 5 (all displays with IceBar enabled)
open "thaw://set?key=gridColumns&value=5"

# Set rehide interval to 10 seconds (clamped to range 1-300)
open "thaw://set?key=rehideInterval&value=10"

# Set hover delay to 0.5 seconds
open "thaw://set?key=showOnHoverDelay&value=0.5"

# Set rehide strategy to "timed" (0=smart, 1=timed, 2=focusedApp)
open "thaw://set?key=rehideStrategy&value=timed"
# Or using numeric value
open "thaw://set?key=rehideStrategy&value=1"
```

#### Target Specific Display (Per-Display Settings)

Use the optional `display` parameter to target a specific display by UUID:

```bash
# Enable Thaw Bar on specific display by UUID
open "thaw://set?key=useIceBar&value=true&display=37D8832A-2D66-02CA-B9F7-8F30A301B230"

# Set IceBar location on specific display
open "thaw://set?key=iceBarLocation&value=iceIcon&display=ABC12345-..."

# Toggle Thaw Bar on specific display
open "thaw://toggle?key=useIceBar&display=XYZ789-..."
```

**Note:** Display UUIDs can be found in System Settings → Displays, or via the `system_profiler SPDisplaysDataType` command. If the specified display is not connected, the request fails silently.

### Authorizing an App

External apps can proactively request authorization via `thaw://authorize`. This triggers the macOS permission dialog for the calling app without needing to read or write any settings.

```bash
# Request whitelist authorization for the calling app
open "thaw://authorize"
```

**Behavior:**
- If the app is already whitelisted → silent no-op
- If the app is not whitelisted → shows the authorization dialog with app name, bundle ID, and signing info
- After approval, the app is added to the whitelist and can use all settings URIs

**Usage:**
```bash
# Request authorization before reading settings
open "thaw://authorize"
open "thaw://get?key=all&callback=myapp://response&requestId=1"
```

### Getting Settings (Read Operations)

Thaw supports reading settings via `thaw://get` URLs. You must provide a response mechanism: either a `callback` URL (recommended) or `broadcast=true` for acknowledgement notifications.

**Important:** For security reasons, full settings data is only sent via callback URL. Using `broadcast=true` returns only an acknowledgement, not the full settings payload.

#### Get All Settings

```bash
# Get all settings with callback URL (receives full data)
open "thaw://get?key=all&callback=droppy://thaw-response&requestId=abc123"
```

**Response JSON (via callback):**
```json
{
  "requestId": "abc123",
  "status": "success",
  "data": {
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
        "iceBarLocation": "mousePointer",
        "alwaysShowHiddenItems": false
      }
    }
  }
}
```

#### Get Individual Setting

```bash
# Get single setting
open "thaw://get?key=autoRehide&callback=droppy://thaw-response"

# Get per-display setting
open "thaw://get?key=useIceBar&display=37D8832A-...&callback=droppy://thaw-response"
```

**Response JSON:**
```json
{
  "requestId": "uuid",
  "status": "success",
  "key": "autoRehide",
  "data": {"value": true, "type": "boolean"}
}
```

#### Get App Version (No Auth Required)

The app version is a read-only value accessible without whitelist authorization. No callback URL required — it works with `broadcast=true` as well.

```bash
# Get app version (no auth needed)
open "thaw://get?key=version&callback=droppy://thaw-response&requestId=abc123"

# Or via broadcast
open "thaw://get?key=version&broadcast=true&requestId=abc123"
```

**Response JSON:**
```json
{
  "requestId": "abc123",
  "status": "success",
  "key": "version",
  "data": {
    "value": "1.2.3",
    "build": "42",
    "type": "string"
  }
}
```

When included in `key=all`, version appears as:
```json
{
  "data": {
    "appVersion": {
      "value": "1.2.3",
      "build": "42"
    },
    "global": {},
    "displays": {}
  }
}
```

#### Get Display Information

```bash
# Get all displays
open "thaw://get?key=displays&callback=droppy://thaw-response"

# Get specific display
open "thaw://get?key=display&display=37D8832A-...&callback=droppy://thaw-response"
```

**Response JSON:**
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
        "iceBarLocation": "mousePointer",
        "alwaysShowHiddenItems": false
      }
    ]
  }
}
```

#### Response Mechanisms

**Callback URL (Recommended):**
- Thaw opens the provided URL with URL-encoded JSON data
- Format: `yourapp://thaw-response?data=<url-encoded-json>`
- Your app must implement a URI handler for the callback
- Receives full settings data

**Distributed Notification (Acknowledgement Only):**
- Thaw broadcasts via `DistributedNotificationCenter`
- Notification name: `com.stonerl.Thaw.settingsURIGetResponse`
- **Only returns acknowledgement, not full settings data** (for security)
- Use callback URL to receive full settings payload

```bash
# Broadcast returns only acknowledgement
open "thaw://get?key=all&broadcast=true&requestId=abc123"
```

**Broadcast Response JSON:**
```json
{
  "requestId": "abc123",
  "status": "ack",
  "message": "Use callback URL to receive full settings data"
}
```

**Error Response:**
```json
{
  "requestId": "uuid",
  "status": "error",
  "error": "Display not found",
  "details": "UUID: INVALID-UUID"
}
```

#### Testing from Terminal (DEBUG Builds Only)

When testing from Terminal, the sender app detection may fail because `open` command doesn't properly identify the source. DEBUG builds support a manual `bundleId` override parameter:

```bash
# For testing: manually specify sender bundle ID
open "thaw://set?key=showOnHover&value=true&bundleId=com.apple.Terminal"

# This shows "Terminal" in the authorization dialog instead of "Unknown App"
```

⚠️ **DEBUG builds only:** The `bundleId` parameter is stripped/ignored in release builds for security. Always remove this parameter in production automation scripts.

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

Settings URI requests may fail silently in these cases:

- Settings URI feature is disabled
- Requesting app is not whitelisted (and user denied authorization)
- Invalid setting key specified
- Invalid boolean value format (not `true`/`false`/`1`/`0`/`yes`/`no`)

Check Thaw's diagnostic logs for details on failed requests.

## Notes

- All `thaw://` URLs work even when Thaw is not currently in the foreground
- The app may activate itself depending on the action
- URL handling is case-insensitive for the host portion
- Invalid URLs are logged but silently ignored
- Settings changes via URI trigger the same UI updates as manual changes
