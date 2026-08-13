#!/usr/bin/env zsh
# 一条命令走完发版。默认只演练（打印计划、跑只读检查），加 --go 才真正执行。
#
# 用法：
#   zsh scripts/release.sh 0.2.0            # 演练：看它准备干什么
#   zsh scripts/release.sh 0.2.0 --go       # 真的发
#   zsh scripts/release.sh 0.2.0 --go --resume   # 中断后续跑（跳过已完成的阶段）
#
# 设计原则：
#   1. **不可逆动作前必须过硬关卡**。公证没验过绝不推 tag——推了 tag 就会触发
#      release.yml，而它上传的是 ad-hoc 签名的同名 dmg。
#   2. **每个阶段先检查是否已完成**，所以中断可以重跑，不会重复推送或重复打 tag。
#   3. **appcast 放最后**，因为它一更新，存量用户立刻开始拉取；而且 length 必须
#      对着**已发布**的那个资产算，不是本地文件。
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { print -u2 "用法：zsh scripts/release.sh <版本号> [--go] [--resume]"; exit 2 }
shift

GO=0
RESUME=0
for arg in "$@"; do
  case "$arg" in
    --go) GO=1 ;;
    --resume) RESUME=1 ;;
    *) print -u2 "未知参数：$arg"; exit 2 ;;
  esac
done

TAG="v$VERSION"
DMG="output/Anchor-$VERSION.dmg"
EXT_ZIP="output/anchor-chrome-extension-$VERSION.zip"
REPO="TIFOSI528/anchor"
APPCAST_URL="https://raw.githubusercontent.com/$REPO/main/appcast.xml"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/Anchor-$VERSION.dmg"

# ---------- 输出helpers ----------
step()  { print "\n\033[1;36m▸ $*\033[0m" }
ok()    { print "  \033[32m✓\033[0m $*" }
warn()  { print "  \033[33m!\033[0m $*" }
die()   { print -u2 "\n\033[1;31m✗ 关卡未过：$*\033[0m"; exit 1 }
run()   {
  if (( GO )); then
    print "  \033[90m\$ $*\033[0m"
    "$@"
  else
    print "  \033[90m[演练] $*\033[0m"
  fi
}

(( GO )) || print "\033[1;33m=== 演练模式：不会推送、不会打 tag、不会发布 ===\033[0m\n加 --go 才真正执行。"

# ---------- 0. 前置条件 ----------
step "0/9 前置条件"

command -v gh >/dev/null || die "缺少 gh CLI"
gh auth status >/dev/null 2>&1 || die "gh 未登录（gh auth login）"
ok "gh 已登录"

: "${ANCHOR_SIGN_IDENTITY:=Developer ID Application: Kaiqiang Yan (YMDVD58KT2)}"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$ANCHOR_SIGN_IDENTITY" \
  || die "钥匙串里找不到签名证书：$ANCHOR_SIGN_IDENTITY\n  用 security find-identity -v -p codesigning 看看实际证书名，再 export ANCHOR_SIGN_IDENTITY=..."
ok "签名证书在位"

# 公证 profile 名历史上有两个说法（RELEASING.md 写 anchor-notary，实际用的是 dev），
# 所以这里自动探测，不写死。
if [[ -z "${ANCHOR_NOTARY_PROFILE:-}" ]]; then
  for candidate in dev anchor-notary; do
    if xcrun notarytool history --keychain-profile "$candidate" >/dev/null 2>&1; then
      ANCHOR_NOTARY_PROFILE="$candidate"
      break
    fi
  done
fi
[[ -n "${ANCHOR_NOTARY_PROFILE:-}" ]] \
  || die "找不到可用的公证 keychain profile（试过 dev / anchor-notary）。\n  用 xcrun notarytool store-credentials <名字> 建一个，再 export ANCHOR_NOTARY_PROFILE=<名字>"
ok "公证 profile：$ANCHOR_NOTARY_PROFILE"

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$SIGN_UPDATE" ]] || SIGN_UPDATE="$(find .build -type f -name sign_update -perm -u+x 2>/dev/null | head -1)"
[[ -n "$SIGN_UPDATE" && -x "$SIGN_UPDATE" ]] \
  || die "找不到 Sparkle 的 sign_update（先跑一次 swift build 拉依赖）"
ok "sign_update：$SIGN_UPDATE"

grep -q "^## \[$VERSION\]" CHANGELOG.md \
  || die "CHANGELOG.md 里没有 '## [$VERSION]' 段落——先补版本条目"
ok "CHANGELOG 有 $VERSION 条目"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  (( RESUME )) || die "tag $TAG 已存在。确认要续跑就加 --resume"
  warn "tag $TAG 已存在（--resume，跳过打 tag）"
fi

# ---------- 1. 验证 ----------
step "1/9 提交待提交的改动并验证"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short
  run git add -A
  run git commit -m "docs: CHANGELOG 定版 $VERSION"
else
  ok "工作区干净"
fi

