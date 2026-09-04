#!/bin/bash
set -e

APP_NAME="XLauncher"
SOURCE_NAME="XPlaneLauncher"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
SKIP_BUILD=false
CUSTOM_BINARY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --binary)
            CUSTOM_BINARY="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$SKIP_BUILD" = false ]; then
    echo "Building Release configuration..."
    swift build -c release
fi

echo "Creating App Bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
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
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>SUEnableAutomaticChecks</key>
    <false/>
    <key>SUPublicEDKey</key>
    <string>UwSNDkYiukbvlZen5gfKSVpMuKo9u92MSF80c9qtk8A=</string>
</dict>
</plist>
EOF

if [ -n "$CUSTOM_BINARY" ] && [ -f "$CUSTOM_BINARY" ]; then
    echo "Copying custom binary from $CUSTOM_BINARY..."
    cp "$CUSTOM_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
elif [ -f "$BUILD_DIR/$SOURCE_NAME" ]; then
    echo "Copying binary..."
    cp "$BUILD_DIR/$SOURCE_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

echo "Copying Sparkle framework..."
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d | grep -E "release|Sparkle\.xcframework" | head -n 1)
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
fi

echo "Configuring rpath..."
if [ -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]; then
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

echo "Copying resources..."
if [ -f "XLauncher.icns" ]; then
    cp "XLauncher.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -d "Sources/XPlaneLauncher/Resources" ]; then
    cp -R Sources/XPlaneLauncher/Resources/* "$APP_BUNDLE/Contents/Resources/"
fi

echo "Signing app..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "Done! $APP_BUNDLE created."
