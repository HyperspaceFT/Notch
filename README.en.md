# Notch

[简体中文](README.md) | **English**

> A "Dynamic Island" for the notch on macOS.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Heavy Vibe Coded](https://img.shields.io/badge/Heavy%20Vibe%20Coded-🤖-ff69b4)
![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue)

> [!WARNING]
> **This project is Heavy Vibe Coded.**
>
> Nearly all the code, scripts, and docs in this repository were written by AI ([Claude Code](https://claude.com/claude-code)). The author only describes what they want, checks the result, and makes the calls, **without reviewing the code line by line**.
> It works and looks good, but treat it as a personal toy project: it may have bugs and may stop working on a future macOS. Use it at your own risk. Issues are welcome.

---

## What it does

Move the pointer onto the notch and it bounces and grows a little (with a light tap on a Force Touch trackpad). Click it and it opens into a small black panel; move away and it shrinks back into the hardware notch. Drag files toward the notch and it opens straight to the Files tab before they reach the top edge of the screen, where macOS would open Mission Control.

Built-in features:

| Feature | Description |
|---|---|
| 🎧 AirPods | Connecting AirPods briefly shows an AirPods icon left of the notch and the battery level right of it. While they are connected, an AirPods tab appears in the open panel just left of the notch: it shows the left, right, and case battery levels and adjusts the AirPods' volume and noise-control mode (Noise Cancellation / Transparency / Adaptive, depending on the model). When the sound switches back to the Mac's own speakers (for example, when the AirPods disconnect), a Mac icon and the current volume briefly show beside the notch too; this part needs no Bluetooth access. macOS's own connection notice cannot be hidden and still appears. Needs Bluetooth access; noise control uses undocumented system interfaces and may stop working after a macOS update |
| 🏠 Home | The home tab of the panel: a row of modules, left to right; for now there are five, the time, the weather, the calendar, notes, and reminders. At its narrowest the time is a square with hours, minutes, and the date; wider, it adds seconds; a click on it opens the Timer tab (see below). At its narrowest the weather takes a third of the row, with the current weather on top and the next three hours below; wider, the current weather sits on the left and more hours appear on the right as it grows. The open island is as wide as its modules, with no black margins, up to a limit that grows with their number: 520 points for one module, 120 more each for the second and the third, and only 80 more for the fourth so the island does not get too wide, 840 at most for four; modules under 520 points in all keep the island at 520. Other tabs keep the original width, and switching tabs animates between the two. In the **Home** pane of **Settings…** you pick the modules (up to four); in the preview, drag the island's edges to scale all modules together, drag the line between two modules to trade their widths, or press and hold a module to move it. The ✕ in a module's top-right corner removes it, and a hint shows when the row is at its longest or shortest |
| ⏱️ Timer | A countdown. The open panel always has a Timer tab right of the notch. With no timer running, it holds a ruler for picking the duration: the selected minutes on top, and below them a row of vertical ticks, one per minute, from 0 to 120 minutes. The selected tick sits in the middle, orange and tallest, sticking out above and below, and the ticks beside it ease back to the normal length toward the left and right; every 10 minutes a tick stands a little taller, to help you find your way. Swipe left or right with two fingers on the trackpad to pick: the ticks follow your fingers and settle on a whole minute when you lift them (or, with momentum, when they stop). Each minute you pass gives a light tap on a Force Touch trackpad, like the pickers on iPhone (felt only while a finger is on the trackpad). You can also drag the ruler, click a tick, or turn a mouse wheel a minute per notch. Then click **Start** (not possible at 0 minutes). Clicking the time module on Home opens this tab; the **Timer** submenu of the notch's right-click menu also starts 1, 3, 5, 10, 15, 25, or 30 minutes or 1 hour right away, and its **Custom…** opens the Timer tab as well. While it counts down, the tab shows the time left and pauses / resumes, adds a minute, or cancels; its button is an orange ring that shrinks with the time left, and the folded right-side button shows that ring too while no right-side tab is selected. The time module on Home shows the countdown and when it ends. With the island closed, for the first 5 seconds an orange ring sits right left of the notch and the time left right of it; then both sides draw in, the island grows a little past the notch, and an orange band of light lines its edge: it runs down the left side, along the bottom, and up the right side at the start, shortens from the left as time runs out, dims while paused, and takes precedence over Now Playing. Opening the island draws the band along the edge into its top-right end; closing it lets the band run back out along the shrinking edge. Another notice shown over it does the same. Clicking either side opens the Timer tab, and the right-click menu can pause, add time, or cancel too. When time is up, a wiggling bell and **Time's up** show beside the notch and a chime sounds (up to 5 times); a click stops it, or **Restart** runs it again. The last duration you started is remembered, and the ruler opens on it next time. There is one timer at a time, kept in memory only, so it is gone when Notch quits |
| 🌤️ Weather | The weather module on Home: the current temperature and conditions, today's high and low, and the next few hours, in the temperature unit macOS is set to. The day splits into three periods, each showing today's weather, the next few hours, or tomorrow's weather (by default today from 5 to 10, the next hours from 10 to 19, and tomorrow from 19 until 5 the next morning); drag the 24-hour ring in the **Weather** pane of **Settings…** to change them. Needs Location access and uses only your approximate location; the data comes from [Open-Meteo](https://open-meteo.com), and requests carry only the latitude and longitude rounded to two decimals. It also fetches the local sunrise and sunset, which light the island's edge (see **Light and Color** below). Updates only while the panel is open, at most every 15 minutes |
| 📅 Calendar | The calendar module on Home: the events of the next few days, today included (3 by default, 1 to 14), grouped by day. All-day events come first each day, an event in progress is marked **Now**, and events that have ended drop off; the card takes the color of the next event's calendar. Events come from two sources: the macOS Calendar app, including accounts added in **System Settings → Internet Accounts** such as iCloud, Google, or Exchange, where you choose which calendars show; and subscription links, such as Google Calendar's **Secret address in iCal format** or an Outlook **Publish a calendar** ICS link, read-only. A switch in the card's top-right corner (**All / This Mac / Cloud**) shows only the Calendar app's events or only the subscription links'. All of this is set in the **Calendar** pane of **Settings…**, which has the same switch. Reading the Calendar app needs Calendars access, which you can decline if you only use links; a subscription link works like a password, so it is kept on this Mac only, downloaded calendars are not written to the disk cache, and they update while the panel is open, at most every 15 minutes. Shortly before an event the notch reminds you: pick how early in the **Calendar** pane of **Settings…** (Off, At Start, or 1, 5, 10, 15, or 30 minutes or 1 hour before; 5 minutes by default). One reminder shows at that time (**In 5 min**) and another as the event starts (**Starting now**); events due together share one. A reminder that comes due while the island is open waits until it closes and then shows in full, unless its events are over by then. Reminders cover the calendars shown in settings and the enabled links, whatever the card's **All / This Mac / Cloud** switch says, skip all-day events, and work whether or not the calendar module is on Home. Click a reminder to see the event; when it has a Zoom, Google Meet, Teams, Tencent Meeting, Feishu, DingTalk, or Webex link, **Join** opens it. The Calendar app's own alerts still appear (in the island too, with Notifications on); turn one of them off to avoid doubles. With reminders on, subscription links also update every 30 minutes while the island is closed |
| 📝 Notes | Jot down notes and short essays. A Notes tab sits among the tabs right of the notch, after Battery: the list of notes on the left, newest first, with **Delete** in the right-click menu, and the note itself on the right, ready to write in. You can also put the notes module on Home; when it is narrow it shows only the note, with arrows above it to step through the notes and **+** to start a new one. With the module on Home, clicking the Notes tab grows the module into the tab, and going back to Home shrinks it into place. One click on the text and you can type, without leaving the app you are in; while you type, moving the pointer off the island does not close it, and a click elsewhere or Esc ends editing; once the island closes, the keyboard goes back to the app you were in. Notes save as you type, blank notes are dropped when you move on, and everything stays on this Mac (`~/Library/Application Support/io.github.hyperspaceft.notch/Notes.json`) |
| ✅ Reminders | The reminders module on Home: the open reminders from the Reminders app. Add it to Home in the **Home** pane of **Settings…**; it has no tab of its own. Type in the top line and press Return to add a reminder to the Reminders app's default list; click the circle to check one off, and click it again within a second and a half to undo; the right-click menu deletes a reminder or opens it in the Reminders app. Reminders with a due date come first, earliest at the top, with overdue ones in red; those without one follow, newest first. Typing works as in Notes: you stay in the app you are in, and Esc ends it. Changes go straight into the Reminders app and reach your other devices through iCloud. Needs Reminders access, which is asked for only the first time you click **Allow** on the card |
| 📂 Files | On the left, an AirDrop zone: drop files on it to send them with AirDrop. On the right, a shelf: files dropped there can be dragged out again, or copied with the right-click **Copy** item and pasted elsewhere. Command-click files on the shelf to select several, Shift-click to select a run of them, or drag with Shift held (or from empty space) to select them with a rectangle; after a click on the shelf, Command-A selects them all; dragging out, Copy, Show in Finder, and Remove then act on every selected file. With **Remove after pasting** on, files leave the shelf once they are dragged out or pasted (the originals are kept) |
| 🔋 Battery | Plugging in the power adapter briefly shows a green charging battery left of the notch and the charge level right of it; unplugging shows a notice too. In the open panel, the battery icon (on the folded button right of the notch, or among the unfolded right-side tabs) follows the charge level; its tab shows the time remaining and the battery health (maximum capacity, cycle count) |
| 🔊 Volume & Brightness | The volume and brightness keys show Notch's own notice beside the notch instead of the system one: an icon on the left and a ring with the current level on the right; hold Option + Shift for finer steps. Needs Accessibility access (see the installation steps below), and can be turned off in the **Island** pane of **Settings…** |
| 🎵 Now Playing | While the system's Now Playing has something (a YouTube or Bilibili tab in a browser, Music, Spotify, and so on), the notch extends a little to each side: right beside it on the left, the cover (the player's icon when there is none), which flips over like a record sleeve when the track changes; on the right, three thin braided strands of a wave, swinging to a beat and flowing sideways. Click the wave to pause, and it calms into a single flat line; click again to play. With the pointer on the island, it grows and the cover and the wave move out with it a little; on the wave, the wave turns into a pause or play icon. The beat is made up per song (each song has its own, and the same one every time); it is not the real audio spectrum. With Light and Color on, the cover casts a glow in its own colors and the wave takes its colors. After a pause it stays for 30 seconds before it leaves. While a track is playing or paused, the open panel has a **Now Playing** tab left of the notch (after Files, before AirPods): a large cover on the left, which brings the playing app to the front when clicked; on the right, the app's name, the title, artist, and album, a progress bar you can click or drag to jump around in the track (with the time played and left; hidden for live streams and anything else without a length), and previous, play / pause, and next buttons. Clicking the cover beside the notch opens the island straight onto this tab, and the cover and the wave fly to their places in it, then back beside the notch as it closes; opening or closing midway turns them around from where they are. By default only Music and Spotify are read, which needs Automation access (to let Notch control them); with **Read Now Playing from Any App** on in the **Island** pane of **Settings…**, the bundled third-party mediaremote-adapter reads any app in the system's Now Playing instead (browsers included). **That switch carries some risk; read the note below before turning it on** |
| 🔔 Notifications | When another app shows a notification banner, the notch extends to each side for a few seconds: the app's icon and name on the left, the title and the first line of the text on the right; a notification arriving while another still shows blurs in over it; while the pointer rests on the island, it grows and the icon and text move out with it. A click on the icon or the text opens the island on that notification alone: its source (the app's icon, name, and when it arrived) on the left, the title and the full text on the right, scrolling when it is long; this view has no tab buttons along the top and closes once the pointer moves away. While there are notifications, a Notifications tab joins the tabs right of the notch (after Notes) and lists the latest 30 in full, newest first: click one to switch to its app and remove it from the list; right-click to delete one, or clear them all at once. Notifications are kept in memory only, never written to disk, and are gone when Notch quits. macOS has no public way to read other apps' notifications, so Notch, like boring.notch, reads the banners on screen through Accessibility access. It therefore sees only banners that actually appear: notifications whose alert style is None, or that a Focus holds back, are missed, and a macOS update that changes the banner's interface may break it. You can turn it off in the **Island** pane of **Settings…**, which also has **Hide System Banners** (off by default): the system banner then moves off screen and shows only in the island, but it can flash briefly before it moves, and its buttons (such as Reply) are out of reach, so open the app from the island to act on it; alerts that stay until you click a button (such as Calendar's Snooze) are not hidden. Should Notch quit unexpectedly while it hides a banner, it moves the banner back the next time it opens; if later banners still do not appear, run `killall NotificationCenter` in Terminal to bring them back |

> [!WARNING]
> **"Read Now Playing from Any App" is a risky feature, and it is off by default.** Since macOS 15.4 only Apple-signed programs may read the system's Now Playing information. To get around that, with the switch on Notch has the system's own `/usr/bin/perl` load a prebuilt third-party library, [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause, taken unmodified from boring.notch and kept in `Vendor/MediaRemoteAdapter/`): code that is not Apple's then runs under an Apple identity and passes a privacy restriction macOS sets on purpose. Notch cannot check what that binary does beyond its published source, and any macOS update may block it. Although most notch apps on the market use this method, that does not stop it from being a fairly dangerous way to do it. Without it, Now Playing still shows Music and Spotify; with it on, Notch falls back to that by itself if the adapter cannot run on your Mac.

The interface is available in English and Simplified Chinese. It follows the system language by default, and you can switch it under **Settings…** in the right-click menu; the change applies right away. **Settings…** also has an **Open at Login** switch that starts Notch when you log in.

The **General** pane of **Settings…** has a **Light and Color** switch (on by default). Cards are lit from above with a fine rim; the weather, calendar, charging, low-battery, and AirDrop cards take a color from what they show; and large numbers get a slight sheen. Once open, the island's edge follows the sky: by day a soft halo marks where the sun stands (rising on the left side, at the bottom center at noon, setting on the right), turning more orange the closer it is to sunrise or sunset; after sunset moonlight takes over, climbing the right side and crossing the top from right to left (partly hidden behind the notch around midnight) to come down the left side at sunrise, so the light goes once around the island a day; the fuller the moon, the brighter and larger its halo. Sunrise and sunset come from the Weather module and are kept, so they still serve while the weather has not refreshed; until they are first fetched, Notch assumes sunrise at 6:00 and sunset at 18:00. With the switch off, cards are plain gray.

The **Debug Mode** switch at the bottom of the **General** pane (off by default) is for checking how the interface looks. With it on, **Settings…** gets a **Debug** pane that lists actions grouped by source; one click shows the matching view on the notch at once, with sample data where needed, so you need not wait for a real notification, weather, or device. The first group is the **Island** itself: Expand and Keep Open, Hover and Keep, Collapse and Keep, and Follow the Pointer Again. Since the pointer is in the settings window and not on the island, an island opened from there closes again after about a second and a half; the first three keep it as it is until you choose Follow the Pointer Again, close Settings, or turn Debug Mode off. After that come the features' own actions: for now Timer, Calendar (event reminders), Weather, Notifications, Now Playing, AirPods, Battery, Volume & Brightness, and Files. Home, Notes, and Reminders show your own content and have none. The actions only show sample content: they do not change your notes, reminders, calendars, the files on the shelf, or any setting, and do not control the system volume, brightness, or other apps. Turn the switch off and the **Debug** pane goes away.

More features are planned; see the [roadmap](#roadmap) below.

## Requirements

- **macOS 26 or later** (the interface uses macOS 26's Liquid Glass)
- **A MacBook with a notch** (Apple Silicon). Screens without a notch show a simulated one.

## Installation

Download the latest `Notch-x.y.z.zip` from the [Releases](https://github.com/HyperspaceFT/Notch/releases) page, then:

1. Unzip it and drag `Notch.app` into your Applications folder;
2. Double-click it. The app is not notarized by Apple, so macOS blocks it and says it cannot verify the developer; click **Done**;
3. Open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway**, and enter your password. It opens normally from then on;
4. On first launch macOS asks for Accessibility access (used to take over the volume and brightness keys and to show notifications in the island). Click **Open System Settings** and turn Notch on in the list. It also asks for Bluetooth access (used to show your AirPods' connection and battery); click **Allow**. The first time you open the notch, it asks for Location access (used to show the local weather) and Calendars access (used to show events from the Calendar app); click **Allow**. Reminders access is asked for only when you first click **Allow** on the Reminders card. The first time Notch reads Music or Spotify, macOS asks whether Notch may control them (Automation, used to read the current track and to pause and play); click **Allow**.

Or remove the download quarantine flag in Terminal and open it directly:

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

If the volume and brightness notices fall back to the system ones after an update, or notifications stop showing in the island, select Notch in **System Settings → Privacy & Security → Accessibility**, remove it with **−**, then open Notch and allow it again. The app has no formal Apple signature, so macOS treats a new version whose signature changed as a different app.

To quit: move the pointer onto the notch, wait for it to grow, right-click, and choose **Quit**.

## Building from source

**No Xcode needed**, only the Command Line Tools:

```bash
xcode-select --install
```

Then:

```bash
git clone https://github.com/HyperspaceFT/Notch.git
cd Notch
make run
```

The built app is at `build/Notch.app` and can be opened directly. Run `make cert` once first to create a local signing certificate; otherwise Accessibility access has to be granted again after every rebuild. See [Local signing certificate](#local-signing-certificate) below.

Common commands:

| Command | Effect |
|---|---|
| `make build` | Release build to `build/Notch.app` |
| `make debug` | Debug build |
| `make run` | Build and (re)launch the app |
| `make test` | Run the unit tests |
| `make dist` | Zip it into `build/dist/Notch-<version>.zip` for sharing |
| `make clean` | Delete all build output |
| `make cert` | Create a local signing certificate so Accessibility access survives rebuilds |

For debugging you can pin the island in one state, and `-NotchDebugSnapshot` also exports the interface as an image (no Screen Recording permission needed, but the image has no Liquid Glass):

```bash
open build/Notch.app --args -NotchDebugState expanded   # or activity / collapsed
open build/Notch.app --args -NotchDebugState expanded -NotchDebugSnapshot /tmp/notch.png
```

### Local signing certificate

By default a build only gets an ad-hoc signature, which differs on every build. macOS then treats each build as a new app, and the Accessibility access granted before stops working until you remove Notch and allow it again.

Create a local signing certificate in your keychain once, and every later build is signed with it: the signature no longer changes, and the access stays. Run this once:

```bash
make cert
```

It:

1. creates a self-signed code-signing certificate named "Notch Local Signing", valid for 10 years;
2. imports the certificate and its private key into the login keychain and lets `codesign` use them without asking during builds.

From then on `make build`, `make debug`, and `make run` sign with it, and the build output shows `==> Signing (Notch Local Signing)`. Without it in the keychain, builds fall back to an ad-hoc signature and show `==> Signing (ad-hoc; …)`.

The certificate is only for signing Notch on this Mac. Because it is self-signed, Keychain Access marks it as "not trusted"; that does not affect signing, and no trust settings need changing.

On the first run after switching to the certificate, remove the old Notch from **System Settings → Privacy & Security → Accessibility** with **−** and allow it again one last time. Later rebuilds keep the access.

To stop using it, open Keychain Access and delete "Notch Local Signing" from My Certificates in the login keychain; later builds go back to ad-hoc signatures.

## Project structure

The project is one Swift Package, split into a shell plus pluggable features, with dependencies pointing one way:

```
Sources/
├── NotchKit/        # The features' contract: NotchFeature, NotchActivity, NotchContext, Home modules, right-click menu entries, interface language
├── NotchUI/         # Design system: notch shape, theme, animations, Liquid Glass buttons, shared controls
├── NotchShell/      # The shell: window, screen/notch placement, hover, state machine, root view
├── Features/        # One folder per feature, depending only on NotchKit + NotchUI
│   ├── Battery/
│   ├── Calendar/
│   ├── Clock/
│   ├── Files/
│   ├── Home/
│   ├── Notes/
│   ├── Notifications/
│   ├── NowPlaying/
│   ├── Reminders/
│   ├── SystemHUD/
│   └── Weather/
└── NotchApp/        # Executable entry point and settings window; FeatureCatalog.swift lists the enabled features
Tests/               # Unit tests
Resources/Info.plist # App info template
scripts/             # Build, run, and packaging scripts
Vendor/              # Prebuilt third-party component shipped in the app (mediaremote-adapter, BSD 3-Clause)
VERSION              # Version number
```

```
NotchApp ──▶ NotchShell ──▶ NotchKit
    │            └────────▶ NotchUI
    └──▶ Features/* ──▶ NotchKit + NotchUI
```

The island has three states:

- **collapsed**: exactly the size of the hardware notch, so it is invisible;
- **activity**: when a feature presents a live activity, the island extends to both sides and shows content there (such as the charging notice);
- **expanded**: after a click, the panel opens with the features' tabs along the top and the selected feature's content below. Home, Files, Now Playing while a track is known, and AirPods while connected sit left of the notch. The tabs right of it (Timer, Battery, Notes, and Notifications while there are any) fold into one button just right of the notch, showing the selected right-side tab when one is selected, else the timer's ring while it counts down, else the right-side feature you used last; with the pointer on it, it unfolds to the right into all the right-side tabs, a click picks one, and it folds again once the pointer leaves.

While the pointer rests on the collapsed or activity island, it grows a little with a slight bounce (hovered), its bottom corners growing with it so they stay concentric with the original ones. A click then opens it, and a right-click shows the menu (**Timer**, **Settings…**, and **Quit**).

## Adding a feature

A new feature takes three steps:

1. Create a folder `Sources/Features/<Name>/` with a class that conforms to `NotchFeature`;
2. Add `"<Name>"` to the `featureNames` array in `Package.swift`; this generates a `<Name>Feature` module and links it into the app;
3. In `Sources/NotchApp/FeatureCatalog.swift`, `import <Name>Feature` and add an instance to the list. The list order is the tab order in the open panel; tabs sit left of the notch by default, and setting `tabPlacement` to `.trailing` puts them on the right; while `isTabAvailable` is `false` the tab is hidden (for example, AirPods while they are not connected); while a right-side tab's `isTabActive` is `true` (for example, a timer counting down), the folded right-side button shows its icon.

Features talk to the shell through `NotchContext`, e.g. `present(_:)` shows a live activity and `dismiss(activityID:)` removes it; `requestExpand(detail:)` opens the island on one view alone, without the tab buttons along the top (a notification's detail, for one). See `Sources/Features/Battery` for an example.

A feature can also implement `makeHomeModules()` to offer modules for the Home tab (`NotchHomeModule`), stating their minimum and maximum widths, or a fixed width, with `HomeModuleSizing`; the user can then place them on Home in the **Home** pane of **Settings…**. See `Sources/Features/Weather` for an example. A feature whose tab needs more room can give the open island's width with `expandedWidth` (520 to 880 points); that is how Home widens with its modules.

Through `menuItems` a feature can add entries to the notch's right-click menu (`NotchMenuItem`: buttons, submenus, and dividers), shown above **Settings…** and free to follow the feature's state. See `Sources/Features/Clock` for an example.

Through `debugItems` (also `NotchMenuItem`s) a feature can add actions to the **Debug** pane of **Settings…**, shown only while **Debug Mode** is on in the **General** pane. Each action shows one of the feature's views at once with sample data, for checking how it looks; none may change the user's own data or act on the system or other apps. Like `menuItems`, they are read while the pane draws. A feature whose content is the user's own data (Home, Notes, Reminders) has none.

Write interface text with `localized(en:zh:)`, giving both the English and the Chinese, and read it while the view draws (for example, make `title` a computed property) so it updates as soon as the language changes.

## Roadmap

- [x] 🎵 Now Playing (browsers, Music, Spotify, and more; click to pause / play)
- [x] 📂 File shelf (drag files onto the notch to keep them)
- [x] 🔊 Replace the system volume / brightness HUD
- [x] 🎧 AirPods connection notice and headphone settings (battery, volume, noise control)
- [x] 🌤️ Weather, a customizable Home layout (pick, order, and size modules), and weather periods
- [x] 📅 Calendar (the Calendar app and subscription links for Google, Outlook, and other calendars), with Home widening by its modules
- [x] ⏰ Event reminders (with a choice of how early, and joining online meetings directly)
- [x] 📝 Notes (a tab and a Home module)
- [x] ✅ Reminders (a Home module, reading and writing the Reminders app)
- [x] 🔔 Notifications (other apps' banners in the island, optionally hiding the system banner)
- [x] ⏱️ Timer (a tab right of the notch with a ruler for the duration, also started from Home's time module or the right-click menu, counting down beside the notch)
- [x] ⚙️ Settings window (launch at login, Light and Color, Debug Mode, the volume/brightness HUD switch, the notification switches, the Home layout, weather periods, the calendar, and language for now)
- [x] 🚀 Launch at login
- [ ] 🔄 Automatic updates

## Acknowledgements

Ideas for this project came from these excellent open-source projects:

- [boring.notch](https://github.com/TheBoredTeam/boring.notch)
- [NotchDrop](https://github.com/Lakr233/NotchDrop)
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)

## License

Copyright (C) 2026 [HyperspaceFT](https://github.com/HyperspaceFT)

This project is released under the [GNU General Public License, version 3 (GPL-3.0)](LICENSE), or, at your option, any later version.

In short:

- ✅ You may use, copy, modify, and distribute it freely, including modified versions;
- 📌 When distributing, keep the original copyright notice and include this license;
- 📌 Modified versions must say what was changed, and **must also be released under the GPL-3.0 with their complete source code**; they cannot be closed source.

This is only a plain-language summary; the [LICENSE](LICENSE) text is what applies.
