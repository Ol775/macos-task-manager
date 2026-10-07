<div align="center">

<img src="Assets/AppIcon-1024.png" width="128" alt="Task Manager icon">

# Task Manager

**A fast, native task manager for macOS.** Live CPU, memory, GPU, disk and network graphs, a sortable process list with details and End Task, system information, and light, dark and OLED Black themes.

[![CI](https://github.com/Ol775/macos-task-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/Ol775/macos-task-manager/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![Apple silicon & Intel](https://img.shields.io/badge/universal-arm64%20%7C%20x86__64-lightgrey)

<img src="docs/processes.png" width="760" alt="Processes">

</div>

## Features

| | |
|---|---|
| **Processes** | Apps and all processes, sortable and searchable, with a **column picker** (CPU, Memory, Disk, PID, User, Threads, State, Started) and a confirmed **End Task**. |
| **Process details** | Double-click a process for its path (with Reveal in Finder), parent, open files, code-signature status and open TCP/UDP ports. |
| **Performance** | Live 60-second graphs for **CPU**, **Memory**, **GPU**, **Disk** (read / write) and **Network** (send / receive, per interface), with core layout, wired and compressed memory, GPU memory and thermal state. |
| **System** | Model, chip, core layout, memory, graphics, macOS version and build, up time, thermal state, storage and battery. |
| **Personalise** | Settings are a page inside the window (⌘,). System / Light / Dark / **OLED Black** appearance, accent colour, card corners, per-graph colours, update speed from 0.5 s to 5 s. |
| **Permissions check** | Settings → Permissions shows exactly what the app can see and why some system processes are hidden. |
| **Signed updates** | Checks GitHub releases and installs only Ed25519-signed builds. See [SECURITY.md](SECURITY.md). |

<p align="center">
  <img src="docs/details.png" width="49%" alt="Process details">
  <img src="docs/cpu.png" width="49%" alt="CPU">
</p>
<p align="center">
  <img src="docs/disk.png" width="49%" alt="Disk">
  <img src="docs/network.png" width="49%" alt="Network">
</p>
<p align="center">
  <img src="docs/light.png" width="49%" alt="Light theme">
  <img src="docs/oled.png" width="49%" alt="OLED Black theme">
</p>

## Install

**Homebrew** (clears the first-launch block for you):

```sh
brew install --cask Ol775/tap/task-manager
```

**Or download** `Task-Manager-<version>.dmg` from [Releases](../../releases), open it and drag **TaskManager** to Applications. Builds are universal (Apple silicon and Intel) and need macOS 15 or later.

The app is ad-hoc signed, not notarized (that needs a paid Apple Developer ID), so macOS blocks the first launch of a downloaded DMG (the Homebrew install avoids this). Either:

- open **System Settings → Privacy & Security**, scroll to the message about *TaskManager* and click **Open Anyway** (on macOS 15 and later the old right-click → Open shortcut no longer works), or
- run `xattr -dr com.apple.quarantine /Applications/TaskManager.app` once in Terminal.

After that, in-app updates install without any prompt, because the app downloads and verifies them itself.

## Build from source

Requires Xcode 16+ (the Swift 6 toolchain):

```sh
git clone https://github.com/Ol775/macos-task-manager.git
cd macos-task-manager
./build-app.sh && open TaskManager.app
TaskManager.app/Contents/MacOS/TaskManager --selftest   # updater, sampling and contrast checks
```

## Privacy

No telemetry, accounts or analytics. The only network request is the update check against this repository's GitHub releases (Settings → General turns it off). Hostname and serial number are never read.

## Limits

macOS only lets an unprivileged app inspect processes owned by the same user, so system and other users' processes aren't listed. Settings → Permissions shows the count.

## Roadmap

A menu bar mode, alerts and a per-core CPU view are next. See [ROADMAP.md](ROADMAP.md).

## Releasing

`./bump.sh minor "note"` updates `VERSION` and the changelog. After building and pushing, `./release.sh "note"` builds the universal DMG, signs it with the offline release key and publishes the GitHub release. `tools/makeicon.swift` regenerates the icon.

## License

[MIT](LICENSE) © 2026 Ol775
