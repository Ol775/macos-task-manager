# Changelog

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
