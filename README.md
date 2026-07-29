# KnoWell

语境化多语言背单词 iOS App（MVP）。输入一句任意语言原文 + 生词，自动生成复习卡片，支持间隔重复复习。

## 功能

- **制卡**：粘贴任意语言原文，输入生词（逗号分隔），AI 生成挖空卡 + 释义卡
- **预览**：生成后可编辑、勾选，再保存到词库
- **复习**：简化版 SM-2 间隔重复（重来 / 困难 / 良好 / 简单）
- **词库**：按原句分组查看所有卡片，支持删除
- **备份**：导出/导入 JSON 备份（合并或替换），可用于换机和多设备同步
- **分享制卡**：从 Safari 等 App 分享文本 → 自动打开 KnoWell 并预填原文

## 分享扩展（Share Extension）

其他 App 选中文字 → 分享 → 选择 **KnoWell** → 自动跳转到制卡页，原文已填好。

### 开通开发者账号后需确认

1. Xcode → Target **KnoWell** 和 **KnoWellShare** → **Signing & Capabilities**
2. 两个 Target 都添加 **App Groups**：`group.com.knowell.app1`
3. 选择你的 **Paid Team** 重新签名
4. 真机安装后，在 Safari 选中文字 → 分享 → 更多 → 打开 KnoWell

## Kimi API 配置

1. 打开 App 的「设置」标签
2. 填入 Kimi API Key（在 [platform.moonshot.cn](https://platform.moonshot.cn) 获取）
3. 选择模型（默认 `moonshot-v1-8k` 即可）
4. 保存后回到「制卡」即可使用

未配置 Key 时会自动使用内置默认 Key；也可在设置里填写自己的 Key 优先使用。

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

```
KnoWell/
├── KnoWellApp.swift          # App 入口 + SwiftData
├── Models/FlashCard.swift      # 卡片数据模型
├── Services/
│   ├── KimiCardGenerator.swift # AI 制卡
│   └── ReviewScheduler.swift   # 间隔重复调度
└── Views/                      # SwiftUI 界面
```

## 数据备份与同步

### 导出 / 导入（设置 → 数据备份）

- **导出备份**：保存为 `knowell-backup.json`，可通过 AirDrop、文件 App 分享
- **导入备份**：
  - **合并导入**：保留现有卡片，同 ID 更新、新卡片追加
  - **替换全部**：清空词库后导入

### 多设备同步说明

- **个人免费 Apple 开发者账号不支持 iCloud 能力**，因此 App 使用本地存储
- 换机或多设备请用 **导出备份 → AirDrop/文件 App → 导入备份**
- 若以后加入 **付费开发者计划（$99/年）**，可再启用 iCloud 自动同步

## 下一步

- [x] 接入 Kimi API 真实制卡
- [x] 导出/导入备份
- [ ] iCloud 同步（需付费开发者账号）
- [ ] 点击选词（在原句中高亮选择生词）
- [ ] 分享扩展（从 Safari / 阅读 App 导入句子）
- [ ] FSRS 算法替换简化 SM-2

## 要求

- iOS 17.0+
- Xcode 15+
