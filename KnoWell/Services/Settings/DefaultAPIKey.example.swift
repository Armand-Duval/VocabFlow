import Foundation

/// 复制本文件为 `DefaultAPIKey.swift`，填入默认 AI Key。
/// 设置里 API Key 留空时：
/// - Moonshot / 其它无自带默认 Key 的服务商 → 使用 `kimi`（走 Moonshot）
/// - DeepSeek → 使用 `deepseek`（走 DeepSeek）
/// `DefaultAPIKey.swift` 已在 .gitignore 中。
enum DefaultAPIKey {
    static let kimi = ""
    static let deepseek = ""
}
