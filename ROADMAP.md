# Roadmap

Where Task Manager is heading. Nothing here is a promise or a date; the order is a best guess and can change. Ideas and votes are welcome as [issues](../../issues).

**Now (v0.3)** – shipped: Processes with End Task and a column picker, process details, CPU / Memory / GPU / Disk / Network pages, System page, accent themes, light / dark / OLED Black, signed GitHub updates, CI.

## Next (v0.4)

- **Menu bar mode.** A compact CPU / memory / GPU readout with a popover, and an option to hide the Dock icon.
- **Alerts.** Optional notifications when a process stays above a CPU or memory threshold.
- **Per-core CPU view.** Logical-processor graphs, with performance and efficiency cores grouped.
- **Per-process network.** Only if macOS exposes it without elevated privileges.

## Later (v0.5 and beyond)

- **Per-process GPU.** Only if macOS exposes it without private APIs.
- **App history.** Cumulative CPU time per app over a session, like the Windows "App history" tab.
- **Export.** Save a snapshot of the process list or system info as CSV or JSON.
- **Keyboard and accessibility pass.** Full keyboard control of the process list and a VoiceOver review.
- **Localisation.** Start with the strings already in the UI.

## Needs a decision or outside help

- **Notarization.** Removes the first-launch "Open Anyway" step. Requires a paid Apple Developer ID.
- **Other users' and system processes.** macOS hides them from unprivileged apps. Showing them would need a privileged helper (`SMAppService`) with its own security review, so it only happens if there is clear demand.
- **Homebrew cask.** A tap entry for `brew install --cask`; easier once releases are notarized.

## Principles

- **Native and light.** SwiftUI and system frameworks only; no third-party dependencies.
- **Private by default.** No telemetry, no accounts, never the hostname or serial number.
- **Safe updates.** Every update is Ed25519-signed offline and verified before install (see [SECURITY.md](SECURITY.md)).
- **Small and readable.** Prefer less code; every feature should earn its place.
