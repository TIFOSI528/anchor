# 贡献 Anchor

欢迎贡献！在动手前请先读 [`docs/product-philosophy.md`](docs/product-philosophy.md)——所有 PR 决策都从那里开始。

## 开发环境

- macOS 14+
- Xcode 16+ / Swift 6.0+
- Node.js 20+（如果改浏览器扩展）

## 本地启动

```bash
# 克隆
git clone https://github.com/TIFOSI528/anchor.git
cd anchor

# 构建
swift build

# 跑测试
swift test

# 打开 Xcode 调试
open Package.swift
```

首次启动 Xcode 会自动 resolve 三个外部依赖：SQLite.swift、DynamicNotchKit、Sparkle。

## PR 流程

1. **Issue 优先**：先在 Issues 里开一个 issue 描述你想做什么，等讨论收敛后再写代码，避免白干。
2. **Fork → 分支 → PR**：分支名格式 `feature/xxx`、`fix/xxx`、`docs/xxx`。
3. **小 PR**：每个 PR 不超过 400 行改动，超过的拆分。
4. **必须带测试**：AnchorCore 的逻辑改动必须配单元测试。
5. **CI 必须绿**：构建 + 测试 + lint 都过。

## Review 优先级

按重要性排序：

1. **哲学是否对齐**——回到 `product-philosophy.md` 的"三条立场"和"三条不做"。
2. **是否有测试**——AnchorCore 改动必须配测试，AnchorApp / UI 改动手测脚本。
3. **代码质量**——可读 > 巧妙，命名清晰，函数短。
4. **性能预算**——见 `docs/technical-architecture.md` §VI。

## Commit 信息

使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 格式：

```
feat(core): add drift threshold per-preset override

详细描述（可选）。

Closes #42
```

类型：`feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `perf`

## 报告 Bug

去 [Issues](https://github.com/TIFOSI528/anchor/issues/new) 用 bug 模板。请附：

- macOS 版本（`sw_vers`）
- Anchor 版本（菜单栏 → About）
- 复现步骤
- 期望行为 vs 实际行为
- 控制台日志（`log show --predicate 'subsystem == "com.anchor.app"' --last 5m`）

## 提建议

去 [Discussions](https://github.com/TIFOSI528/anchor/discussions) 开帖。在动手开发任何新功能前，建议先讨论。

## 不接受的贡献

参考 `product-philosophy.md` 的"三条不做"：

- ❌ Team mode / 社交压力功能
- ❌ 反作弊 / 不可卸载功能
- ❌ 跨平台支持（v1 周期内）
- ❌ 任何引入云依赖的功能
- ❌ 任何遥测 / 分析 SDK

## 行为准则

简单一句：**所有讨论都对事不对人**。粗鲁、人身攻击、骚扰会被立刻 ban。

---

> 维护者会优先 review 这几类 PR：bug 修复 > Accessibility 改进 > 性能优化 > 内置 preset 增加 > 文档 > 新功能。
