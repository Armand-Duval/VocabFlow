# KnoWell

致知（KnoWell）：通用文本精读闪卡。从任意文本摘录句子与知识点，AI 生成语境卡片，用间隔重复记住；兼容 Anki / JSON。

## 功能

- **制卡**：粘贴任意语言原文，输入生词（逗号分隔），AI 生成挖空卡 + 释义卡；支持选词高亮、OCR 拍照/相册
- **预览**：生成后可编辑、勾选，再保存到词库
- **复习**：FSRS 间隔重复（不会 / 良好 / 简单；支持下滑揭晓、左右滑评分）
- **词库**：按原句分组查看所有卡片，支持删除、暂停、按 deck 复习
- **备份**：导出/导入 JSON 备份（合并或替换），可用于换机和多设备同步；支持 apkg
- **分享制卡**：从 Safari 等 App 分享文本 → 自动打开 KnoWell 并预填原文

## 分享扩展（Share Extension）

其他 App 选中文字 → 分享 → 选择 **KnoWell** → 自动跳转到制卡页，原文已填好。

### 开通开发者账号后需确认

1. Xcode → Target **KnoWell** 和 **KnoWellShare** → **Signing & Capabilities**
2. 两个 Target 都添加 **App Groups**：`group.com.knowell.app1`
3. 选择你的 **Paid Team** 重新签名
4. 真机安装后，在 Safari 选中文字 → 分享 → 更多 → 打开 KnoWell

## AI API 配置

1. 打开 App 的「设置」
2. 默认服务商为 **DeepSeek**（也可改选 Moonshot / Kimi、OpenAI 等）
3. 填入对应 API Key；留空则使用内置默认 Key（优先 DeepSeek；上架构建请勿依赖内置 Key）
4. 选择模型后保存，回到「制卡」即可使用

## 运行

1. 用 Xcode 打开 `KnoWell.xcodeproj`
2. 选择 iPhone 模拟器或真机
3. 首次运行需在 **Signing & Capabilities** 中选择你的 Development Team
4. `Cmd + R` 运行

命令行编译（模拟器）：

```bash
cd ~/Projects/KnoWell
xcodebuild -scheme KnoWell -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## 使用示例

1. 打开「制卡」标签
2. 原句：`The government took measures to mitigate the effects of climate change.`
3. 生词：`mitigate, measures`
4. 点击「AI 生成卡片」→ 预览 → 保存
5. 切换到「复习」开始记忆

## 项目结构

目录与 Tab / 跳转一致（一级 = 入口域，二级 = 该域页面与服务）：

```
KnoWell/
├── KnoWellApp.swift
├── Models/
├── Views/
│   ├── ContentView.swift          # Tab 壳：复习 / 词库 / 制卡 / 设置
│   ├── Review/                    # Tab1 + 复习会话
│   ├── Library/                   # Tab2 → 卡片详情 / 词库管理 / 统计
│   ├── Create/                    # Tab3 → 预览保存
│   ├── Settings/                  # Tab4 设置 → 账号 / 隐私
│   └── Common/
└── Services/
    ├── Core/                      # SwiftData 容器等
    ├── Review/                    # 队列 / FSRS / 提醒
    ├── Library/                   # Deck / apkg / 列表缓存
    ├── Create/                    # AI 制卡 / 分享导入
    └── Settings/                  # 账号 / 备份 / API Key
```

## 数据备份与同步

### 导出 / 导入（设置 → 数据备份）

- **导出备份**：保存为 `knowell-backup.json`，可通过 AirDrop、文件 App 分享
- **导入备份**：
  - **合并导入**：保留现有卡片，同 ID 更新、新卡片追加
  - **替换全部**：清空词库后导入

### 多设备同步说明

- **个人免费 Apple 开发者账号不支持 iCloud 能力**，因此 App 使用本地存储
- 换机或多设备请用 **导出备份 → AirDrop/文件 App → 导入备份**（亦可开启每日自动备份）
- 若以后加入 **付费开发者计划（$99/年）**，可再启用 iCloud 自动同步

## 下一步

- [x] 接入 Kimi / DeepSeek API 真实制卡
- [x] 导出/导入备份
- [x] 分享扩展（从 Safari / 阅读 App 导入句子）
- [x] 点击选词（在原句中高亮选择生词）
- [x] FSRS 算法替换简化 SM-2
- [ ] iCloud 同步（需付费开发者账号）
- [ ] AI 额度 / 会员页（App Store 上架）
- [ ] 动态字体（Accessibility）

## 要求

- iOS 17.0+
- Xcode 15+
