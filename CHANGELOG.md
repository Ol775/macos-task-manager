# Changelog

## 0.4.3 (2026-10-07)
- **Lighter on your Mac.** Memory use is about halved (roughly 50 MB instead of 100 MB) and CPU use is down by about a third. Graphs are now plain SwiftUI shapes (the GPU renderer they used cost about 45 MB), the app no longer redraws its whole window every second, unchanged process rows are skipped, Apps mode samples only the apps, and All Processes refreshes every 2 seconds.

## 0.4.2 (2026-10-07)
- **Faster and friendlier.** Idle CPU use is about a third of what it was (graphs are drawn directly instead of with Swift Charts, process names and icons are looked up once, and a hidden or minimized window no longer redraws); the Processes page now says when macOS protects some processes, shows a message when a search finds nothing, says "1 process" correctly, and clears the selection when a process ends; End Task shows the PID and path; ad hoc signatures no longer get a green seal; the graph caption no longer overlaps the line.

## 0.4.1 (2026-10-07)
- **Security and accessibility hardening.** Code-signature labels now come from the certificate chain (a look-alike certificate is reported as unverified instead of Apple or Developer ID), update URLs reject path tricks, the installer re-verifies the new app after copying it, rates can no longer crash on NaN or infinity, and the app runs with the hardened runtime. Accessibility: VoiceOver labels and values everywhere, keyboard navigation of the process list (↑ ↓ Return Esc, ⌘I, ⌘⌫), a **Text size** setting, Reduce Motion and Increase Contrast support, and higher-contrast secondary text.

## 0.4.0 (2026-10-07)
- **Menu bar mode**: a live CPU / memory / GPU / disk / network readout in the menu bar with a popover of graphs and your busiest apps, plus an option to hide the Dock icon. Turn it on in Settings → Menu bar.

## 0.3.1 (2026-10-07)
- **Settings** now live inside the main window (sidebar → Settings, or ⌘,) instead of a separate window, with the appearance, accent, columns, colours and permissions sections on one page.

## 0.3.0 (2026-10-07)
- New **Disk** page: read and write transfer rate across all drives, with a per-process **Disk** column.
- New **Network** page: send and receive rate for all connections together or for one interface (Wi-Fi, Ethernet, …).
- More process columns: **User**, **Threads**, **State** and **Started**. Choose them from the Columns button, by right-clicking the headings, or in Settings → Columns; the table scrolls sideways when they don't fit.
- **Process details** panel (double-click a row, or the Details button): path with Reveal in Finder, parent, open files, code-signature status and open TCP/UDP ports.
- New look: sidebar with live graphs and an accent pill, large page titles, ring gauges, rounded cards and heat-tinted CPU / Memory / Disk cells. Pick an accent colour (Ocean blue by default) and card corner style in Settings → General; ⌘1–⌘7 switch pages.
- Light mode review: chart colours deepen on light cards and every accent is checked against the WCAG contrast ratio by `--selftest`.
- Continuous integration: GitHub Actions builds the app and runs `--selftest` on every push and pull request.

## 0.2.0 (2026-10-07)
- New **System** page: model, chip, core layout, memory, graphics, macOS version and build, up time, thermal state, storage and battery. Hostname and serial number are never collected.
- CPU, Memory and GPU pages show more detail (performance/efficiency cores, wired and compressed memory, thermal state).
- **Settings** shortcut in the sidebar.
- Processes list rebuilt on a plain scrolling list, which removes a macOS "reentrant NSTableView" warning when sorting by CPU.
- **End Task** now asks first and only signals the process that was listed, never a different program that reused its pid.
- Updater re-checks the verified executable's fingerprint right before installing.
- Released under the MIT license. The bundle identifier changed to `io.github.ol775.taskmanager`, so preferences start fresh.

## 0.1.0 – beta
- First release: processes, CPU/Memory/GPU graphs, Settings, OLED Black theme, About and signed GitHub updates.
