#!/bin/zsh
# Publishes the current VERSION: builds the universal DMG, signs it with the release key and creates the GitHub release
# (DMG + .sha256 + .sig2). Run after ./bump.sh, a build, and pushing the commit.
# Usage: ./release.sh "short release note"
# The signing key (never committed, back it up!) lives at ~/.config/taskmanager/signing.key; its public half is built into the app.
set -e
cd "$(dirname "$0")"
note="${1:?usage: ./release.sh \"short release note\"}"
ver=$(cat VERSION)
key="${SIGNING_KEY:-$HOME/.config/taskmanager/signing.key}"
[ -f "$key" ] || { echo "No signing key at $key. Releases must be signed (see tools/sign-tool.swift)."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q origin main; [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
mkdir -p build && swiftc -O tools/sign-tool.swift -o build/sign-tool 2>/dev/null
[ "$(build/sign-tool public "$key")" = "$(grep -o 'publicKey = "[^"]*"' Sources/TaskManager/Updater.swift | cut -d'"' -f2)" ] || { echo "The signing key doesn't match the public key built into the app."; exit 1; }
./make-dmg.sh >/dev/null 2>&1
dmg="dist/Task-Manager-$ver.dmg"
build/sign-tool sign-update "$key" "$dmg" "$ver" > "$dmg.sig2"
gh release create "v$ver" "$dmg" "$dmg.sha256" "$dmg.sig2" --repo Ol775/macos-task-manager --title "v$ver" --notes "$note" --latest
echo "Released v$ver"
