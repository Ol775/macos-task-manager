#!/bin/sh
# Builds TaskManager.app (needs the Swift toolchain + Xcode). UNIVERSAL=1 builds arm64 + x86_64.
set -e
cd "$(dirname "$0")"
VER=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
ARCHS=""; [ -n "$UNIVERSAL" ] && ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN=$(swift build -c release $ARCHS --show-bin-path)
APP=TaskManager.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TaskManager" "$APP/Contents/MacOS/TaskManager"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Task Manager</string>
<key>CFBundleDisplayName</key><string>Task Manager</string>
<key>CFBundleIdentifier</key><string>io.github.ol775.taskmanager</string>
<key>CFBundleExecutable</key><string>TaskManager</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP $VER ($BUILD)"
