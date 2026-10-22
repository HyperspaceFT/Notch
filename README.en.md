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

Move the pointer onto the notch and it bounces and grows a little (with a light tap on a Force Touch trackpad). Click it and it opens into a small black panel; move away and it shrinks back into the hardware notch. Drag files onto the notch and it opens straight to the Files tab.

Built-in features:

| Feature | Description |
|---|---|
| 🏠 Home | The first tab of the panel; shows the current time for now |
| 📂 Files | On the left, an AirDrop zone: drop files on it to send them with AirDrop. On the right, a shelf: files dropped there can be dragged out again, or copied with the right-click **Copy** item and pasted elsewhere. With **Remove after pasting** on, files leave the shelf once they are dragged out or pasted (the originals are kept) |
| 🔋 Battery | Plugging in the power adapter briefly shows a green charging battery left of the notch and the charge level right of it; unplugging shows a notice too. In the open panel, the battery icon right of the notch follows the charge level; its tab shows the time remaining and the battery health (maximum capacity, cycle count) |

The interface is available in English and Simplified Chinese. It follows the system language by default, and you can switch it under **Settings…** in the right-click menu; the change applies right away. **Settings…** also has an **Open at Login** switch that starts Notch when you log in.

More features are planned; see the [roadmap](#roadmap) below.

## Requirements

- **macOS 26 or later** (the interface uses macOS 26's Liquid Glass)
- **A MacBook with a notch** (Apple Silicon). Screens without a notch show a simulated one.

## Installation

Download the latest `Notch-x.y.z.zip` from the [Releases](https://github.com/HyperspaceFT/Notch/releases) page, then:

1. Unzip it and drag `Notch.app` into your Applications folder;
2. Double-click it. The app is not notarized by Apple, so macOS blocks it and says it cannot verify the developer; click **Done**;
3. Open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway**, and enter your password. It opens normally from then on.

Or remove the download quarantine flag in Terminal and open it directly:

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

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

The built app is at `build/Notch.app` and can be opened directly.

Common commands:

| Command | Effect |
|---|---|
| `make build` | Release build to `build/Notch.app` |
| `make debug` | Debug build |
| `make run` | Build and (re)launch the app |
| `make test` | Run the unit tests |
| `make dist` | Zip it into `build/dist/Notch-<version>.zip` for sharing |
| `make clean` | Delete all build output |

For debugging you can pin the island in one state, and `-NotchDebugSnapshot` also exports the interface as an image (no Screen Recording permission needed, but the image has no Liquid Glass):

```bash
open build/Notch.app --args -NotchDebugState expanded   # or activity / collapsed
open build/Notch.app --args -NotchDebugState expanded -NotchDebugSnapshot /tmp/notch.png
```

## Project structure

The project is one Swift Package, split into a shell plus pluggable features, with dependencies pointing one way:

```
Sources/
├── NotchKit/        # The features' contract: NotchFeature, NotchActivity, NotchContext, interface language
├── NotchUI/         # Design system: notch shape, theme, animations, Liquid Glass buttons, shared controls
├── NotchShell/      # The shell: window, screen/notch placement, hover, state machine, root view
├── Features/        # One folder per feature, depending only on NotchKit + NotchUI
│   ├── Battery/
│   ├── Files/
│   └── Home/
└── NotchApp/        # Executable entry point and settings window; FeatureCatalog.swift lists the enabled features
Tests/               # Unit tests
Resources/Info.plist # App info template
scripts/             # Build, run, and packaging scripts
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
- **expanded**: after a click, the panel opens with the features' tabs along the top (Home and Files left of the notch, Battery right of it) and the selected feature's content below.

While the pointer rests on the collapsed or activity island, it grows a little with a slight bounce (hovered). A click then opens it, and a right-click shows the **Settings…** / **Quit** menu.

## Adding a feature

A new feature takes three steps:

1. Create a folder `Sources/Features/<Name>/` with a class that conforms to `NotchFeature`;
2. Add `"<Name>"` to the `featureNames` array in `Package.swift`; this generates a `<Name>Feature` module and links it into the app;
3. In `Sources/NotchApp/FeatureCatalog.swift`, `import <Name>Feature` and add an instance to the list. The list order is the tab order in the open panel; tabs sit left of the notch by default, and setting `tabPlacement` to `.trailing` puts them on the right.

Features talk to the shell through `NotchContext`, e.g. `present(_:)` shows a live activity and `dismiss(activityID:)` removes it. See `Sources/Features/Battery` for an example.

Write interface text with `localized(en:zh:)`, giving both the English and the Chinese, and read it while the view draws (for example, make `title` a computed property) so it updates as soon as the language changes.

## Roadmap

- [ ] 🎵 Now Playing / media controls
- [ ] 📅 Calendar and Reminders
- [x] 📂 File shelf (drag files onto the notch to keep them)
- [ ] 🔊 Replace the system volume / brightness HUD
- [ ] 🎧 AirPods connection notice
- [x] ⚙️ Settings window (launch at login and language for now)
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