# 这三项是只读的，演练模式也跑——发版前本来就该知道结果。
print "  跑测试…"
swift test >/tmp/anchor-release-test.log 2>&1 \
  || die "swift test 未过，详见 /tmp/anchor-release-test.log"
ok "$(grep -oE 'Executed [0-9]+ tests, with [0-9]+ failures' /tmp/anchor-release-test.log | tail -1)"

swift build -Xswiftc -warnings-as-errors >/tmp/anchor-release-build.log 2>&1 \
  || die "带 -warnings-as-errors 的构建未过，详见 /tmp/anchor-release-build.log"
ok "构建零警告"

python3 scripts/build-localizations.py --check >/dev/null \
  || die "本地化校验未过（语言间 key 不齐或说明符不一致）"
ok "本地化校验通过"

# ---------- 2-3. 推分支 + 合 main ----------
step "2/9 推送当前分支"
BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" == "main" ]]; then
  ok "已在 main 上，跳过"
else
  run git push -u origin "$BRANCH"
fi

step "3/9 快进合入 main"
if [[ "$BRANCH" != "main" ]]; then
  run git checkout main
  # --ff-only：不是干净快进就失败，绝不产生意外的 merge commit
  run git merge --ff-only "$BRANCH"
  run git push origin main
else
  run git push origin main
fi

# ---------- 4. 构建 + 签名 + 公证 ----------
step "4/9 构建 + 签名 + 公证（要等 Apple，通常几分钟）"
if [[ -f "$DMG" ]] && (( RESUME )); then
  warn "$DMG 已存在（--resume，跳过重新构建）"
else
  run env \
    ANCHOR_VERSION="$VERSION" \
    ANCHOR_SIGN_IDENTITY="$ANCHOR_SIGN_IDENTITY" \
    ANCHOR_NOTARIZE=1 \
    ANCHOR_NOTARY_PROFILE="$ANCHOR_NOTARY_PROFILE" \
    ANCHOR_APPCAST_URL="$APPCAST_URL" \
    zsh scripts/package-app.sh
fi

# ---------- 5. 公证硬关卡 ----------
step "5/9 公证验收（硬关卡）"
if (( GO )); then
  SPCTL_OUT="$(spctl -a -vv output/Anchor.app 2>&1 || true)"
  print "$SPCTL_OUT" | sed 's/^/    /'
  print "$SPCTL_OUT" | grep -q "source=Notarized Developer ID" \
    || die "公证未生效。发一个 ad-hoc 包出去，每个下载的人都会被 Gatekeeper 拦——\n  这比晚发版糟得多。到此为止，什么都没发布。"
  xcrun stapler validate output/Anchor.app >/dev/null 2>&1 \
    || die "stapler validate 未过（公证票据没钉上）"
  ok "source=Notarized Developer ID，票据已钉上"
else
  print "  \033[90m[演练] spctl -a -vv output/Anchor.app  → 必须含 source=Notarized Developer ID\033[0m"
  print "  \033[90m[演练] xcrun stapler validate output/Anchor.app\033[0m"
fi

# ---------- 6. tag + Release ----------
step "6/9 打 tag 并建 Release"
NOTES_FILE="/tmp/anchor-release-notes-$VERSION.md"
if (( GO )); then
  # 只抽出本版那一段 CHANGELOG 作为 release notes
  python3 - "$VERSION" > "$NOTES_FILE" <<'PY'
import re, sys, pathlib
version = sys.argv[1]
text = pathlib.Path("CHANGELOG.md").read_text(encoding="utf-8")
match = re.search(rf"^## \[{re.escape(version)}\].*?$(.*?)(?=^## \[|\Z)",
                  text, re.M | re.S)
print((match.group(1).strip() if match else f"见 CHANGELOG.md 的 {version} 段落。"))
PY
  ok "release notes 已抽取（$(wc -l < "$NOTES_FILE") 行）"
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  warn "tag $TAG 已存在，跳过创建"
else
  run git tag -a "$TAG" -m "$TAG"
fi
run git push origin "$TAG"

if (( GO )) && gh release view "$TAG" >/dev/null 2>&1; then
  warn "Release $TAG 已存在，改为上传/覆盖资产"
  run gh release upload "$TAG" "$DMG" "$EXT_ZIP" --clobber
else
  run gh release create "$TAG" "$DMG" "$EXT_ZIP" \
    --title "$TAG" --notes-file "$NOTES_FILE"
fi

