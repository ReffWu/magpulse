#!/usr/bin/env bash
# 构建、Developer ID 签名、公证、DMG 打包及 Sparkle appcast 生成流水线
#
#   Scripts/release.sh             制作签名的精装 DMG 并生成 Sparkle appcast
#   Scripts/release.sh --dmg-only  仅快速生成已签名的本地精装 DMG
#   Scripts/release.sh --publish   生成并发布到 GitHub Releases
set -euo pipefail
cd "$(dirname "$0")/.."

app="MagPulse"
repo="ReffWu/magpulse"
team="YVRAA57U55"
identity="Developer ID Application: Reff LLC ($team)"
version="$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)"
root="build/release"
archive="$root/$app.xcarchive"
packages="build/SourcePackages"
feed="$root/feed"
dmg="$root/$app.dmg"
prefix="https://github.com/$repo/releases/download/v$version/"

echo "▸ 1. 检查代码签名证书..."
security find-identity -v -p codesigning | grep -q "$identity" || {
  echo "警告: 未在钥匙串中找到 '$identity'，将尝试使用有效证书..." >&2
}

rm -rf "$root"
mkdir -p "$root"
mkdir -p "$packages"
touch build/.metadata_never_index 2>/dev/null || true

echo "▸ 2. 生成工程并构建 Release Archive..."
find Sources Resources -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr Sources Resources 2>/dev/null || true
xcodegen generate
xcodebuild archive -quiet -project "$app.xcodeproj" -scheme "$app" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  -clonedSourcePackagesDirPath "$packages" \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$team" ENABLE_HARDENED_RUNTIME=YES

inside="$archive/Products/Applications/$app.app"

echo "▸ 3. 签署内部 Frameworks (Sparkle)..."
if [ -d "$inside/Contents/Frameworks/Sparkle.framework" ]; then
  codesign --force --options runtime --timestamp --sign "$identity" "$inside/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --options runtime --timestamp --sign "$identity" "$inside"

echo "▸ 4. 验证应用代码签名与安全强化 (Hardened Runtime)..."
codesign --verify --deep --strict --verbose=2 "$inside"

echo "▸ 5. 制作官方精装 DMG 安装包 (带 Applications 软链接)..."
stage="$root/stage"
mkdir -p "$stage"
ditto "$inside" "$stage/$app.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -ov -volname "$app" -srcfolder "$stage" -format UDZO "$dmg"
rm -rf "$stage"

echo "▸ 6. 对 DMG 安装包自身进行签名与时间戳附加..."
codesign --force --timestamp --sign "$identity" "$dmg"

# 检查是否配置了 Apple 官方公证环境变量 NOTARY_PROFILE
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ 7. 正在向 Apple 官方提交公证 (Profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "▸ 8. 压印 Apple 公证票据 (Stapling)..."
  xcrun stapler staple "$dmg"
fi

(cd "$root" && shasum -a 256 "$app.dmg" > "$app.dmg.sha256")
echo "✓ DMG 创建完成: $dmg"
cat "$root/$app.dmg.sha256"

if [ "${1:-}" = "--dmg-only" ]; then
  echo "🎉 精装 DMG 已准备就绪: $dmg"
  exit 0
fi

echo "▸ 9. 生成 Sparkle 自动更新 feed (appcast.xml)..."
mkdir -p "$feed"
cp "$dmg" "$feed/"
curl -sLf "https://github.com/$repo/releases/latest/download/appcast.xml" -o "$feed/appcast.xml" 2>/dev/null || true

# 寻找 generate_appcast 工具
GEN_APPCAST=""
if [ -x "$packages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
  GEN_APPCAST="$packages/artifacts/sparkle/Sparkle/bin/generate_appcast"
elif [ -x "/Users/reff/Documents/Claude Code项目/TokNotch/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
  GEN_APPCAST="/Users/reff/Documents/Claude Code项目/TokNotch/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
fi

if [ -n "$GEN_APPCAST" ]; then
  "$GEN_APPCAST" "$feed" --download-url-prefix "$prefix"
  echo "✓ Sparkle appcast.xml 生成并成功签名！"
else
  echo "提示: 未找到 generate_appcast 可执行文件，跳过 appcast 自动签名。"
fi

if [ "${1:-}" = "--publish" ]; then
  echo "▸ 10. 发布到 GitHub Release ($repo v$version)..."
  cat > "$root/release_notes.md" << 'EOF'
### MagPulse 1.0.1

- **Antigravity 毫秒级原生状态感知**：直接对接 Antigravity 官方 SQLite 本地状态库 (`~/.gemini/antigravity/conversation_summaries.db`)，彻底解决回答完成后延迟 40 秒才恢复待命的问题，实现 0 秒瞬时响应。
- **状态栏同款实时硬件接头**：弹窗 Header 图标去除黑色外壳容器，采用透明背景直出，中央 LED 光珠实时跟随硬件 SMC 变色呼吸。
- **全新底栏微胶囊控件组**：开机自启微型胶囊开关、v1.0.1 版本状态与 Sparkle 更新徽标、极简退出按键。
EOF

  gh release create -R "$repo" "v$version" "$dmg" "$root/$app.dmg.sha256" "$feed/appcast.xml" \
    --title "$app $version" --notes-file "$root/release_notes.md" --target main --draft
  gh release edit -R "$repo" "v$version" --draft=false --latest
  echo "✓ 成功发布到 GitHub Release!"
fi

echo "🎉 $app $version 已完成 Developer ID 签名、精装 DMG 制作与 Sparkle 配置，位于 $root"
