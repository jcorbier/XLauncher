#!/bin/bash
set -e

# Clean up
rm -rf XLauncher.iconset XLauncher.icns
mkdir XLauncher.iconset

SOURCE="XLauncherIcon.png"

if [ ! -f "$SOURCE" ]; then
    echo "Source icon $SOURCE not found!"
    exit 1
fi

# Generate icons
sips -z 16 16     "$SOURCE" --out XLauncher.iconset/icon_16x16.png
sips -z 32 32     "$SOURCE" --out XLauncher.iconset/icon_16x16@2x.png
sips -z 32 32     "$SOURCE" --out XLauncher.iconset/icon_32x32.png
sips -z 64 64     "$SOURCE" --out XLauncher.iconset/icon_32x32@2x.png
sips -z 128 128   "$SOURCE" --out XLauncher.iconset/icon_128x128.png
sips -z 256 256   "$SOURCE" --out XLauncher.iconset/icon_128x128@2x.png
sips -z 256 256   "$SOURCE" --out XLauncher.iconset/icon_256x256.png
sips -z 512 512   "$SOURCE" --out XLauncher.iconset/icon_256x256@2x.png
sips -z 512 512   "$SOURCE" --out XLauncher.iconset/icon_512x512.png
sips -z 1024 1024 "$SOURCE" --out XLauncher.iconset/icon_512x512@2x.png

# Create icns
iconutil -c icns XLauncher.iconset

echo "XLauncher.icns created successfully."
