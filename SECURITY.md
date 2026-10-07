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

## Security review (7 October 2026, v0.4.1)
The whole code base was reviewed: updater, process and socket inspection, code-signature checks, End Task, menu bar controller, preferences handling, build and release scripts, CI and the Homebrew cask. Findings fixed in 0.4.1:

- **Misleading signer label (medium).** The process details panel decided "Apple" or "Developer ID" from the certificate's *name*, which anyone can imitate. Labels now come from Apple's certificate-chain requirements (`anchor apple`, Developer ID and App Store requirements); anything else is shown as an unverified certificate.
- **Update URL checks (low).** Asset URLs must be exactly this repository's `releases/download/` path on github.com: no port, credentials, query, `..` or empty path segments.
- **Installer re-verification (low).** The swap helper now runs `codesign --verify --deep --strict` on the installed app after copying it and rolls back to the backup if that fails.
- **Crash on non-finite rates (low).** Disk and CPU rates could reach an integer conversion that traps on NaN or infinity; they are now sanitised.
- **Hardened runtime.** The app is built with `codesign --options runtime` (blocks code injection and debugger attach).
- **CI least privilege.** The workflow token is read-only.
- **Signature checks are bounded.** The details panel verifies the signature itself rather than every resource, so inspecting a very large app can't tie up the machine.

Residual risks, accepted: the app is ad-hoc signed and not notarized; the Homebrew cask clears the quarantine flag (the cask pins the DMG's SHA-256 and the app verifies its own updates); a process running as your own user can already tamper with your files, so local same-user attacks are out of scope; `SIGTERM` could in principle hit a recycled pid in the microseconds between the start-time check and `kill`.

## Updates
Updates come only from this repository's GitHub releases and are installed only if **all** of these pass:

1. The asset URL is `https://github.com/Ol775/macos-task-manager/releases/download/…`, and every redirect stays on `github.com` or `*.githubusercontent.com`.
2. The release version is plain `x.y.z` and newer than the installed one.
3. An **Ed25519 signature**, made offline with a private key that never leaves the maintainer's Mac and is never committed, verifies over `"taskmanager-update\nv<version>\n"` plus the disk image bytes. The public key is built into the app, so a hijacked GitHub account or release cannot push an update that installs, and an older signed image cannot be passed off as a newer one.
4. The SHA-256 matches, checked again right before mounting.
5. The app inside has bundle id `io.github.ol775.taskmanager`, the announced version, and a valid code signature.
6. The executable's fingerprint, taken at verification, is unchanged at install time.

Downloads are capped at 100 MB and 10 minutes. After the swap the installed app is verified again and the previous version is restored if it fails. The previous app is kept as a backup and restored if the swap fails.

## Verifying a release yourself
```sh
shasum -a 256 Task-Manager-X.Y.Z.dmg   # compare with the .sha256 asset
```
The signature asset is `Task-Manager-X.Y.Z.dmg.sig2` (base64 Ed25519); the public key is `Updater.publicKey` in `Sources/TaskManager/Updater.swift`.

## Supported versions
Only the latest release receives fixes.
