# Privacy

Last updated 7 October 2026.

**Short version:** Task Manager works entirely on your Mac. There are no servers, accounts, analytics or telemetry, and nothing about you is collected.

## What the app reads

Read-only, to draw the graphs and lists:

- Process information (name, CPU time, memory, disk I/O, threads, state, owner, start time, path, open files and open TCP/UDP port numbers) through `libproc`, only for processes your own user owns.
- System statistics: CPU, memory, GPU, disk and network counters, thermal state, storage and battery.
- A process's code signature, only when you open its details.

It never reads file contents, the hostname, the serial number, IP addresses or the data you send over the network.

## What is stored

Only the app's preferences (theme, colours, columns, update interval), in the standard macOS preferences file for `io.github.ol775.taskmanager`. Nothing leaves your Mac.

## Network requests

One: the update check against this repository's GitHub releases (`api.github.com`, and the release download from `github.com` when you choose Update Now). You can turn the check off in Settings. GitHub sees your IP address as it would for any web request.

## Deleting your data

Quit the app and delete `~/Library/Preferences/io.github.ol775.taskmanager.plist`. `brew uninstall --zap --cask task-manager` does this for you.

## Questions

Open an [issue](https://github.com/Ol775/macos-task-manager/issues/new/choose), or report anything security-related privately as described in [SECURITY.md](SECURITY.md).
