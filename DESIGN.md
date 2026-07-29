# KnoWell Design System

> 工程代号 **KnoWell** · 品牌 **致知 (KnoWell)**  
> **Calm Study UI** — 三 Tab · 极简克制 · Teal `#239678`  
> UX 全文见 **[docs/UX_SPEC.md](docs/UX_SPEC.md)**

---

## 1. 品牌与产品调性

### 1.1 North Star

> **把读过的、见过的，变成记得住的。**

### 1.2 品牌命名（已定）

| 层级 | 值 |
|------|-----|
| **中文显示名** | 致知 |
| **英文** | KnoWell |
| **副标题** | 词卡复习，记住读过的 |
| **工程 Bundle** | `com.knowell.app1` |

### 1.3 Daily Tone

随手 · 回忆 · 情景 · 继续 · 安静（无金币排行；连续天数仅首页三栏弱展示）

### 1.4 Tab 结构

| 顺序 | Tab | 说明 |
|------|-----|------|
| 1 | 复习 | 默认首页 |
| 2 | 词库 | 卡组与检索 |
| 3 | 制卡 | AI 制卡 |
| — | 设置 | 右上角 ⚙️ Sheet |

### 1.5 竞品调研

见 **[docs/MARKET_POSITIONING.md](docs/MARKET_POSITIONING.md)**。

---

## 2. 设计原则

| 原则 | 说明 |
|------|------|
| **复习优先** | 打开 App 先看到「今天要学什么」 |
| **内容为王** | 一屏一个焦点：词 → 答案 → 评分 |
| **卡片即单元** | Deck、统计、配额、设置模块用 `AppSurfaceCard` |
| **品牌色克制** | Teal 用于强调，不全屏铺满 |
| **原生优先** | SF 字体、HIG 导航、系统动画 |
| **语义清晰** | 红/橙/绿仅用于学习反馈 |
| **开放工具** | 专业工具气质，非儿童游戏 / 非封闭运营 |

---

## 3. 色板（`AppColor`）

| Token | Light | 用途 |
|-------|-------|------|
| `accent` | `#2DB5A9` | 主色、选中、进度、单词高亮 |
| `accentStrong` | `#179487` | 主按钮、选中 Chip 文字 |
| `pageBackground` | `#F5F7FA` | 页面底 |
| `surface` | `#FFFFFF` | 卡片面 |
| `surfaceMuted` | `#F2F4F7` | 次要按钮、未选中 Chip |
| `border` | black 6% | 卡片描边 |
| `textPrimary` | `#1F2937` | 正文 |
| `textSecondary` | `#6B7280` | 说明、导航标题 |
| `success` | `#22C55E` | Easy / 掌握 |
| `warning` | `#FA8C3E` | Hard / 模糊 |
| `danger` | `#F0544F` | Again / 忘记 |

Dark Mode：见 `Shared/AppComponents.swift` 中 `Color.adaptive(light:dark:)`。

---

## 4. 间距与圆角

```
AppSpacing: xs=8  sm=12  md=16  lg=20  xl=24
AppRadius:  card=16  button=12  chip=999(capsule)
```

屏幕水平边距统一 `AppSpacing.md`（16pt）。

---

## 5. 字体（`AppFont`）

| 角色 | 样式 |
|------|------|
| 复习单词 | `studyWord()` — 34pt semibold rounded |
| Section 标题 | `sectionTitle()` — title3 semibold |
| 统计数字 | `statValue()` — title2 semibold |
| 正文 | `body()` |
| 辅助 | `secondary()` / `caption()` |
| 导航标题 | `navTitle()` — callout medium, `#666` 风格 |

---

## 6. 组件

| 组件 | 用途 |
|------|------|
| `AppSurfaceCard` | 白底 + 边框 + 轻阴影内容容器 |
| `AppStatTile` | 2 列统计格 |
| `PrimaryButtonStyle` | 实心 Teal 主操作 |
| `SecondaryButtonStyle` | 描边次要操作 |
| `RevealAnswerButtonStyle` | 复习「查看答案」灰底按钮 |
| `QuickActionChip` | 导入/导出等网格快捷操作 |
| `DeckFilterChip` / `FilterChip` | 横向筛选 |
| `AppEmptyState` | 空状态（图标 + 标题 + 可选 CTA） |

---

## 7. 页面模板

### 复习（Review）
- 顶部：进度 `2/10` + 可选 deck 名
- 中部：Teal 大号单词 + 音标 + 白卡片（正面/背面）
- 底部：「查看答案」→ 四档评分（带间隔预览）

### 列表（Library / DeckStore）
- `ScrollView` + `AppSurfaceCard` 分区（避免纯系统 List 设置风）
- 行内：主标题 semibold + 次要信息 caption

### 设置（Settings）
- `ScrollView` + 多卡片 + 底部固定 Save 栏

### 导航标题
- Tab 页：居中浅灰 `#666`，callout medium（`appNavTitle`）
- Library：无标题，搜索 + Chip 识别
- 二级页：`.secondary` 略深

---

## 8. Tab 结构

| 顺序 | Tab | 图标 |
|------|-----|------|
| 1 | 复习 | clock |
| 2 | 词库 | books.vertical.fill |
| 3 | 创建 | plus.circle |
| 4 | 我的 | person.crop.circle |

---

## 9. Do / Don't

**Do**
- 用 `AppColor.textPrimary` / `textSecondary` 替代裸 `.primary` / `.secondary`
- 列表页 `scrollContentBackground(.hidden)` + `appPageBackground()`
- 致命错误 Alert，其余 Toast

**Don't**
- 混用 `.borderedProminent` 与 `PrimaryButtonStyle`
- 大面积 `.regularMaterial` / `.bar`（破坏卡片层次）
- 装饰性渐变背景
- 同一语义多种字号（如 section 标题混用 title2/title3）

---

## 10. 账号与登录（Account）

- **Apple 登录**：`AuthenticationServices`，Sign in with Apple entitlement
- **微信登录**：需 [微信开放平台](https://open.weixin.qq.com/) AppID + iOS SDK + Universal Link + **服务端** code 换 token  
- 配置项见 `Info.plist`：`WECHAT_APP_ID`、`WECHAT_UNIVERSAL_LINK`、`AUTH_BACKEND_URL`
- 详细步骤：`docs/AUTH_SETUP.md`

---

## 11. 参考

- [Apple HIG — Clarity / Deference / Depth](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- Health / Reminders：卡片统计、今日任务
- 学习类产品：复习动线、评分间隔可见（借鉴结构，非拷贝视觉）
