# 发版手册（维护者）

> 发行渠道：**GitHub Releases 直发签名公证 dmg + Sparkle 自更新**。
> 不走 Mac App Store——沙盒会禁掉 NSWorkspace 全局监控 / CGEventTap / Sparkle，产品核心没了。

## 〇、一次性准备（约 1 小时 + 等 Apple 审核）

### 1. Apple Developer Program（$99/年）
1. https://developer.apple.com/programs/enroll 注册（个人即可）
2. Xcode → Settings → Accounts 登录后，Manage Certificates → 创建 **Developer ID Application** 证书
3. 记下证书名，形如 `Developer ID Application: Your Name (TEAMID10)`
4. App 专用密码（公证用）：https://appleid.apple.com → 登录与安全 → App 专用密码
5. 把公证凭证存进钥匙串（**推荐；密码不进 shell 历史/环境**）：
   ```bash
   xcrun notarytool store-credentials anchor-notary \
     --apple-id you@example.com --team-id TEAMID10
   # 按提示交互输入 App 专用密码；之后脚本只引用 profile 名
   export ANCHOR_NOTARY_PROFILE=anchor-notary
   ```

### 2. Sparkle 签名密钥（一次性）✅ 已生成（2026-06-12）
```bash
swift build   # 确保依赖已拉取
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```
- 私钥已在本机钥匙串（**备份它**：`generate_keys -x key.priv` 导出后存密码管理器）
- 公钥已烤进 `package-app.sh` 默认值：`eSu0nsFWgzHoc2PK4f9GyUy0pvOVVfITU9/uYgb3oB8=`

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
export ANCHOR_NOTARY_PROFILE="anchor-notary"   # 推荐：见上面 store-credentials
export ANCHOR_APPCAST_URL="https://raw.githubusercontent.com/TIFOSI528/anchor/main/appcast.xml"
# 公钥已是脚本默认值，无需设置；不用 profile 时退路：
# export ANCHOR_APPLE_ID=... ANCHOR_APPLE_PWD=... ANCHOR_TEAM_ID=...
```

## 一、每次发版

```bash
zsh scripts/release.sh 0.2.0        # 演练：只跑只读检查并打印计划
zsh scripts/release.sh 0.2.0 --go   # 真的发
```

脚本把下面「手工步骤」整条串起来了，并且加了三道以前只靠人记得的关卡：

- **公证没验过绝不推 tag**。推 tag 会触发 `release.yml`，而它上传的是 ad-hoc 签名的
  同名 dmg——先推 tag 再发现公证失败，Release 上就已经挂了一个被 Gatekeeper 拦死的包。
- **等 CI 跑完后把已发布的资产下载回来复验**，被 CI 覆盖就自动重传（见下方注意事项）。
- **appcast 的 `length` 对着「已发布」的资产算**，并与本地文件逐字节比对。不一致时
  Sparkle 是**静默**拒绝更新，是最难查的一类故障。

中断了可以 `--resume` 续跑（已完成的阶段会跳过，不会重复推送或重复打 tag）。

公证 profile 名脚本会自动探测（依次试 `dev`、`anchor-notary`），也可以自己
`export ANCHOR_NOTARY_PROFILE=...` 覆盖。

<details>
<summary>手工步骤（脚本坏了或想逐步来时用）</summary>

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

</details>

> **注意（最容易踩的一个坑）**：CI 里的 dmg 是 **ad-hoc 签名**（无证书 secrets 时），
> 而 `release.yml` 用的是同一个文件名。它可能把你刚上传的公证版**覆盖掉**，
> 于是 Release 页面看着有资产、下载下来却被 Gatekeeper 拦。
> `scripts/release.sh` 第 7 步就是为此存在的：等 CI 结束 → 把资产下回来 `spctl` 复验 →
> 被覆盖则重新上传。手工发版时务必自己做这一步，别只看 Release 页面有文件就以为好了。

## 二、发版检查单

- [ ] `swift test` 全绿
- [ ] CHANGELOG.md 增补本版条目
- [ ] dmg 在一台干净 Mac 上双击可开（无 Gatekeeper 阻拦 = 公证成功）
- [ ] `spctl -a -vv output/Anchor.app` 显示 accepted / Notarized Developer ID
- [ ] appcast.xml 已更新并可访问；旧版本 app 内「检查更新」能看到新版
- [ ] Release notes 附 demo GIF / 主要变更
