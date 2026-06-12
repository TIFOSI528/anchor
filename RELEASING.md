# 发版手册（维护者）

> 发行渠道：**GitHub Releases 直发签名公证 dmg + Sparkle 自更新**。
> 不走 Mac App Store——沙盒会禁掉 NSWorkspace 全局监控 / CGEventTap / Sparkle，产品核心没了。

## 〇、一次性准备（约 1 小时 + 等 Apple 审核）

### 1. Apple Developer Program（$99/年）
1. https://developer.apple.com/programs/enroll 注册（个人即可）
2. Xcode → Settings → Accounts 登录后，Manage Certificates → 创建 **Developer ID Application** 证书
3. 记下证书名，形如 `Developer ID Application: Your Name (TEAMID10)`
4. App 专用密码（公证用）：https://appleid.apple.com → 登录与安全 → App 专用密码

### 2. Sparkle 签名密钥（一次性）
```bash
swift build   # 确保依赖已拉取
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```
- 私钥自动存入本机钥匙串（**备份它**；可 `generate_keys -x key.priv` 导出后存密码管理器）
- 打印出的**公钥**填进下面的 `ANCHOR_SPARKLE_PUBLIC_KEY`

### 3. GitHub 仓库
```bash
# 在 GitHub 网页建空仓库后：
git remote add origin git@github.com:TIFOSI528/anchor.git
git push -u origin main
```
推送后 `ci.yml`（build+test）即生效。（仓库：https://github.com/TIFOSI528/anchor）

### 4. 环境变量（本地发版用，放 ~/.zshrc 或临时 export）
```bash
export ANCHOR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID10)"
export ANCHOR_APPLE_ID="you@example.com"
export ANCHOR_APPLE_PWD="xxxx-xxxx-xxxx-xxxx"   # App 专用密码
export ANCHOR_TEAM_ID="TEAMID10"
export ANCHOR_SPARKLE_PUBLIC_KEY="<generate_keys 打印的公钥>"
export ANCHOR_APPCAST_URL="https://tifosi528.github.io/anchor/appcast.xml"
```

## 一、每次发版（本地，~10 分钟）

```bash
# 0. 确认绿
swift test

# 1. 版本号 + 打包 + 签名 + 公证 + dmg
export ANCHOR_VERSION=0.1.0
ANCHOR_NOTARIZE=1 zsh scripts/package-app.sh
# 产物：output/Anchor.app（已 staple）+ output/Anchor-0.1.0.dmg

# 2. Sparkle 签名 dmg
.build/artifacts/sparkle/Sparkle/bin/sign_update output/Anchor-0.1.0.dmg
# 记下输出的 sparkle:edSignature 和 length

# 3. 更新 appcast.xml（首版从 scripts/appcast-template.xml 复制）
#    填 版本 / pubDate / dmg 下载 URL（GitHub Release 资产地址）/ edSignature / length
#    发布到 GitHub Pages（репо里建 gh-pages 或 docs/ 托管均可）

# 4. tag + Release
git tag v0.1.0 && git push origin v0.1.0
# release.yml 会自动 build+test 并把 dmg 挂上 Release；
# 也可手动：gh release create v0.1.0 output/Anchor-0.1.0.dmg
```

> 注意：CI 里的 dmg 是 **ad-hoc 签名**（无证书 secrets 时）。对外发布请用上面本地
> 签名+公证的 dmg 替换 Release 资产，或在 repo secrets 配好证书后启用 CI 签名。

## 二、发版检查单

- [ ] `swift test` 全绿
- [ ] CHANGELOG.md 增补本版条目
- [ ] dmg 在一台干净 Mac 上双击可开（无 Gatekeeper 阻拦 = 公证成功）
- [ ] `spctl -a -vv output/Anchor.app` 显示 accepted / Notarized Developer ID
- [ ] appcast.xml 已更新并可访问；旧版本 app 内「检查更新」能看到新版
- [ ] Release notes 附 demo GIF / 主要变更
