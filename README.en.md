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

Move the pointer onto the notch and it bounces and grows a little. Click it and it opens into a small black panel; move away and it shrinks back into the hardware notch. Drag files toward the notch and it opens straight to the Files tab.

| Feature | Description |
|---|---|
| 🎵 Now Playing | While a song plays, the notch extends to each side with the cover and a wave that swings to a beat; click the wave to pause / resume, and it retracts 3 seconds after a pause. The open **Now Playing** tab has a large cover, a progress bar you can drag, and track-skip buttons. By default only Music and Spotify are read (needs Automation access); with **Read Now Playing from Any App** on, any app, browsers included, can be read too, **which carries some risk; see the note below**. The beat is made up per song; it is not the real audio spectrum |
| 🔔 Notifications | When another app shows a notification banner, the notch extends to each side with the app's icon, the title, and the first line of the text; click it to read the full text. The latest 30 are listed in the **Notifications** tab, kept in memory only. macOS has no public way to read notifications, so Notch reads the banners on screen through Accessibility access: it sees only banners that actually appear (notifications whose alert style is None, or that a Focus holds back, are missed), and a macOS update may break it. You can choose **Hide System Banners** so they show only in the island; if system banners then never appear, run `killall NotificationCenter` in Terminal to bring them back. When many notifications arrive within a short time, macOS shows only some of them as banners; turning on **Read the Notification Database Directly** (needs Full Disk Access) fills in the rest, a few seconds late |
| 🏠 Home | The home tab of the open panel: the time, weather, calendar, notes, reminders, and usage modules in a row, four at most. In the **Home** pane of **Settings…** you pick the modules, drag to reorder them, and resize them; the island widens with the number of modules, 840 points at most |
| 📅 Calendar | Lists the events of the next few days by day (3 by default, 1 to 14); click one to expand it to its full text, which you can copy. Events come from the Calendar app (needs Calendars access) or from ICS subscription links such as Google or Outlook (read-only; the links are kept on this Mac only). The notch reminds you shortly before an event (how early is adjustable, 5 minutes by default), and when an event has a Zoom, Google Meet, Teams, Tencent Meeting, Feishu, DingTalk, or Webex link you can join the meeting directly |
| ⏱️ Timer | In the Timer tab right of the notch, pick a duration on a ruler (0 to 120 minutes); swiping with two fingers on the trackpad taps lightly every minute you pass. Clicking the time module on Home opens it too. While it counts down, an orange band of light lines the island's edge, its length showing the time left, and a bell rings when time is up. There is one timer at a time, kept in memory only |
| 📊 Usage Limits | The 5-hour, weekly, and other usage limits of Claude, Codex (ChatGPT plan), and Grok subscriptions, shown in the **Usage** tab and a Home module. In the **Usage** pane of **Settings…**, turn on the AIs to show and sign in once in Notch's own sign-in window (your browser's sign-ins are not read; Google sign-in is not available, so use an email code or a password). It is read only while the panel is open or the **Usage** settings pane is open, at most every 5 minutes per AI. It uses the internal endpoints of the web pages, which are undocumented and may stop working at any time |
| 🌤️ Weather | The current weather, today's high and low, and the forecast for the next few hours; the day splits into three periods, each showing today's weather, the next few hours, or tomorrow's weather, adjustable in the **Weather** pane of **Settings…**, which can also refresh the location and weather on demand. Needs Location access (approximate location only); the data comes from [Open-Meteo](https://open-meteo.com) |
| 📝 Notes | Jot down notes, in a tab of their own or on Home. You type right on the island without switching away from the current app; notes save as you type and stay on this Mac only |
| ✅ Reminders | A Home module: the open to-dos from the Reminders app, which you can add, check off, and delete; changes reach your other devices through iCloud. Needs Reminders access |
| 📂 Files | On the left, an AirDrop zone: drop files on it to send them. On the right, a shelf: files can be dragged out again, or copied and pasted, with multi-select. You can turn on **Remove after pasting** (it only removes files from the shelf, never the originals) |
| 🎧 AirPods | When AirPods connect, the notch shows the earbuds and their battery on both sides; while they are connected an extra tab shows the left, right, and case battery levels and adjusts the volume and noise-control mode. Needs Bluetooth access; noise control uses undocumented system interfaces and may stop working after a macOS update |
| 🔋 Battery | A notice when the power adapter is plugged or unplugged, and one alert each when the charge falls to 20%, 10%, and 5%; the open panel shows the time remaining and the battery health |
| 🔊 Volume & Brightness | The volume and brightness keys show Notch's own notice beside the notch instead of the system one; hold Option + Shift for finer steps. Needs Accessibility access, and can be turned off in settings |

