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
| 🎧 AirPods | Connecting AirPods briefly shows an AirPods icon left of the notch and the battery level right of it. While they are connected, an AirPods tab appears at the far left of the open panel: it shows the left, right, and case battery levels and adjusts the AirPods' volume and noise-control mode (Noise Cancellation / Transparency / Adaptive, depending on the model). macOS's own connection notice cannot be hidden and still appears. Needs Bluetooth access; noise control uses undocumented system interfaces and may stop working after a macOS update |
| 🏠 Home | The home tab of the panel; shows the current time for now |
| 📂 Files | On the left, an AirDrop zone: drop files on it to send them with AirDrop. On the right, a shelf: files dropped there can be dragged out again, or copied with the right-click **Copy** item and pasted elsewhere. With **Remove after pasting** on, files leave the shelf once they are dragged out or pasted (the originals are kept) |
| 🔋 Battery | Plugging in the power adapter briefly shows a green charging battery left of the notch and the charge level right of it; unplugging shows a notice too. In the open panel, the battery icon right of the notch follows the charge level; its tab shows the time remaining and the battery health (maximum capacity, cycle count) |
| 🔊 Volume & Brightness | The volume and brightness keys show Notch's own notice beside the notch instead of the system one: an icon on the left and a ring with the current level on the right; hold Option + Shift for finer steps. Needs Accessibility access (see the installation steps below), and can be turned off in the **Island** pane of **Settings…** |

The interface is available in English and Simplified Chinese. It follows the system language by default, and you can switch it under **Settings…** in the right-click menu; the change applies right away. **Settings…** also has an **Open at Login** switch that starts Notch when you log in.

More features are planned; see the [roadmap](#roadmap) below.

## Requirements

- **macOS 26 or later** (the interface uses macOS 26's Liquid Glass)
- **A MacBook with a notch** (Apple Silicon). Screens without a notch show a simulated one.

## Installation

Download the latest `Notch-x.y.z.zip` from the [Releases](https://github.com/HyperspaceFT/Notch/releases) page, then:

1. Unzip it and drag `Notch.app` into your Applications folder;
2. Double-click it. The app is not notarized by Apple, so macOS blocks it and says it cannot verify the developer; click **Done**;
3. Open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway**, and enter your password. It opens normally from then on;
4. On first launch macOS asks for Accessibility access (used to take over the volume and brightness keys). Click **Open System Settings** and turn Notch on in the list. It also asks for Bluetooth access (used to show your AirPods' connection and battery); click **Allow**.

Or remove the download quarantine flag in Terminal and open it directly:

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

If the volume and brightness notices fall back to the system ones after an update, select Notch in **System Settings → Privacy & Security → Accessibility**, remove it with **−**, then open Notch and allow it again. The app has no formal Apple signature, so macOS treats a new version whose signature changed as a different app.

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
├── NotchKit/        # The features' contract: NotchFeature, NotchActivity, NotchContext, interface language
├── NotchUI/         # Design system: notch shape, theme, animations, Liquid Glass buttons, shared controls
├── NotchShell/      # The shell: window, screen/notch placement, hover, state machine, root view
├── Features/        # One folder per feature, depending only on NotchKit + NotchUI
│   ├── Battery/
│   ├── Files/
│   ├── Home/
│   └── SystemHUD/
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
- **expanded**: after a click, the panel opens with the features' tabs along the top (AirPods while connected, Home, and Files left of the notch, Battery right of it) and the selected feature's content below.

While the pointer rests on the collapsed or activity island, it grows a little with a slight bounce (hovered). A click then opens it, and a right-click shows the **Settings…** / **Quit** menu.

## Adding a feature

A new feature takes three steps:

1. Create a folder `Sources/Features/<Name>/` with a class that conforms to `NotchFeature`;
2. Add `"<Name>"` to the `featureNames` array in `Package.swift`; this generates a `<Name>Feature` module and links it into the app;
3. In `Sources/NotchApp/FeatureCatalog.swift`, `import <Name>Feature` and add an instance to the list. The list order is the tab order in the open panel; tabs sit left of the notch by default, and setting `tabPlacement` to `.trailing` puts them on the right; while `isTabAvailable` is `false` the tab is hidden (for example, AirPods while they are not connected).

Features talk to the shell through `NotchContext`, e.g. `present(_:)` shows a live activity and `dismiss(activityID:)` removes it. See `Sources/Features/Battery` for an example.

Write interface text with `localized(en:zh:)`, giving both the English and the Chinese, and read it while the view draws (for example, make `title` a computed property) so it updates as soon as the language changes.

## Roadmap

- [ ] 🎵 Now Playing / media controls
- [ ] 📅 Calendar and Reminders
- [x] 📂 File shelf (drag files onto the notch to keep them)
- [x] 🔊 Replace the system volume / brightness HUD
- [x] 🎧 AirPods connection notice and headphone settings (battery, volume, noise control)
- [x] ⚙️ Settings window (launch at login, the volume/brightness HUD switch, and language for now)
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
