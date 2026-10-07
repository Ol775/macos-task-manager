# Changelog

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
