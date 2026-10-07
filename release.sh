#!/bin/zsh
# Publishes the current VERSION: builds the universal DMG, signs it with the release key and creates the GitHub release
# (DMG + .sha256 + .sig2) and updates the Homebrew cask. Run after ./bump.sh, a build, and pushing the commit.
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
# Homebrew tap: point the cask at the new release (clones the tap into build/ if TAP_DIR isn't set).
tap="${TAP_DIR:-build/homebrew-tap}"
[ -d "$tap/.git" ] || git clone -q https://github.com/Ol775/homebrew-tap "$tap"
git -C "$tap" pull -q --ff-only origin main
sha=$(cut -d' ' -f1 "$dmg.sha256")
sed -i '' -e "s/^  version \".*\"/  version \"$ver\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/task-manager.rb"
git -C "$tap" add -A && git -C "$tap" commit -q -m "task-manager $ver" && git -C "$tap" push -q origin main && echo "Homebrew tap updated to $ver"
echo "Released v$ver"
