#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Fridge.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$DIST_DIR/Fridge.iconset"
ICON_PNG="$DIST_DIR/AppIcon-1024.png"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/FridgeApp" "$MACOS_DIR/Fridge"
cp "$BUILD_DIR/fridge" "$MACOS_DIR/fridge-cli"

if command -v magick >/dev/null 2>&1; then
  mkdir -p "$ICONSET_DIR"
  magick "$ROOT_DIR/Assets/AppIcon.svg" -resize 1024x1024 "$ICON_PNG"
  sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Fridge</string>
    <key>CFBundleIdentifier</key>
    <string>app.fridge.menu</string>
    <key>CFBundleName</key>
    <string>Fridge</string>
    <key>CFBundleDisplayName</key>
    <string>Fridge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Fridge may open System Settings to help configure permissions.</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>Fridge uses keyboard permissions for global Pause key handling.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Fridge uses Accessibility permission to support global Pause key handling.</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${FRIDGE_CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "$APP_DIR"
