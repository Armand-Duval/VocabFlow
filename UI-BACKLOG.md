# VocabFlow Backlog

> 校准分 ~78/100。双主线：**SRS 算法** + **Demo 感消除**（文字驱动 → 视觉优先）。  
> 状态：`[ ]` 待做 · `[~]` 进行中 · `[x]` 已完成

**已落地基础（不再跟踪）：** `AppComponents` 设计 token、全局 Toast、Loading 遮罩、StatusChip、滑动手势、apkg 导出、卡片编辑/暂停、按 deck 复习。

---

## P0 — 今天可合（记忆科学性 + 第一印象）

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P0-1 | SRS 首次毕业 + Hard/Good 梯度 | [ ] | `ReviewScheduler.mutate`：Again 10min → Hard 1d → Good 3d → Easy 7d |
| P0-2 | 复习按钮语义底色 + 着色边框 | [ ] | Again 浅红 / Hard 浅黄 / Good 白 / Easy 浅绿 |
| P0-3 | Settings「无限复习」Toggle | [ ] | 一键同步 new + review limit 为 0 |
| P0-4 | 精简 Create 页常驻说明文字 | [x] | 移除 section footer 大段 hint；空态仅留占位一行 |
| P0-5 | 核心 CTA 图标 + 短标签 | [x] | 生成/导入/导出统一「图标 + 1～2 字」；DeckStore 文字列表改快捷 chip |

## P1 — 1–3 天（差异化 + 体验）

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P1-1 | 复习页显示当前 card 所属 deck | [ ] | 混合复习时进度旁展示词库名 |
| P1-2 | Share Extension 实机回归 + 边界修复 | [ ] | 空文本、超时、图片 OCR 失败；`ExtensionImportViewController` |
| P1-3 | 首次复习手势引导 | [ ] | Coach mark 或动画示意四向滑动 |
| P1-4 | Create 顶部快捷卡片区 | [x] | 相册 / 相机 / 待制卡 三入口置顶 |
| P1-5 | 「待制作卡片」Banner 强化 | [x] | `PendingCardsBannerView`；Share 草稿手动进预览 |
| P1-6 | Deck 状态可视化 | [ ] | 词库卡片数 + Due 比例进度条；空库用 `AppEmptyState` 插图态 |
| P1-7 | 首次打开一次性引导 | [ ] | 制卡 / 复习 / Share 各一句；`UserDefaults` 只展示一次 |
| P1-8 | 报错改 Toast、保留 Alert 仅致命错误 | [ ] | 导入失败/导出成功等走 `ToastCenter`；减少 `alert` 弹窗 |

## P2 — 上架前

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P2-1 | 复习统计看板 | [ ] | 聚合 `newStudiedToday` / `reviewStudiedToday`、累计、遗忘率 |
| P2-2 | 子词库 Subdeck | [ ] | 多层级 deck 分类 |
| P2-3 | AI 额度 / 会员页 | [ ] | App Store 3.1.1 |
| P2-4 | 启动隐私同意弹窗 | [ ] | 首次启动 |
| P2-5 | 开源协议二次确认 | [ ] | 社区 deck 导入 |
| P2-6 | 动态字体 | [ ] | 全局字号 / Accessibility |
| P2-7 | AI 生成骨架屏 + 进度 | [ ] | 替代纯 `ProgressView` 文字遮罩；显示百分比或步骤 |
| P2-8 | 长按按钮 Tooltip | [ ] | 替代页面常驻说明；`contextMenu` 或自定义 popover |
| P2-9 | 品牌主色 + 卡片阴影层级 | [ ] | 固定 accent 色值；页面浅底 + 卡片白底 + 微弱 shadow |
| P2-10 | 导入进度条细化 | [ ] | apkg/大库导入显示 `current/total` 进度条（数据已有） |

---

## Demo 感诊断 ↔ 代码现状

| 评估说法 | 现状 | 待办 |
|---------|------|------|
| 全无视觉规范 | 部分成立 | `AppComponents` 已有 token，但未全页贯彻；P2-9 |
| 无 Toast / 无 Loading | **已解决** | Toast + LoadingOverlay 已全局 |
| 全文字按钮 | 部分成立 | OCR 已图标化；生成/导入导出仍偏文字；P0-5 |
| 大段 footer 说明 | **仍成立** | Create/Library/Settings 多处 helper 文案；P0-4、P1-7 |
| 无空态占位 | 部分成立 | `AppEmptyState` 有，缺定制插图；P1-6 |
| Share 后需手动找入口 | 部分成立 | 会自动切 Tab + banner，但不够醒目；P1-5 |
| 无进度可视化 | 部分成立 | 导入有 progress state，UI 仅 overlay 文字；P2-10 |

---

## 变更日志

- **2026-07-27** 按产品质量评估重组 backlog；移除已完成项
- **2026-07-27** P0-4/5 + P1-4/5：QuickActionChip、Create 快捷区、PendingCardsBanner、DeckStore/Library 短标签
