# Roadmap

Thaw has two lines in development: 3.0 for macOS 27 and 2.1 for macOS 26. This is the plan as it stands, not a promise, and your reports decide the order. It was last brought up to date with the [3.0.0-beta.2 notes](../CHANGELOG.md) of 6 October 2026.

## Now

The two releases being finished.
### macOS 27

- **Thaw 3.0.0.** In beta. It is a rebuilt menu bar core for macOS 27, and the interface is being trimmed and tidied over the next betas.

### macOS 26

- **Thaw 2.1.0.** Six betas are done, and the stable release is being prepared. See the [changelog](../CHANGELOG.md).

## Coming next

The release after those two.
### macOS 15

- **Thaw 2.2.0.** It brings back compatibility with macOS 15.

## Up next

Planned for the 3.0.0 betas.
### Permissions

- **Minimal mode.** Thaw without the Accessibility permission, for anyone who would rather not grant it. It is in the works.

### Settings

- **Fewer switches.** Every setting is being gone through: some become default behaviour, some move under Advanced, and some go away. Experiments either graduate or get removed. The first pass shipped in 3.0.0-beta.1.

### Layout

- **Stand-ins without a switch.** Dragging an Apple item Thaw can't hide into Hidden should put a Thaw icon there for you. Today that takes a switch in Experiments.
- **Undo for drags.** Command-Z will undo mouse moves in Layout, the way it already undoes keyboard moves.

### Coming over from 2.1

- **Scripts.** Script-driven bar modules, tested by macOS 26 users on 2.1.0, are the next thing coming to 3.0. The Scripts pane is already there as a preview.
- **The full trigger engine.** In 2.1 an item can move on battery level, the frontmost app, a network, a Focus and more. 3.0 has part of it: 3.0.0-beta.2 added showing items while an app runs.
- **Widgets.** The Widgets pane is a placeholder that shows where widgets will live. It holds no settings yet.
- **Rotating diagnostic logs.** Keeping and cycling through diagnostic logs will appear in a later 3.0 build.

## Blocked by macOS 27

These run into limits in macOS 27 itself. The team is looking for ways around them and can't promise them for the beta.
### Hiding

- **Separate items from the same app.** macOS 27 hides and shows an app's items together, so one of an app's items can't yet go in Hidden while another stays in Visible.

### Layout

