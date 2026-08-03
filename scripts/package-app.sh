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

# 本地化表。刻意放在 Sources/ 之外：SwiftPM 会把 target 资源塞进
# Anchor_<Target>.bundle，而 SwiftUI 的字面量查的是 Bundle.main——对不上就会
# "翻译全做了、界面还是原语言"。直接拷进 Contents/Resources 让 Bundle.main 命中。
#
# 先从 fragments 重新生成一次：漏生成的表会静默回落成 key（界面上出现
# `settings.general.xxx`），绝不能靠"记得手动跑脚本"来避免。
if command -v python3 >/dev/null 2>&1; then
  python3 "$PROJECT_ROOT/scripts/build-localizations.py" >/dev/null
fi
if [[ -d "$PROJECT_ROOT/Resources/Localizations" ]]; then
  for lproj in "$PROJECT_ROOT"/Resources/Localizations/*.lproj(N); do
    ditto "$lproj" "$RES_DIR/${lproj:t}"
  done
fi

# 品牌资源。
if [[ -d "$PROJECT_ROOT/Assets/Brand" ]]; then
  ditto "$PROJECT_ROOT/Assets/Brand" "$RES_DIR/Brand"
fi

# Chrome 扩展（Settings 的"安装指南"按钮指向这里），并产出独立 zip 随 Release 分发。
if [[ -d "$PROJECT_ROOT/Sources/AnchorExtension/chrome" ]]; then
  ditto "$PROJECT_ROOT/Sources/AnchorExtension/chrome" "$RES_DIR/AnchorExtension/chrome"
  ditto -c -k "$PROJECT_ROOT/Sources/AnchorExtension/chrome" "$OUTPUT_DIR/anchor-chrome-extension-$VERSION.zip"
fi

# App 图标（swift scripts/generate-appicon.swift 生成）。
if [[ -f "$PROJECT_ROOT/Assets/Brand/AppIcon.icns" ]]; then
  cp "$PROJECT_ROOT/Assets/Brand/AppIcon.icns" "$RES_DIR/AppIcon.icns"
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
	<key>CFBundleDevelopmentRegion</key> <string>en</string>
	<!-- 声明支持的语言，系统「语言与地区 → 应用程序」才能单独给 Anchor 选语言。 -->
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>zh-Hans</string>
	</array>
	<key>NSHighResolutionCapable</key> <true/>
	<!-- menu-bar / overlay app：不在 Dock 显示图标、无主窗口。 -->
	<key>LSUIElement</key>             <true/>
	<key>CFBundleIconFile</key>        <string>AppIcon</string>
	<key>NSHumanReadableCopyright</key> <string>© 2026 Anchor. GPL-3.0.</string>
	<!--
	  Sparkle 自动更新。刻意**不写** SUEnableAutomaticChecks：
	  把它钉成 false 会连带压掉 Sparkle 自己的首次征询弹窗，结果是绝大多数用户
	  永远收不到更新——安全修复也送不出去。留空则由 Sparkle 在首次启动时
	  正常询问一次"是否自动检查更新"，把选择权交给用户（也正是隐私立场要的知情同意）。
	-->
	<key>SUFeedURL</key>               <string>${ANCHOR_APPCAST_URL:-https://example.invalid/anchor/appcast.xml}</string>
	<key>SUPublicEDKey</key>           <string>${ANCHOR_SPARKLE_PUBLIC_KEY:-eSu0nsFWgzHoc2PK4f9GyUy0pvOVVfITU9/uYgb3oB8=}</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "[5/6] 签名"
if [[ -n "${ANCHOR_SIGN_IDENTITY:-}" ]]; then
  # 分发签名：由内到外。公证要求包内所有可执行体都用本团队 Developer ID + 时间戳签名，
  # Sparkle 自带的是 Sparkle 团队的签名，必须逐个重签嵌套组件
  # （--preserve-metadata=entitlements 保留 XPC 的沙盒/网络 entitlements，Sparkle 官方要求）。
  SPARKLE_FW="$FW_DIR/Sparkle.framework"
  if [[ -d "$SPARKLE_FW" ]]; then
    for nested in \
      "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" \
      "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
      "$SPARKLE_FW/Versions/B/Autoupdate" \
      "$SPARKLE_FW/Versions/B/Updater.app"; do
      if [[ -e "$nested" ]]; then
        codesign --force --options runtime --timestamp \
          --preserve-metadata=entitlements --sign "$ANCHOR_SIGN_IDENTITY" "$nested"
      fi
    done
  fi
  for fw in "$FW_DIR"/*.framework(N); do
    codesign --force --options runtime --timestamp --sign "$ANCHOR_SIGN_IDENTITY" "$fw"
  done
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$ANCHOR_SIGN_IDENTITY" "$APP_PATH"
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
  if [[ -f "$PROJECT_ROOT/Assets/Brand/AppIcon.icns" ]]; then
    cp "$PROJECT_ROOT/Assets/Brand/AppIcon.icns" "$STAGE_DIR/.VolumeIcon.icns"
  fi
  RW_DMG="$OUTPUT_DIR/$APP_NAME-rw.dmg"
  rm -f "$RW_DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDRW "$RW_DMG" -quiet
  MOUNT_DIR=$(mktemp -d)
  hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
  SetFile -a C "$MOUNT_DIR" 2>/dev/null || true   # 卷根 custom-icon 位（挂载窗口显示锚图标）
  hdiutil detach "$MOUNT_DIR" -quiet
  hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -quiet
  rm -f "$RW_DMG"
  rm -rf "$STAGE_DIR"
  echo "  → $DMG_PATH"
fi
