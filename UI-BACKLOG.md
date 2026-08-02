# KnoWell Backlog

> 校准分 ~78/100。双主线：**SRS 算法** + **Demo 感消除**（文字驱动 → 视觉优先）。  
> 状态：`[ ]` 待做 · `[~]` 进行中 · `[x]` 已完成

**已落地基础（不再跟踪）：** `AppComponents` 设计 token、全局 Toast、Loading 遮罩、StatusChip、滑动手势、apkg 导出、卡片编辑/暂停、按 deck 复习、`AppSectionHeader`、`appNavTitle`。

---

## 一级页面导航标题 — 最终方案（已确认）

| 页面 | 标题 | 策略 | 说明 |
|------|------|------|------|
| Create | 居中浅灰 **Create** / 制卡 | **保留弱化** | Tab 仅入口标识；切后台/分屏需锚点；顶部边距已压缩 |
| Review | 居中浅灰 **Review** / 复习 | **保留弱化** | 复习闭环；空白加载时唯一身份标识 |
| Library | **无标题** | **隐藏** | 搜索框 + deck chip + 列表即识别；搜索栏顶格 |
| Settings | 居中浅灰 **Settings** / 设置 | **保留弱化** | 多模块割裂；齿轮 Tab 辨识度低 |

**全局规范（`appNavTitle`）：**
- 字重 Medium · 色值 `#666666` · 字号 `callout`（略高于正文）
- inline 居中 · 非 large 黑体
- **二级页**（Deck 详情、卡片编辑等）：`.secondary` 样式，`#444` 略深对比

**文字原则（维持）：** 不新增模块小标题；长说明移出主界面；操作按钮仅短词（Generate、Show answer）。

---

## P0 — 今天可合（记忆科学性 + 第一印象）

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P0-1 | SRS 首次毕业 + Good/Easy 梯度 | [x] | UI 三档：不会(Again 短间隔) / 良好 3d / 简单 7d；Hard 并入不会 |
| P0-2 | 复习按钮语义底色 + 着色边框 | [x] | 不会浅红 / 良好中性 / 简单浅绿 |
| P0-3 | Settings「无限复习」Toggle | [x] | 一键同步 new + review limit 为 0 |
| P0-4 | 精简 Create 页常驻说明文字 | [x] | 移除 section footer 大段 hint；空态仅留占位一行 |
| P0-5 | 核心 CTA 图标 + 短标签 | [x] | 生成/导入/导出统一「图标 + 1～2 字」；DeckStore 文字列表改快捷 chip |

## P1 — 1–3 天（差异化 + 体验）

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P1-1 | 复习页显示当前 card 所属 deck | [x] | 混合复习时进度旁展示词库名 |
| P1-2 | Share Extension 实机回归 + 边界修复 | [ ] | 空文本、超时、图片 OCR 失败 |
| P1-3 | 首次复习手势引导 | [ ] | Coach mark 或动画示意四向滑动 |
| P1-4 | Create 顶部快捷卡片区 | [x] | 已回退：OCR 放回原文区 |
| P1-5 | 「待制作卡片」Banner 强化 | [x] | `PendingCardsBannerView` |
| P1-6 | Deck 状态可视化 | [ ] | 词库卡片数 + Due 比例进度条 |
| P1-7 | 首次打开一次性引导 | [ ] | 承接已删 footer 说明 |
| P1-8 | 报错改 Toast | [ ] | 致命错误才用 Alert |

## 质感 / 文字 / 导航（已完成摘要）

| 批次 | 状态 | 要点 |
|------|------|------|
| T-A/B 文字层级 | [x] | footer 清扫、AppSectionHeader、Share 精简 |
| U-P0/P1 Anti-Demo | [x] | Create 卡片化、Library 行瘦身、AppSurfaceCard、配额 progress 条 |
| N-1～N-5 导航标题 | [x] | appNavTitle、Library 无标题、Create 顶距压缩、#666 规范 |

## P2 — 上架前

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P2-1 | 复习统计看板 | [ ] | 聚合 new/review 今日数据 |
| P2-2 | 子词库 Subdeck | [ ] | 多层级 deck |
| P2-3 | AI 额度 / 会员页 | [ ] | App Store 3.1.1 |
| P2-4 | 启动隐私同意弹窗 | [ ] | 首次启动 |
| P2-5 | 开源协议二次确认 | [ ] | 社区 deck 导入 |
| P2-6 | 动态字体 | [ ] | Accessibility |
| P2-7 | AI 生成骨架屏 + 进度 | [ ] | 替代纯 ProgressView |
| P2-8 | 长按按钮 Tooltip | [ ] | 替代常驻说明 |
| P2-9 | 品牌主色 + 卡片阴影 | [x] | Teal accent + AppSurfaceCard 全站推广 |
| P2-10 | 导入进度条细化 | [ ] | current/total |
| P2-11 | 账号系统（Apple / 微信） | [x] | 设置页 AccountSettingsCard；见 `docs/AUTH_SETUP.md` |
| T-C2 | FlashCardDetail 阅读态去重复 label | [ ] | |
| T-C3 | Settings 卡片化（与 Create 统一） | [x] | ScrollView + AppSurfaceCard；底部 Save 栏 |

---

## 变更日志

- **2026-07-29** Ink & Sage 视觉跃迁：暖纸色板、首页大数字、减边框、文字链快捷入口、词库状态色点
- **2026-07-29** 致知 (KnoWell) 三 Tab 重构：设置进齿轮、三栏数据卡、线性紧凑图标、品牌色 `#1E6B5C`
- **2026-07-27** Deck 导入导出重构：当前词库 vs 全部词库；JSON 导入到选中 deck；修复 fileExporter 弹窗
- **2026-07-27** P0-1～3：SRS 毕业梯度、复习按钮语义色、无限复习 Toggle
- **2026-07-27** 导航标题最终方案固化；Create 顶距 -20%、Library 搜索顶格、#666 规范
- **2026-07-27** 质感 Anti-Demo + 导航弱化 + 文字批次 A/B
