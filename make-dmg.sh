#!/bin/zsh
# Builds the universal app and packs dist/Task-Manager-<version>.dmg (drag-to-Applications installer).
set -e
cd "$(dirname "$0")"
UNIVERSAL=1 ./build-app.sh >/dev/null
ver=$(cat VERSION)
out="dist/Task-Manager-$ver.dmg"
stage=$(mktemp -d)
mkdir -p dist
cp -R TaskManager.app "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -volname "Task Manager $ver" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out" >/dev/null
rm -rf "$stage"
(cd dist && shasum -a 256 "Task-Manager-$ver.dmg" > "Task-Manager-$ver.dmg.sha256")
echo "$out"