> [!WARNING]
> **"Read Now Playing from Any App" is a risky feature, and it is off by default.** Since macOS 15.4 only Apple-signed programs may read the system's Now Playing information. To get around that, with the switch on Notch has the system's own `/usr/bin/perl` load a prebuilt third-party library, [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause, taken unmodified from boring.notch and kept in `Vendor/MediaRemoteAdapter/`): code that is not Apple's then runs under an Apple identity and passes a privacy restriction macOS sets on purpose. Notch cannot check what that binary does beyond its published source, and any macOS update may block it. Although most notch apps on the market use this method, that does not stop it from being a fairly dangerous way to do it. Without it, Now Playing still shows Music and Spotify; with it on, Notch falls back to that by itself if the adapter cannot run on your Mac.

To open settings: move the pointer onto the notch, wait for it to grow, right-click, and choose **Settings…**. The interface is available in English and Simplified Chinese (it follows the system language by default). Settings also has **Open at Login** and **Light and Color** (cards are tinted by their content, and once open, the island's edge follows the positions of the sun and the moon). **Debug Mode** at the bottom of the **General** pane is for checking the interface; **do not turn it on if you don't know what you're doing**.

## Requirements

- **macOS 26 or later** (the interface uses macOS 26's Liquid Glass)
- **A MacBook with a notch** (Apple Silicon). Screens without a notch show a simulated one.

## Installation

Download the latest `Notch-x.y.z.zip` from the [Releases](https://github.com/HyperspaceFT/Notch/releases) page, then:

1. Unzip it and drag `Notch.app` into your Applications folder;
2. Double-click it. The app is not notarized by Apple, so macOS blocks it and says it cannot verify the developer; click **Done**;
3. Open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway**, and enter your password.

Or remove the download quarantine flag in Terminal and open it directly:

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

The first time you use it, macOS asks for these permissions; allow them as you need:

- **Accessibility**: to take over the volume and brightness keys and to show notifications in the island (asked on first launch; you then turn Notch on in System Settings);
- **Bluetooth**: to show your AirPods' connection and battery (asked on first launch);
- **Location**, **Calendars**: the local weather and the events in the Calendar app (asked the first time you open the notch; Calendars access can be declined if you only use subscription links);
- **Reminders**: asked the first time you click **Allow** on the Reminders card;
- **Automation**: to read and control Music and Spotify (asked the first time Notch reads them);
- **Full Disk Access**: needed only for **Read the Notification Database Directly**; macOS never asks for it, so add Notch yourself in **System Settings → Privacy & Security → Full Disk Access**.

If the volume and brightness notices fall back to the system ones after an update, or notifications stop showing in the island, select Notch in **System Settings → Privacy & Security → Accessibility**, remove it with **−**, then open Notch and allow it again. The app has no formal Apple signature, so macOS treats a new version whose signature changed as a different app.

To quit: move the pointer onto the notch, wait for it to grow, right-click, and choose **Quit**.

## Building from source

**No Xcode needed**, only the Command Line Tools:

```bash
xcode-select --install
git clone https://github.com/HyperspaceFT/Notch.git
cd Notch
make cert   # only needed once, see "Local signing certificate" below
make run
```

The built app is at `build/Notch.app`. Common commands:

| Command | Effect |
|---|---|
| `make build` / `make debug` | Release / Debug build to `build/Notch.app` |
| `make run` | Build and (re)launch the app |
| `make test` | Run the unit tests |
| `make dist` | Zip it into `build/dist/Notch-<version>.zip` |
| `make clean` | Delete all build output |
| `make cert` | Create a local signing certificate |
| `make icon` | Regenerate `Resources/AppIcon.icns` after editing `Resources/AppIcon.svg` |

For debugging you can pin the island in one state, and `-NotchDebugSnapshot` also exports the interface as an image (the image has no Liquid Glass):

```bash
open build/Notch.app --args -NotchDebugState expanded   # or activity / collapsed
open build/Notch.app --args -NotchDebugState expanded -NotchDebugSnapshot /tmp/notch.png
```

### Local signing certificate

Without a certificate, every build only gets an ad-hoc signature, which differs each time, so macOS treats each build as a different app and the Accessibility access stops working. `make cert` creates a self-signed certificate named "Notch Local Signing" in the login keychain (valid for 10 years, usable by `codesign` directly); every later build is signed with it and the access stays. It is only for signing Notch on this Mac, and Keychain Access marking it as "not trusted" does not affect its use.

After switching to the certificate, remove the old Notch from **System Settings → Privacy & Security → Accessibility** and allow it again one last time. To stop using it, delete the certificate in Keychain Access; later builds go back to ad-hoc signatures.

## Project structure

The project is one Swift Package, split into a shell plus pluggable features, with dependencies pointing one way:

```
Sources/
├── NotchKit/        # The features' contract: NotchFeature, NotchActivity, NotchContext, Home modules, right-click menu entries, interface language
├── NotchUI/         # Design system: notch shape, theme, animations, Liquid Glass buttons, shared controls
├── NotchShell/      # The shell: window, screen/notch placement, hover, state machine, root view
├── Features/        # One folder per feature, depending only on NotchKit + NotchUI
└── NotchApp/        # Executable entry point and settings window; FeatureCatalog.swift lists the enabled features
Tests/               # Unit tests
Resources/           # Info.plist template, signing entitlements, app icon (AppIcon.svg is the source)
scripts/             # Build, run, and packaging scripts
Vendor/              # Prebuilt third-party component shipped in the app (mediaremote-adapter, BSD 3-Clause)
VERSION              # Version number
```

```
NotchApp ──▶ NotchShell ──▶ NotchKit
    │            └────────▶ NotchUI
    └──▶ Features/* ──▶ NotchKit + NotchUI
```

The island has three states: **collapsed** (the size of the hardware notch, so you can't see it), **activity** (extends to both sides when a feature presents a live activity, such as the charging notice), and **expanded** (opens after a click, with the features' tabs along the top). While the pointer rests on the notch it grows a little; a click then opens it, and a right-click shows the menu.

## Adding a feature

1. Create a folder `Sources/Features/<Name>/` with a class that conforms to `NotchFeature`;
2. Add `"<Name>"` to `featureNames` in `Package.swift`; this generates a `<Name>Feature` module automatically;
3. In `Sources/NotchApp/FeatureCatalog.swift`, `import <Name>Feature` and add an instance to the list. The list order is the tab order.

A feature can optionally implement:

- `tabPlacement` (whether the tab sits left or right of the notch), `isTabAvailable` (hide the tab for now), `isTabActive` (let the folded right-side button show it);
- `present(_:)` / `dismiss(activityID:)` on `NotchContext` to show and remove live activities, and `requestExpand(detail:)` to open the island on one view alone; see `Sources/Features/Battery`;
- `makeHomeModules()` to offer modules for Home, and `expandedWidth` to make the tab wider (520 to 880 points); see `Sources/Features/Weather`;
- `menuItems` to add entries to the right-click menu, and `debugItems` to add actions to the **Debug** pane (they show only sample content and must not change the user's data or control the system or other apps); see `Sources/Features/Clock`.

Write interface text with `localized(en:zh:)`, giving both the English and the Chinese, and read it while the view draws, so it refreshes as soon as the language changes.

## Roadmap

- [ ] 🔄 Automatic updates

Finished features are listed in [What it does](#what-it-does) above.

## Acknowledgements

Ideas for this project came from these excellent open-source projects:

- [boring.notch](https://github.com/TheBoredTeam/boring.notch)
- [NotchDrop](https://github.com/Lakr233/NotchDrop)
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)

The Claude, Codex, and Grok logos in Usage come from [Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT License); the marks belong to Anthropic, OpenAI, and xAI and are used only to identify their services.

## License

Copyright (C) 2026 [HyperspaceFT](https://github.com/HyperspaceFT)

This project is released under the [GNU General Public License, version 3 (GPL-3.0)](LICENSE), or, at your option, any later version.

In short:

- ✅ You may use, copy, modify, and distribute it freely, including modified versions;
- 📌 When distributing, keep the original copyright notice and include this license;
- 📌 Modified versions must say what was changed, and **must also be released under the GPL-3.0 with their complete source code**; they cannot be closed source.

This is only a plain-language summary; the [LICENSE](LICENSE) text is what applies.
