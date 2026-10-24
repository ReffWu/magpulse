#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MagPulse"
BUNDLE_ID="com.reff.MagPulse"
VERSION="1.0.0"
SIGN_IDENTITY="Apple Development: reffwu@icloud.com (RYP73FWJ3Y)"

echo "▸ 1. 正在编译 Release 二进制 (Apple Silicon arm64)..."
swift build -c release --arch arm64

BUNDLE_DIR="$HOME/Applications/$APP_NAME.app"
echo "▸ 2. 正在打包至 $BUNDLE_DIR..."

pkill -f "$APP_NAME.app" || true
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

BIN_DIR=$(swift build --show-bin-path -c release)
cp "$BIN_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -f "Resources/icon-2048.png" ]; then
    cp "Resources/icon-2048.png" "$BUNDLE_DIR/Contents/Resources/app_icon.png"
fi
if [ -d "Resources/Icons" ]; then
    cp -r "Resources/Icons" "$BUNDLE_DIR/Contents/Resources/Icons"
fi

# 生成 Info.plist
cat > "$BUNDLE_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "▸ 3. 正在使用 $SIGN_IDENTITY 证书进行官方签名..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"

echo "✓ 验证代码签名..."
codesign -vvv --deep --strict "$BUNDLE_DIR"

echo "✓ MagPulse 已成功构建并安装到 $BUNDLE_DIR"
open "$BUNDLE_DIR"
