# 每日复盘规范

> 这是产品的第二张脸。灵动岛是"工作中的瞭望员"，每日复盘是"工作后的对话者"。

## 一、为什么不做 dashboard

绝大多数同类产品（Rize、Timing、RescueTime）做的是"数字墙"——堆图表、推百分比、给排名。**用户看两天就不打开了**，因为：

- 数字本身不产生 insight
- 图表需要用户自己解读
- 没有可执行建议

Anchor 的复盘是**叙事 + 可操作建议**：每天像一封朋友写给你的复盘信，附带数据可视化作为佐证。

## 二、信息架构

```
今日复盘（每天 22:00 灵动岛敲门后展开）
├── Header                     ← 日期 + 触发时间
├── Section 1: Score + 叙事     ← 产品的灵魂段
├── Section 2: 24h 时间线       ← 数据可视化主体
├── Section 3: 本周漂移热力图    ← 横向对比，找 pattern
├── Section 4: 今日罪人榜       ← 自嘲文化，传播性 hook
├── Section 5: 漂移链           ← 金矿数据，未来打深
└── Section 6: 周回顾预告       ← 引导用户养成"周日反思"习惯
```

可视化的最终视觉稿见 `Assets/Mockups/daily-recap.svg`（v1 设计稿）。

## 三、Deep Score 公式（必须公开）

```
raw_score = (绿区分钟 × 1.0)
          + (灰区分钟 × 0.3)
          - (红区分钟 × 1.5)
          - (漂移次数 × 0.5)

normalized_score = clamp(raw_score / (在线总分钟 × 1.0), 0, 1) × 100
```

**为什么公开**：
- Rize / RescueTime 都是黑箱算法，被骂多年。
- 开源版的天然优势是"公式我敢给你看"。
- 用户能自己 sanity check，对产品产生信任。

**用户可调权重**（v2）：让重度用户在 Settings 调整四个系数。但默认值经过初始用户测试后必须冻结，避免每次更新让历史 score 失真。

## 四、叙事生成

### 数据输入
当日 SessionStore 里的所有数据：
- 总在线分钟、绿/灰/红区分钟
- 漂移事件列表（时间戳、起点、目的地、停留时长、结束方式）
- 最长连续专注（Deep Streak）
- 当前 preset
- 过去 7 天同字段的滑动平均（用于横向对比）

### 生成策略（v1）
**模板引擎 + 条件分支**，不用 LLM。理由：
- v1 不引入云依赖（Local-first 原则）
- Apple Foundation Models 在 macOS 14 还不够稳，留到 v2 切换
- 模板能保证语气一致、不出幻觉

### 模板结构
固定三段：

**段 1：今日总览（事实陈述）**
```
今天你有 {deep_minutes} 分钟的真正专注，最长一段 {longest_streak_minutes}
分钟（{start_time}–{end_time}），{preset_name} preset。
```

**段 2：漂移模式（找出当日最大异常）**
- 如果有一个目的地占总漂移 ≥ 30%：
  ```
  漂出去 {drift_count} 次，其中 {top_destination_count} 次都去了
  {top_destination} —— 连续第 {consecutive_days} 天了。要加进黑名单吗？
  ```
- 如果分散：
  ```
  漂出去 {drift_count} 次，没有特别突出的去处——今天属于"无意识切换"型，
  不是被某个特定 app 吸住。
  ```

**段 3：节律观察（基于过去 7 天 pattern）**
- 如果存在固定时段漂移：
  ```
  {time_window} 是你今天最难稳住的时段，过去 7 天有 {n} 天也是。
  可能不是意志力，是节律。
  ```
- 否则：
  ```
  今天的漂移分布相对均匀，没有明显时段规律。
  ```

### v2 升级路径
切换到 Apple Foundation Models（macOS 15.2+），用 system prompt 注入"朋友式语气 + 给一条建议"约束。模板作为 fallback 留存。

## 五、可视化组件规范

### 1. 时间线（24h）
- 横向 bar，宽 600px × 高 36px
- 颜色映射：
  - `#22c55e` 深度绿区（连续 ≥ 15min）
  - `#86efac` 普通绿区
  - `#d1d5db` 灰区
  - `#fca5a5` 红区
  - `#f3f4f6` 离线
- 关键峰值标注：deep streak ≥ 30min 时上方加注解线 + 文字
- 关键低谷标注：连续 ≥ 10min 红区时下方加注解

### 2. 本周漂移热力图
- 5 行（周一–周五）× 7 列（8–22 时，每 2h 一格）
- 单元格 52 × 16 px，gap 0
- 颜色：`#fb923c` 橙色，opacity 0–1 线性映射漂移频率
- "今日" 这一行用 1px 绿色外框 + dashed "进行中" 提示
- 标注线圈出"连续多天的固定时段黑洞"

