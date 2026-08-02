import Foundation

/// 复制本文件为 `DefaultAPIKey.swift`，填入默认 AI Key。
/// 设置里 API Key 留空时使用此 Key，并自动走默认 AI（Moonshot）端点，与服务商选择无关。
/// 若要使用其它服务商，请在设置中填写对应 API Key。`DefaultAPIKey.swift` 已在 .gitignore 中。
enum DefaultAPIKey {
    static let kimi = ""
}
