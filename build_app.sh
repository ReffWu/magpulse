#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MagPulse"
BUNDLE_ID="com.reffwu.magpulse"
VERSION="1.0.1"
SIGN_IDENTITY="Apple Development: reffwu@icloud.com (RYP73FWJ3Y)"

# 检查证书是否存在
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "警告: 未在钥匙串中找到 '$SIGN_IDENTITY'" >&2
fi

echo "▸ 1. 正在编译 Release 二进制 (Apple Silicon arm64)..."
swift build -c release --arch arm64

BUNDLE_DIR="$HOME/Applications/$APP_NAME.app"
echo "▸ 2. 正在打包至 $BUNDLE_DIR..."

pkill -f "$APP_NAME.app" || true
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Frameworks"

BIN_DIR=$(swift build --show-bin-path -c release)
cp "$BIN_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# 确保二进制具备 Frameworks 搜索路径
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# 拷贝 Sparkle.framework
SPARKLE_FW=$(find .build -name "Sparkle.framework" | head -n 1)
if [ -n "$SPARKLE_FW" ] && [ -d "$SPARKLE_FW" ]; then
    echo "▸ 嵌入 Sparkle.framework..."
    cp -R "$SPARKLE_FW" "$BUNDLE_DIR/Contents/Frameworks/"
fi

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -f "Resources/icon-2048.png" ]; then
    cp "Resources/icon-2048.png" "$BUNDLE_DIR/Contents/Resources/app_icon.png"
fi
if [ -d "Resources/Icons" ]; then
    cp -r "Resources/Icons" "$BUNDLE_DIR/Contents/Resources/Icons"
fi

# 生成标准 Info.plist (包含 Sparkle 2 与 URL Scheme)
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
    <!-- Sparkle 2 自动更新配置 -->
    <key>SUFeedURL</key>
    <string>https://github.com/ReffWu/magpulse/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>wpcSIsJIvvZPj3jAoJuw8wl0+fVXS3K3ChODZ0W8EBI=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>21600</integer>
    <!-- URL Scheme: magpulse:// -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>magpulse</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "▸ 3. 正在使用 '$SIGN_IDENTITY' 进行安全签名与权限配置..."
if [ -d "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"

echo "✓ 验证代码签名..."
codesign -vvv --deep --strict "$BUNDLE_DIR"

echo "✓ MagPulse 已成功构建并安装到 $BUNDLE_DIR"
open "$BUNDLE_DIR"
