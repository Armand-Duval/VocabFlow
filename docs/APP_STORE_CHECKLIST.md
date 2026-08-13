# App Store 上架清单（v1）

工程侧已处理：隐藏未配置的登录、隐私清单、出口合规声明。  
下面只列 **需要你本人完成** 的事项。

## 必须你来做

1. **加入 Apple Developer Program**（约 $99/年）  
   https://developer.apple.com/programs/  
   免费个人团队不能上架。付费后把 Xcode 的 Team 换成付费团队。

2. **在 App Store Connect 创建 App**  
   Bundle ID：`com.knowell.app1`  
   名称建议：KnoWell；副标题可用：记住读过的 · 情景复习

3. **挂一份可公开访问的隐私政策 URL**  
   把 `docs/PRIVACY.md` 发到 GitHub Pages / 个人站点 / 语雀公开页。  
   Connect 的「隐私政策」栏必须填这个链接（不能只放在 App 里）。

4. **填写支持信息**  
   - 技术支持 URL 或邮箱（Connect 必填）  
   - 把同一邮箱补进隐私政策「联系」段

5. **截图**（真机）  
   至少 iPhone 6.7" 一组。建议 4 张：复习首页、复习中、制卡、词库。不要带 Dynamic Island 录屏指示。

6. **App 隐私问卷**  
   - 不用于追踪  
   - 用户内容（卡片原文）仅在用户填写自己的 AI Key 后发往第三方  
   - 相机：仅用于扫描制卡  
   - 无账号时不收集联系方式 / 身份

7. **出口合规**  
   选「使用豁免加密」（仅 HTTPS）。工程已加 `ITSAppUsesNonExemptEncryption = NO`。

8. **真机回归**  
   复习、制卡、分享导入、备份导出、首次隐私同意各走一遍。

## 第一版不要做（先关掉）

- 微信登录：开放平台 AppID、SDK、Universal Link、**自己的服务端** 都还没有  
- Apple 登录：要付费账号 + Capability；且一旦做第三方登录就必须同时做 Apple 登录和注销  
- iCloud：付费账号后再开，现在用本地备份即可

## 付费账号到位后（可选，非 v1 拦路）

- Xcode → Signing & Capabilities → Sign in with Apple，并设 `APPLE_SIGN_IN_ENABLED = true`  
- 应用内「删除账号」  
- iCloud / CloudKit 同步  
