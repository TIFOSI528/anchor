#!/usr/bin/env zsh
# 打包 Anchor 成可双击运行的 .app bundle。
# 用法：zsh scripts/package-app.sh
#
# 可选环境变量：
#   ANCHOR_VERSION        版本号（默认 0.1.0）
#   ANCHOR_SIGN_IDENTITY  Developer ID Application 签名身份（分发用；不设则 ad-hoc 本机签名）
#   ANCHOR_NOTARIZE       传 1 触发公证（需 ANCHOR_APPLE_ID / ANCHOR_APPLE_PWD / ANCHOR_TEAM_ID）

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

APP_NAME="Anchor"
BUNDLE_ID="com.anchor.app"
VERSION="${ANCHOR_VERSION:-0.1.0}"

OUTPUT_DIR="$PROJECT_ROOT/output"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
FW_DIR="$CONTENTS/Frameworks"
ENTITLEMENTS="$PROJECT_ROOT/scripts/Anchor.entitlements"

echo "[1/6] 清理旧产物"
rm -rf "$OUTPUT_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR" "$FW_DIR"

echo "[2/6] 构建 release"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "[3/6] 拷贝可执行文件 / 框架 / 资源"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# 链接的框架（目前只有 Sparkle）→ Contents/Frameworks。ditto 保留 framework 的符号链接结构。
for fw in "$BIN_DIR"/*.framework(N); do
  ditto "$fw" "$FW_DIR/${fw:t}"
done

# SwiftPM 生成的资源 bundle（如 SQLite.swift_SQLite.bundle）→ Contents/Resources。
for bundle in "$BIN_DIR"/*.bundle(N); do
  ditto "$bundle" "$RES_DIR/${bundle:t}"
done

# 品牌资源。
if [[ -d "$PROJECT_ROOT/Assets/Brand" ]]; then
  ditto "$PROJECT_ROOT/Assets/Brand" "$RES_DIR/Brand"
fi

# Chrome 扩展（Settings 的"安装指南"按钮指向这里）。
if [[ -d "$PROJECT_ROOT/Sources/AnchorExtension/chrome" ]]; then
  ditto "$PROJECT_ROOT/Sources/AnchorExtension/chrome" "$RES_DIR/AnchorExtension/chrome"
fi

# 二进制只带 @loader_path 这一条 rpath；补一条指向 Contents/Frameworks，
# 这样 @rpath/Sparkle.framework 才能在 relocate 后的 .app 里被找到。
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"

echo "[4/6] 写入 Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>            <string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
	<key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>     <string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
	<key>CFBundleShortVersionString</key>    <string>${VERSION}</string>
	<key>CFBundleVersion</key>         <string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>  <string>14.0</string>
	<key>NSPrincipalClass</key>        <string>NSApplication</string>
	<key>NSHighResolutionCapable</key> <true/>
	<!-- menu-bar / overlay app：不在 Dock 显示图标、无主窗口。 -->
	<key>LSUIElement</key>             <true/>
	<key>NSHumanReadableCopyright</key> <string>© 2026 Anchor. GPL-3.0.</string>
	<key>NSAppleEventsUsageDescription</key> <string>Anchor 需要读取浏览器当前标签页地址，来判断你在绿区还是漂移。</string>
	<!-- Sparkle 自动更新。feed 上线前 SUEnableAutomaticChecks 保持 false（用户可在 Settings 打开）。 -->
	<key>SUFeedURL</key>               <string>${ANCHOR_APPCAST_URL:-https://example.invalid/anchor/appcast.xml}</string>
	<key>SUEnableAutomaticChecks</key> <false/>
	<key>SUPublicEDKey</key>           <string>${ANCHOR_SPARKLE_PUBLIC_KEY:-eSu0nsFWgzHoc2PK4f9GyUy0pvOVVfITU9/uYgb3oB8=}</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "[5/6] 签名"
if [[ -n "${ANCHOR_SIGN_IDENTITY:-}" ]]; then
  # 分发签名：先签内部框架，再用 entitlements + 强化运行时签整个 app。
  # 注意：Sparkle 内部还有 XPCServices / Updater.app 等嵌套组件，发布前需逐个签名 + 公证（见下方 TODO）。
  for fw in "$FW_DIR"/*.framework(N); do
    codesign --force --options runtime --sign "$ANCHOR_SIGN_IDENTITY" "$fw"
  done
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$ANCHOR_SIGN_IDENTITY" "$APP_PATH"
else
  # 本机验收：ad-hoc 深度签名，保证能直接双击启动（不走 Gatekeeper 公证）。
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "[6/6] 完成 → $APP_PATH"
codesign --verify --verbose=2 "$APP_PATH" 2>&1 | tail -2 || true

if [[ "${ANCHOR_NOTARIZE:-0}" == "1" ]]; then
  echo "[+] 公证"
  ZIP_PATH="$OUTPUT_DIR/$APP_NAME-notarize.zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  if [[ -n "${ANCHOR_NOTARY_PROFILE:-}" ]]; then
    # 推荐：凭证在钥匙串里（xcrun notarytool store-credentials <profile>），密码不进环境/历史。
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$ANCHOR_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
  elif [[ -n "${ANCHOR_APPLE_ID:-}" && -n "${ANCHOR_APPLE_PWD:-}" && -n "${ANCHOR_TEAM_ID:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" \
      --apple-id "$ANCHOR_APPLE_ID" --password "$ANCHOR_APPLE_PWD" --team-id "$ANCHOR_TEAM_ID" --wait
    xcrun stapler staple "$APP_PATH"
  else
    echo "    跳过：设 ANCHOR_NOTARY_PROFILE（推荐）或 ANCHOR_APPLE_ID/PWD/TEAM_ID"
  fi
  rm -f "$ZIP_PATH"
fi

if [[ "${ANCHOR_DMG:-1}" == "1" ]]; then
  echo "[+] 生成 dmg"
  DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
  STAGE_DIR="$OUTPUT_DIR/dmg-stage"
  rm -rf "$STAGE_DIR" "$DMG_PATH"
  mkdir -p "$STAGE_DIR"
  ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
  ln -s /Applications "$STAGE_DIR/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" -quiet
  rm -rf "$STAGE_DIR"
  echo "  → $DMG_PATH"
fi
