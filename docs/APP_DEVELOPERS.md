# Make your app work with Thaw

Thaw moves and hides other apps' menu bar items. Up to macOS 26, each item had a window of its own, so this mostly worked whatever an app did. macOS 27 draws the whole menu bar in one window, and Thaw has to work out which item is which from what each app tells it. What your app does decides whether Thaw can keep its items where people put them.

This page is for the developers of those apps, and came out of [a question in Discussions](https://github.com/orgs/thaw-app/discussions/1242). Most of it was measured while making [Barometer](https://github.com/mackid1993/Barometer) work with menu bar managers on macOS 27.

## In short

1. Give every item a fixed `autosaveName` and accessibility identifier, before it is first shown.
2. Keep changing text, such as a temperature, out of the button's title. Draw it into the image.
3. Make each item once, and hide it with `isVisible`.
4. Keep your main thread free to answer Accessibility requests.
5. Show each item that should hide on its own from a helper app with its own bundle identifier.
6. Test from `/Applications`, then check the item in Thaw's Menu Bar Layout.

## Hand it to your coding agent

Paste this into Claude Code, Codex, Cursor or another coding agent, in your app's project. It sums up this page and sends the agent here for the details.

```text
Make this app's menu bar items work with Thaw and other menu bar managers on
macOS 27. Read the guide first: https://getthaw.app/docs/thaw/app-developers.md

Thaw knows an item by the app's bundle identifier and the item's name, which it
reads from the autosaveName and the accessibility title, identifier, description
and value. If either changes, the item loses its place.

1. Find every NSStatusItem the app makes.
2. Give each one a fixed autosaveName and accessibility identifier, such as
   "com.example.app.cpu", and an accessibility label, before its first
   isVisible. One name per item, never reused. A second item of the same kind
   gets ".2", a third ".3". Don't rename an item that has shipped.
3. Make each item once, keep it for as long as the app runs, and hide it with
   isVisible. Don't remove and remake items, and don't use .removalAllowed.
4. Keep changing text, such as a temperature or a count, out of the button
   title. Set the title to "", draw the text into the button image with
   imagePosition = .imageOnly, and pass the reading to setAccessibilityValue.
5. Don't set the title of the status item's window.
6. Don't write to AppKit's visibility or position defaults or to Control
   Center's preferences, and don't reorder items from code. If the app has its
   own way of hiding menu bar items, keep it off while Thaw is running.
7. Keep long work off the main thread, so the app answers Accessibility
   requests at once, at launch too.
8. Make the app an agent with LSUIElement in Info.plist, not by setting the
   .accessory activation policy before the run loop starts.
9. Let only one copy run: a second launch hands over to the first and quits.
10. If an item should hide on its own, apart from the app's other items, tell
    me, and propose a helper app with its own bundle identifier as the guide
    describes. Don't build it without asking.

When you're done, list each item with its autosaveName and what you changed.
Then tell me how to check it: install the app in /Applications, put each item
in a section in Thaw's Menu Bar Layout, quit and reopen the app, and see that
each item is listed once, under its own name, in its section.
```

## How Thaw tells items apart

Thaw knows an item by two things:

1. The bundle identifier of the app that made it.
2. The item's name, which it reads from the item's `autosaveName` and its accessibility title, identifier, description and value.

If either changes, Thaw treats it as an item it has never seen, and the item loses its place. An item that renames itself when its icon changes is a common reason an item seems to wander or go missing.

## Give every item a fixed name

```swift
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
// Name it before it is first shown, so it is never seen without one.
item.autosaveName = "com.example.app.cpu"
if let button = item.button {
    button.setAccessibilityIdentifier("com.example.app.cpu")
    button.setAccessibilityLabel("CPU")
}
item.isVisible = true
```

- **Name it before it is shown.** Set the autosave name, accessibility identifier and label before the item's first `isVisible`. A manager that sees an unnamed item can pair it with the wrong name.
- **One name per item, for good.** Give each item its own name and never reuse one for different content. A second item of the same kind gets `.2`, a third `.3`, and so on.
- **Don't rename an item that has shipped.** macOS keeps the position it saved under the old name, so after a rename your app has two entries for one item. Thaw can no longer tell which entry is the item's, and has to move them all together.
- **Make it once.** Keep each item for as long as the app runs, and hide it with `isVisible`. Removing an item and making it again, or using `.removalAllowed`, gives a manager a new item each time. An item that only shows some of the time, such as a music player, is the one this matters for most.
- **Leave the window's title alone.** Don't set the title of the status item's window.

## Keep live values out of the title

A button title that changes, such as a temperature or a count, becomes the item's accessibility title, and Thaw reads it as a new name. Draw changing text into the button's image instead, and give the reading to accessibility as a value:

```swift
button.title = ""
button.imagePosition = .imageOnly
button.image = reading // the text, drawn into an image
button.setAccessibilityValue("62 °C")
```

### Apps whose names keep changing

Thaw has worked around a number of apps whose item names change all the time:

- **Dato** shows the date and a countdown to your next event, so its name keeps changing, whatever date format you pick ([#1175](https://github.com/thaw-app/Thaw/issues/1175)).
- **Amphetamine**'s one item switches between `Item-0`, `∞` and `𝗧`.
- **ThermalForge**, **MacThrottle**, **Macs Fan Control** and **iStat Menus** show live temperatures and readings.
- **Outlook** puts a countdown to your next meeting in front of its name.

A fixed name in your own app is the fix that lasts. Each app above needed a change in Thaw itself, and Thaw no longer adds workarounds for single apps.

For these apps, Thaw strips out the changing part of the name, or tells the items apart by where they sit. It learns to do the same for an app with a single item that renames itself, such as WeChat with its unread count.

Position only goes so far. When an app has several items, moving one can swap which is which.

### Items with no name

Set an autosave name and an accessibility identifier, as above, and your items never end up as one of these.

An item that publishes no name of its own gets a placeholder from macOS by its position: `Item-0`, `Item-1` and so on. Thaw can tell two of an app's unnamed items apart only by their order, so moving one can make them trade places in Layout, or trade sections.

It happened to Rectangle, whose item became `Item-0` when its old AppKit placeholder name could no longer be read. Little Snitch had it worst, below.

### What Little Snitch went through

Little Snitch's agent shows its item through Control Center, so Thaw saw it as `com.apple.controlcenter:Item-0`, with no name and no app behind it. Thaw had to work out which item was Little Snitch's by matching it indirectly. For months, people saw what looked like Thaw bugs:

1. It wasn't listed by name in Layout, and dragging it there didn't last ([#709](https://github.com/thaw-app/Thaw/issues/709), [#372](https://github.com/thaw-app/Thaw/issues/372)).
2. It went back to Hidden a few minutes after being moved, and in 2.0.0-beta.13 it wouldn't stay anywhere ([#651](https://github.com/thaw-app/Thaw/issues/651), [#575](https://github.com/thaw-app/Thaw/issues/575), [#643](https://github.com/thaw-app/Thaw/issues/643)).
3. Clicking it while hidden made Thaw's own icon chase the cursor ([#332](https://github.com/thaw-app/Thaw/issues/332)).
4. Its agent came back twice after the Mac woke from sleep ([#641](https://github.com/thaw-app/Thaw/issues/641)).
5. On macOS 27 it was missing from Thaw altogether, and clicking it opened Thaw's hidden items, until its GUI Scripting option was turned on ([#1179](https://github.com/thaw-app/Thaw/issues/1179), [#1220](https://github.com/thaw-app/Thaw/issues/1220)).

Each one took a fix or a workaround in Thaw, and some still need people to ⌘-drag the icon by hand. An item that comes from your own app's process, with a fixed name, avoids all of it.

## Answer Accessibility requests quickly

Thaw reads every app's menu bar items through Accessibility, the system interface that lets one app inspect another's. It asks each app in turn and gives each one only a short time to answer, so that one slow app can't hold up the whole menu bar. An app that doesn't answer in time is skipped for a few seconds, and while Thaw can't see its items it may move them, or leave them out of Layout.

Keep long work off the main thread, at launch most of all, when many apps start at once and Thaw reads the whole menu bar for the first time.

## Let each item be hidden on its own

macOS 27 hides menu bar items by app, not by item. Thaw can tell macOS which apps' items to hide, so all of one app's items go to Hidden together, and one item left in Visible keeps the others there too. This is on the [roadmap as blocked by macOS 27](https://www.getthaw.app/roadmap#blocked-by-macos-27).

The way round it is to show each item that should hide on its own from a separate app, with its own bundle identifier. Barometer tried this in [Barometer#4](https://github.com/mackid1993/Barometer/pull/4), with a small helper app inside the main one that shows a single item:

1. Build the helper as an app of its own, with its own bundle identifier, such as `com.example.app.gpu`. Set `LSUIElement` to true in its `Info.plist`, so it has no Dock icon.
2. Put it inside the main app, at `Contents/Library/LoginItems/`.
3. In the helper, check `Bundle.main.bundleIdentifier` before you touch `NSStatusBar`, and make its one item as described above.
4. Sign the helper first, under its own identifier, and then the main app, so the main app's signature covers a helper that is already signed.
5. Start the helper from the main app, for example with `SMAppService.loginItem(identifier:)`, and make sure only one copy of it runs.

On macOS 27, a menu bar manager then lists the helper's item on its own, and can hide it while the main app's items stay visible.

## Other things that cost an item its place

- **Don't edit saved positions.** Leave AppKit's visibility and position defaults, and Control Center's preferences, alone. An app that wrote to Control Center's preferences sent its own icon to Hidden in Thaw and other menu bar managers ([#605](https://github.com/thaw-app/Thaw/issues/605)).
- **Don't reorder items from code.** Leave where an item sits to macOS and the person using it.
- **Keep your own menu bar hiding off.** If your app can hide other menu bar items itself, turn that off while Thaw is running, or ask people to use one or the other. Two apps arranging the same bar undo each other's work.
- **Let `LSUIElement` make it an agent.** Setting the `.accessory` activation policy before the run loop starts gives items no height on macOS 27, and no manager can place them.
- **Test from `/Applications`.** The same app launched from a build folder can get items with no height. Install it before you judge how it works with a manager.
- **Run one copy, and expect to be relaunched.** A second launch should hand over to the first one and quit. To apply a new menu bar spacing, Thaw asks apps with menu bar items to quit and opens them again, and an app that also restarts its own helper ends up with two icons.

## Check it

1. Open Menu Bar Layout in Thaw's Settings, and put each of your items in a section.
2. Quit your app and open it again.
3. If an item only shows some of the time, hide and show it a few times.
4. Check that each item is listed once, under its own name, in the section you put it in.

If it isn't and you've followed this page, [open an issue](https://github.com/thaw-app/Thaw/issues) with your app's bundle identifier and the autosave names of its items.
