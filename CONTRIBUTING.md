# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and ideas

Use [Issues](https://github.com/Ol775/macos-task-manager/issues/new/choose). Please don't paste personal data such as full process lists with private names. For security problems, use the private route in [SECURITY.md](SECURITY.md) instead.

## Building

You need Xcode 16 or later (the Swift 6 toolchain), macOS 15 or later.

```sh
./build-app.sh                                          # builds TaskManager.app
TaskManager.app/Contents/MacOS/TaskManager --selftest   # logic, sampling and contrast checks
```

CI runs the same two commands on every push and pull request.

## Pull requests

- Keep each PR small and focused, and describe what you checked.
- Run `--selftest` first. Add a check to `Sources/TaskManager/Checks.swift` when you add logic that can be tested without a window.
- Run `./bump.sh patch "short note"` when you change the app's behaviour. It updates `VERSION` and the changelog.
- Native and light: SwiftUI and system frameworks only, no third-party dependencies.
- Screenshots in the repo must not show personal information (usernames, private app names, hostnames).
- The app is macOS only. Don't add telemetry or network requests other than the update check.
- Changes to the updater (`Updater.swift`) need extra care; explain how the trust model in [SECURITY.md](SECURITY.md) still holds.

## Ideas

Have a look at [ROADMAP.md](ROADMAP.md) first. Items under "Needs a decision or outside help" are the ones where input matters most.
