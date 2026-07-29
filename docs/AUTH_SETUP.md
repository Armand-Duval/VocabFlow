# KnoWell 账号登录配置

## Apple 登录

**限制：** 免费「Personal Team」不支持 Sign in with Apple，只有 **付费 Apple Developer Program（$99/年）** 才能开启该 Capability。

当前默认 `KnoWell.entitlements` **不含** Apple 登录 entitlement，以便个人开发者账号正常签名真机调试。

### 个人开发者（当前默认）

- 可直接编译、安装到真机
- 设置页会显示灰色「通过 Apple 登录」占位 + 说明文案
- 微信登录 scaffold 仍保留（需自行配置 SDK）

### 升级到付费开发者账号后

1. Xcode → Target **KnoWell** → **Signing & Capabilities** → 添加 **Sign in with Apple**
2. 将 `KnoWell.entitlements.with-apple-signin` 的内容合并进 `KnoWell.entitlements`（或整体替换），确保包含：

```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

3. 重新生成 Provisioning Profile 并编译
4. 将 `Info.plist` 中 `APPLE_SIGN_IN_ENABLED` 改为 `true`
5. App 会显示可用的 Apple 登录按钮

---

## 微信登录

微信 iOS 登录**必须**同时满足：

| 项 | 说明 |
|----|------|
| 微信开放平台 AppID | [open.weixin.qq.com](https://open.weixin.qq.com/) 创建移动应用 |
| WechatOpenSDK | 下载 [iOS 开发工具包](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html) 并加入工程 |
| URL Scheme | `wx{你的AppID}` |
| Universal Link | 与开放平台配置一致 |
| 服务端 | 用 `code` 换 `access_token`（AppSecret **不能**放在客户端） |

### Info.plist

```xml
<key>WECHAT_APP_ID</key>
<string>wxXXXXXXXX</string>
<key>WECHAT_UNIVERSAL_LINK</key>
<string>https://your.domain.com/app/</string>
<key>AUTH_BACKEND_URL</key>
<string>https://api.your.domain.com/auth</string>
```

`AUTH_BACKEND_URL` 可选。配置后客户端 POST：

```json
{ "provider": "wechat", "code": "..." }
```

返回 `{ "userId", "displayName", "avatarURL"? }` 完成登录。

### SDK 接入后

1. 将 `WechatOpenSDK.xcframework` 拖入工程
2. 在 App 启动时调用 `WeChatSignInService.registerIfNeeded()`
3. 在 `onOpenURL` 中调用 `WeChatSignInService.handleOpenURL(_:)`

未链接 SDK 时，微信登录按钮会提示「需要配置微信 SDK」。

---

## 本地账号存储

- 登录态保存在 Keychain（`AccountStore`）
- 退出登录清除 Keychain，本地词库数据保留
