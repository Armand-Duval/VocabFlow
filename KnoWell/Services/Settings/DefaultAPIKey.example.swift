import Foundation

/// 复制本文件为 `DefaultAPIKey.swift` 仅用于本地直连上游。
/// 设置里 API Key 留空时，正式版走 `KnoWellCloud`（`api.knowellcards.com`）。
/// `DefaultAPIKey.swift` 已在 .gitignore 中，不要把上游密钥提交进 git。
enum DefaultAPIKey {
    static let kimi = ""
    static let deepseek = ""
}