- **Even spacing.** Each app adds its own padding around its items, so the same spacing setting can still leave uneven gaps. [#1126](https://github.com/thaw-app/Thaw/issues/1126)
- **A Timer stand-in.** Thaw can't remove Apple's Timer, so it can't put one of its own in its place.

## Further out

These come after the beta is solid. The team intends to build them, and none has a date.
### Integrations

- **An Alfred workflow.** One you can install, on top of the `thaw://` links that [already work with Alfred](URI_SCHEMES.md).
- **Import from another menu bar manager.** Bring your setup with you, so switching to Thaw doesn't mean starting over.
- **More with Droppy and Floe.** Both already drive Thaw through `thaw://` links: they open menu bar items and apply profiles. The plan is to take that further.
- **OmniWM.** Work alongside the OmniWM window manager on macOS 26 and 27, so Thaw stays out of the way of its workspaces. It came up on [OmniWM's issue tracker](https://github.com/OmniNull/OmniWM/issues/752).
- **MCP support.** A server for AI assistants, so one you already use can read your menu bar and rearrange it when you ask.

### Installing

- **Modules.** Download only the parts of Thaw you use, and add others when you want them, so the app you install is no bigger than what you need.
- **Nix support.** A flake, so Thaw can be installed and pinned from a Nix configuration.

### Across your Macs

- **iCloud sync.** For profiles, appearance and preferences. Anything tied to one Mac's displays stays local.

### Menu bar items

- **Your own menus in the menu bar.** Make an item yourself and fill its menu with actions: open a link, run a Shortcut, run a script. Thaw puts it in the menu bar and treats it like any other item.
- **Isolation mode.** Show just one item for a while, with everything else out of the way. [#970](https://github.com/thaw-app/Thaw/issues/970)

## Ideas

Things we have written up and not decided on. None is planned.
### Integrations

- **Stream Deck and other controllers.** Keys that hide and show sections, switch profiles and stay lit while a mode is on.
- **Items hosted by Thaw.** Another app hands Thaw an icon and a menu, and Thaw shows it as a menu bar item that follows your sections and profiles like any other.

### Displays

- **OLED saving mode.** The menu bar sits on the same pixels all day. Thaw could turn it true black, shift the items a point or two now and then, and dim them when the Mac is idle.

## Suggesting changes

Roadmap items are tracked as issues. To propose something, open a
[feature request](https://github.com/thaw-app/Thaw/issues/new/choose) or start with
[Ways to contribute](https://github.com/thaw-app/Thaw/issues/316).

## Shipped

Everything that has shipped, by release, newest first. The changelog has the detail.
### 3.0.0-beta.2

- Triggers can show items while an app runs
- Launchers can open menu bar items and apply profiles through `thaw://` URLs
- Restore missing menu bar items, in Troubleshooting
- Gradients at any angle
- Layout shows when macOS won't let an icon follow its section

### 3.0.0-beta.1

- Rounded screen corners, carried over from the 2.x roadmap
- Open an item by letter, planned as "item hints"
- Folders for item groups, each with its own icon and colour
- The app's own icon where Thaw has no picture of an item
- Choose the icon Thaw shows for any item
- One menu for every item in Layout, search and the Thaw Bar
- Live Activities and the camera indicator stay visible while apps are hidden
- Open hidden items in the menu bar, under their own icon
- Replace Input Menu, with your keyboard layouts

### 3.0.0 alphas

- A rebuilt menu bar core for macOS 27
- Time Machine can be hidden
- Focus, AirDrop, Now Playing and Fast User Switching stay reachable while hidden
- The Layout editor works from the keyboard: Tab, Home and End, Option-arrows, Space
- Swap bar
- macOS 27's limits shown in the Layout pane
- App zoom
- A separate appearance for the Thaw Bar
- Reapply Spacing

### Pre-3.0.0

- Hiding, showing and reordering items on macOS 27
- Hiding system items
- Settings search
- Reset layout
- A new onboarding walkthrough
- Deep links
- Support for macOS 27's own overflow icon

### 2.1.0

- Item triggers: an item moves when something happens
- Image-change triggers, with comparison modes and a preview
- Menu bar item groups
- Individual spacer items
- Zen Mode
- Simple Mode
- Per-Space profiles and per-Space appearance
- Wallpaper changes re-tint the bar right away
- Items that ask for attention surface themselves
- A Thaw Bar with its own shape and tint
- Hidden icons refresh at the slider rate
- One Per display section in place of repeated blocks
- App icons where captures can't go, so Screen Recording is optional
- A hotkey to enable and disable auto-rehide
- Opened items can stay a while after their menu closes
- Diagnostic logs that rotate by size and time

### 2.0.0

- Built for macOS 26, with Liquid Glass throughout
- Reading and writing settings through `thaw://` URLs
- Per-item hotkeys
- Script hooks before and after a profile is applied
- Adaptive background and tint, per screen
- Configurable background and a glass effect
- Notch shape, a notch margin slider and tint opacity
- Per-display menu bar spacing
- A reworked menu bar item spacing
- Thaw Bar layout options, alignments, a grid and dynamic resizing
- Hold to preview
- Option-click for the always-hidden section
- Double-click the Thaw icon
- Restart Thaw, from the menu
- Game Mode support
- A refreshed Settings window and onboarding

### 1.3.0-beta.1

- Settings Profiles
- Profiles that switch with the display
- Focus mode integration
- Profile hotkeys
- A badge for new items
- Icon overflow for notched displays
- Keep the search panel open

### 1.2.0

- Icon positions saved and restored across restarts
- Custom names for menu bar items
- Menu bar item tooltips
- The `thaw://` URL scheme
- A hotkey to toggle application menus
- Hover highlight in the Thaw Bar
- Conflicting apps detection
- Per-display settings
- A Reset Thaw button

### 1.1.0

- Localised in 12 languages
- Double-click the menu bar to reveal the always-hidden section
- The active menu bar detected on each screen
- The Thaw Bar for displays with a notch only

### 1.0.0

- The first stable release of Thaw