### 3. 今日罪人榜
- Top 3 时间小偷
- 每行：排名 + app/tab 名 + 时长 + 自嘲文案
- 配色：第 1 名红框，第 2、3 名橙框
- **自嘲文案库**（v1 用静态库 + 简单随机）：
  - "又赢了"
  - "假装在学习"
  - "摆烂"
  - "意料之中"
  - "今日 boss"
  - "稳定输出"

**严肃模式开关**：Settings 里一键关掉自嘲，改为中性文字（"38 分钟"），避免对正处于低谷期的用户造成冒犯。**自动触发**：当日 Deep Score < 30 时，自动切到严肃模式（不需用户操作）。

### 4. 漂移链
- 显示 Top 2 最常漂移路径
- 每条 chain：起点（蓝色 pill）→ 中间点（橙色 pill）→ 终点（红色 pill）
- 附带"本周触发 N 次 · 平均链路时长 X min"
- **未来打深方向**（v2+）：可交互力导向图，点击边能看每次触发的时间戳和上下文。这是产品最大的数据壁垒。

## 六、周回顾（周日 21:00 自动）

### 触发
- 默认每周日 21:00 push 通知
- 用户可在 Settings 改时间
- 用户可关闭

### 内容
1. 本周关键数据 + 同比上周差值
2. 本周最佳 / 最差日
3. **一条可执行建议**（核心 ROI）

### 建议生成规则（v1）
基于规则引擎，不用 LLM。三类候选规则：

**规则 A：黑名单建议**
```
触发条件：某个 URL/app 出现在漂移 Top 5 超过 5 天
建议：要不要把 {target} 加进 {preset_name} 的黑名单？
一键 apply：直接修改 preset 配置
```

**规则 B：preset 调整建议**
```
触发条件：某个 app 在绿区但每周触发漂移 > 20 次
（用户标了它是工作 app 但实际经常变摸鱼入口）
建议：{app} 经常成为漂移起点，要不要把它从 {preset_name} 绿区移到灰区？
```

**规则 C：节律建议**
```
触发条件：某固定时段连续 4+ 天高漂移
建议：要不要在 {time_window} 启用更严格的 {strict_preset}？
```

**关键约束**：
- 每周**只给一条建议**，永远不超过
- 必须**可撤销**（apply 后保留一周可一键回退）
- 必须**可解释**（建议附带数据来源："因为你周二、四、五都在 14–16 漂走"）

## 七、数据存储

### SQLite Schema
```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    preset_id TEXT,
    started_at INTEGER,
    ended_at INTEGER,
    green_seconds INTEGER,
    gray_seconds INTEGER,
    red_seconds INTEGER,
    drift_count INTEGER,
    longest_streak_seconds INTEGER,
    deep_score INTEGER
);

CREATE TABLE drifts (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id),
    occurred_at INTEGER,
    from_app TEXT,
    from_url TEXT,
    to_app TEXT,
    to_url TEXT,
    duration_seconds INTEGER,
    end_reason TEXT, -- "tap" | "long_press" | "swipe" | "auto_return" | "session_end"
    next_destination TEXT -- 用于漂移链分析
);

CREATE TABLE presets (
    id TEXT PRIMARY KEY,
    name TEXT,
    rules_json TEXT, -- 序列化的白/黑名单规则
    drift_threshold_seconds INTEGER DEFAULT 60,
    created_at INTEGER,
    updated_at INTEGER
);

CREATE TABLE daily_recaps (
    date TEXT PRIMARY KEY, -- ISO 8601 date
    deep_score INTEGER,
    narrative TEXT, -- 生成的叙事文本
    top_thieves_json TEXT,
    generated_at INTEGER
);

CREATE INDEX idx_drifts_session ON drifts(session_id);
CREATE INDEX idx_drifts_time ON drifts(occurred_at);
```

### 数据保留
- 默认保留 90 天明细
- 90 天前的数据聚合成每周快照（保留 daily_recaps + sessions 汇总）
- 用户可在 Settings 调整或一键清空

### 导出
- "导出为 Markdown 月报"：给 Obsidian / 日记用户的杀手锏
- "导出为 CSV"：给数据控
- 永远不能"上传到服务器"——这不是功能，是哲学

## 八、不做的（v1）

- ❌ 实时复盘（中途打断专注）
- ❌ 分享到社交媒体（功能后面有空再说，先做好私人体验）
- ❌ 月度复盘 / 年度复盘（先把日 / 周做好）
- ❌ 跨用户 leaderboard（永远不做，见 product-philosophy.md）
- ❌ AI 看屏幕识别"摸鱼内容"（v2 探索，v1 不开口子）

---

> **设计原则**：每个数字背后必须有一句话能告诉用户"这意味着什么"。看不懂的数据宁可不展示。
