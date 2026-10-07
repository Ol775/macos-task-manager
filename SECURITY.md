# Security

## Reporting a vulnerability
Please use GitHub's **private vulnerability reporting** (Security tab → *Report a vulnerability*) rather than a public issue. You'll get a reply within a few days.

## What the app does
- Reads process, CPU, memory, GPU, battery, disk and network information through `libproc` (including `proc_pid_rusage` for per-process disk I/O), `sysctl`, Mach host statistics, `getifaddrs` interface counters and IOKit. The process details panel also lists a process's open TCP/UDP socket ports (local and remote port numbers only, never addresses) and checks its code signature with the Security framework; it never reads file contents. It needs no special macOS permission: no Full Disk Access, Accessibility or Screen Recording.
- Only sees processes owned by your user; macOS hides other users' and system processes from unprivileged apps.
- **End Task** sends `SIGTERM` after a confirmation, and only to the process that was listed (it re-checks the process start time, so a recycled pid is never signalled).
- Never collects or shows your hostname or serial number.
- No telemetry, no accounts, no analytics. The only network request is the update check (below), which you can turn off in Settings → General.
- The app is not sandboxed (the sandbox blocks the process APIs it relies on) and is ad-hoc code signed, not notarized.

## Updates
Updates come only from this repository's GitHub releases and are installed only if **all** of these pass:

1. The asset URL is `https://github.com/Ol775/macos-task-manager/releases/download/…`, and every redirect stays on `github.com` or `*.githubusercontent.com`.
2. The release version is plain `x.y.z` and newer than the installed one.
3. An **Ed25519 signature**, made offline with a private key that never leaves the maintainer's Mac and is never committed, verifies over `"taskmanager-update\nv<version>\n"` plus the disk image bytes. The public key is built into the app, so a hijacked GitHub account or release cannot push an update that installs, and an older signed image cannot be passed off as a newer one.
4. The SHA-256 matches, checked again right before mounting.
5. The app inside has bundle id `io.github.ol775.taskmanager`, the announced version, and a valid code signature.
6. The executable's fingerprint, taken at verification, is unchanged at install time.

Downloads are capped at 100 MB and 10 minutes. The previous app is kept as a backup and restored if the swap fails.

## Verifying a release yourself
```sh
shasum -a 256 Task-Manager-X.Y.Z.dmg   # compare with the .sha256 asset
```
The signature asset is `Task-Manager-X.Y.Z.dmg.sig2` (base64 Ed25519); the public key is `Updater.publicKey` in `Sources/TaskManager/Updater.swift`.

## Supported versions
Only the latest release receives fixes.
