#!/bin/sh
# Builds TaskManager.app (no Xcode needed, just the Swift toolchain).
set -e
swift build -c release
APP=TaskManager.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/TaskManager "$APP/Contents/MacOS/TaskManager"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>TaskManager</string>
<key>CFBundleIdentifier</key><string>io.github.ol775.taskmanager</string>
<key>CFBundleExecutable</key><string>TaskManager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP"
