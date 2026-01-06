#!/bin/bash
set -e

APP_NAME="XLauncher"
SOURCE_NAME="XPlaneLauncher"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "Building Release configuration..."
swift build -c release

echo "Creating App Bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Creating Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.jcorbier.XPlaneLauncher</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Copying binary..."
cp "$BUILD_DIR/$SOURCE_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Signing app..."
codesign -f -s - "$APP_BUNDLE"

echo "Done! $APP_BUNDLE created."
