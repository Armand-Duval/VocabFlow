# VocabFlow UI Backlog

> 功能链路完整；主要短板是视觉规范、交互反馈、合规展示。  
> 状态：`[ ]` 待做 · `[~]` 进行中 · `[x]` 已完成

---

## 已确认优点（不改导航）

- [x] 4 Tab 闭环：Create → Review → Library → Settings
- [x] Anki 生态：apkg / JSON 导入导出（词库包页）
- [x] SRS 四档评分（Show Answer 后 Again/Hard/Good/Easy + 间隔提示）
- [x] BYOK + 内置 Key
- [x] 释义 / 挖空筛选

---

## P0 — 快速改（1 天，消除 Demo 感）

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P0-1 | DesignTokens（间距/字号/圆角） | [x] | `Shared/DesignTokens.swift` |
| P0-2 | StatusChip 统一标签（Due/New/类型） | [x] | `Shared/StatusChip.swift` + `LibraryCardStatusChip` |
| P0-3 | 全局 Toast | [x] | `ToastCenter` + ContentView / 制卡 / 设置 / 导入 |
| P0-4 | Loading 遮罩 | [x] | 制卡 OCR/AI、词库包导入 |
| P0-5 | Due 标签浅橙底 + 角标规范 | [x] | StatusChip `.due` / `.new` / `.scheduled` |
| P0-6 | 置灰主按钮说明文案 | [x] | 制卡页底部 |
| P0-7 | SF Symbols 权重统一 | [ ] | Tab / 工具栏 `.regular` |

## P1 — 中期（1–3 天）

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P1-1 | Library 顶部导入/导出快捷入口 | [x] | 底部 Import / Export 栏 → 词库包 |
| P1-2 | 字体层级：28/20/16/13 | [~] | AppFont 已建，待全页套用 |
| P1-3 | OCR 按钮图标化 | [ ] | 制卡页 |
| P1-4 | 选词高亮反馈 | [ ] | SelectableTextEditor |
| P1-5 | Review 卡片压缩空白 + 大发音钮 | [x] | maxHeight 340 + 44pt 发音区 |
| P1-6 | Settings 模型参数 footer | [x] | 各 model 一行说明 |
| P1-7 | 搜索框清空 + 关键词高亮 | [~] | 清空已有；高亮待做 |
| P1-8 | 深色模式扫 hardcoded 色 | [ ] | 跟随系统 |
| P1-9 | Settings 隐私政策置顶 | [x] | About 区第一项 |

## P2 — 上架前 / 长期

| ID | 项 | 状态 | 说明 |
|----|----|------|------|
| P2-1 | AI 额度 / 会员页 | [ ] | App Store 3.1.1 |
| P2-2 | 启动隐私同意弹窗 | [ ] | 首次启动 |
| P2-3 | 开源协议二次确认 | [ ] | 社区 deck 导入 |
| P2-4 | Share Extension 空文本/超时 | [ ] | |
| P2-5 | apkg 批量/单卡导出 | [ ] | 阶段 1 功能 |
| P2-6 | 卡片归档/暂停复习 | [ ] | |
| P2-7 | 复习统计看板 | [ ] | |
| P2-8 | 动态字体 | [ ] | |

---

## 评估文档勘误（现版代码）

| 原评估 | 实际 |
|--------|------|
| 复习无四档评分 | 已有 |
| 删除/重置无确认 | 已有 confirmationDialog |
| API Key 无显隐 | 已有 eye 按钮 |
| 无 Toast | 已扩展为全局 ToastCenter |

---

## 变更日志

- **2026-07-26** 创建 backlog
- **2026-07-26** 完成 P0-1～P0-6、P1-1、P1-5、P1-6、P1-7（清空）、P1-9；Debug 编译通过

## 下一步建议

1. P0-7 + P1-2：全 App 套用 DesignTokens / AppFont  
2. P1-3～P1-4：制卡 OCR 图标化、选词高亮  
3. P1-8：深色模式  
4. 进入阶段 1 功能：apkg 批量导出、卡片暂停、按 deck 复习