# ---------- 7. 防 CI 抢资产 ----------
step "7/9 等 CI 跑完，并复验已发布的资产"
# release.yml 由 tag 推送触发，会上传它自己那份 **ad-hoc 签名**的同名 dmg，
# 可能把刚上传的公证版覆盖掉。所以等它结束，再把资产下回来验一遍。
if (( GO )); then
  sleep 10
  RUN_ID="$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  if [[ -n "$RUN_ID" ]]; then
    print "  等 release.yml（run $RUN_ID）…"
    gh run watch "$RUN_ID" --exit-status >/dev/null 2>&1 || warn "release.yml 失败或超时——继续复验资产"
  else
    warn "没找到 release.yml 的运行记录"
  fi

  VERIFY_DIR="$(mktemp -d)"
  gh release download "$TAG" -p '*.dmg' -D "$VERIFY_DIR" --clobber
  PUBLISHED_DMG="$(find "$VERIFY_DIR" -name '*.dmg' | head -1)"
  [[ -n "$PUBLISHED_DMG" ]] || die "从 Release 上下不回 dmg"

  MOUNT="$(mktemp -d)"
  hdiutil attach "$PUBLISHED_DMG" -mountpoint "$MOUNT" -nobrowse -quiet
  PUB_SPCTL="$(spctl -a -vv "$MOUNT/Anchor.app" 2>&1 || true)"
  hdiutil detach "$MOUNT" -quiet || true

  if print "$PUB_SPCTL" | grep -q "source=Notarized Developer ID"; then
    ok "已发布的资产确认是公证版"
  else
    warn "已发布的资产不是公证版——CI 覆盖了它，正在重新上传本地公证版"
    print "$PUB_SPCTL" | sed 's/^/    /'
    gh release upload "$TAG" "$DMG" --clobber
    ok "已重新上传；请重跑本脚本 --resume 以再次复验"
  fi
else
  print "  \033[90m[演练] 等 release.yml → 下载已发布 dmg → spctl 复验 → 被覆盖则重传\033[0m"
fi

# ---------- 8. appcast ----------
step "8/9 更新 appcast.xml"
if (( GO )); then
  SIG_OUT="$("$SIGN_UPDATE" "$DMG")"
  print "  sign_update: $SIG_OUT"
  ED_SIG="$(print "$SIG_OUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  [[ -n "$ED_SIG" ]] || die "没能从 sign_update 的输出里解析出 edSignature"

  # length 必须对着**已发布**的资产算：不一致 Sparkle 会静默拒绝更新。
  PUB_LEN="$(gh release view "$TAG" --json assets \
    --jq '.assets[] | select(.name|endswith(".dmg")) | .size' | head -1)"
  [[ -n "$PUB_LEN" ]] || die "取不到已发布 dmg 的字节数"
  LOCAL_LEN="$(stat -f%z "$DMG")"
  ok "已发布 $PUB_LEN 字节 / 本地 $LOCAL_LEN 字节"
  [[ "$PUB_LEN" == "$LOCAL_LEN" ]] \
    || die "字节数不一致（已发布 $PUB_LEN vs 本地 $LOCAL_LEN）。\n  说明 Release 上挂的不是这个文件——先把资产换成本地公证版再来。"

  python3 - "$VERSION" "$DOWNLOAD_URL" "$PUB_LEN" "$ED_SIG" <<'PY'
import pathlib, sys, re
from email.utils import formatdate
version, url, length, sig = sys.argv[1:5]
path = pathlib.Path("appcast.xml")
xml = path.read_text(encoding="utf-8")
if f"<sparkle:version>{version}</sparkle:version>" in xml:
    print(f"  appcast 里已有 {version}，跳过")
    raise SystemExit(0)
item = f"""    <item>
      <title>{version}</title>
      <pubDate>{formatdate(localtime=True)}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/TIFOSI528/anchor/releases/tag/v{version}</sparkle:releaseNotesLink>
      <enclosure
        url="{url}"
        length="{length}"
        type="application/octet-stream"
        sparkle:edSignature="{sig}" />
    </item>
"""
# 插在第一个 <item> 之前（最新版在最前）
updated, count = re.subn(r"([ \t]*<item>)", item + r"\1", xml, count=1)
if count != 1:
    raise SystemExit("appcast.xml 里找不到 <item>，无法插入——请手工检查")
path.write_text(updated, encoding="utf-8")
print(f"  已插入 {version}（length={length}）")
PY

  run git add appcast.xml
  run git commit -m "release: $TAG appcast"
  run git push origin main
else
  print "  \033[90m[演练] sign_update → 取已发布资产字节数 → 比对 → 插入 <item> → 提交推送\033[0m"
fi

# ---------- 9. 终验 ----------
step "9/9 终验"
if (( GO )); then
  APPCAST_LEN="$(grep -A6 "<sparkle:version>$VERSION</sparkle:version>" appcast.xml \
    | sed -n 's/.*length="\([0-9]*\)".*/\1/p' | head -1)"
  ASSET_LEN="$(gh release view "$TAG" --json assets \
    --jq '.assets[] | select(.name|endswith(".dmg")) | .size' | head -1)"
  print "    appcast length = $APPCAST_LEN"
  print "    已发布资产     = $ASSET_LEN"
  [[ "$APPCAST_LEN" == "$ASSET_LEN" ]] || die "appcast length 与已发布资产字节数不一致"
  ok "字节数一致"
  gh release view "$TAG" --json assets --jq '.assets[].name' | sed 's/^/    /'
  ok "发布完成：https://github.com/$REPO/releases/tag/$TAG"
else
  print "  \033[90m[演练] 比对 appcast length 与已发布资产字节数，并列出资产\033[0m"
  print "\n\033[1;33m演练结束。确认无误后重跑并加 --go。\033[0m"
fi
