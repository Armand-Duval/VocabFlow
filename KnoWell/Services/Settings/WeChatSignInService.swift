import Foundation

enum WeChatSignInError: LocalizedError {
    case notConfigured
    case sdkNotLinked
    case wechatNotInstalled
    case missingCode
    case backendRequired
    case backendFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            L10n.accountWeChatNotConfigured
        case .sdkNotLinked:
            L10n.accountWeChatSDKNotLinked
        case .wechatNotInstalled:
            L10n.accountWeChatNotInstalled
        case .missingCode:
            L10n.accountWeChatMissingCode
        case .backendRequired:
            L10n.accountWeChatBackendRequired
        case .backendFailed(let message):
            L10n.accountWeChatBackendFailed(message)
        }
    }
}

@MainActor
enum WeChatSignInService {
    private static var pendingState: String?

    static func registerIfNeeded() {
        guard AccountAuthConfig.isWeChatConfigured,
              WeChatSDKBridge.isLinked,
              let appID = AccountAuthConfig.wechatAppID,
              let link = AccountAuthConfig.wechatUniversalLink else {
            return
        }
        _ = WeChatSDKBridge.register(appID: appID, universalLink: link)
    }

    static func startSignIn() async throws -> AccountProfile {
        guard AccountAuthConfig.isWeChatConfigured else {
            throw WeChatSignInError.notConfigured
        }
        guard WeChatSDKBridge.isLinked else {
            throw WeChatSignInError.sdkNotLinked
        }
        guard WeChatSDKBridge.isWeChatInstalled else {
            throw WeChatSignInError.wechatNotInstalled
        }

        let state = UUID().uuidString
        pendingState = state

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            authContinuation = continuation
            let started = WeChatSDKBridge.sendAuthRequest(state: state)
            if !started {
                authContinuation = nil
                continuation.resume(throwing: WeChatSignInError.sdkNotLinked)
            }
        }

        pendingState = nil
        return try await completeSignIn(with: code)
    }

    @MainActor
    static func resumeAuth(code: String) {
        authContinuation?.resume(returning: code)
        authContinuation = nil
        pendingState = nil
    }

    @MainActor
    static func failAuth(_ error: Error) {
        authContinuation?.resume(throwing: error)
        authContinuation = nil
        pendingState = nil
    }

    private static var authContinuation: CheckedContinuation<String, Error>?

    @discardableResult
    static func handleOpenURL(_ url: URL) -> Bool {
        if WeChatSDKBridge.handleOpenURL(url) {
            return true
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return false
        }

        let code = queryItems.first(where: { $0.name == "code" })?.value
        let state = queryItems.first(where: { $0.name == "state" })?.value

        guard let code, !code.isEmpty else { return false }
        if let pendingState, let state, pendingState != state {
            authContinuation?.resume(throwing: WeChatSignInError.missingCode)
            authContinuation = nil
            return true
        }

        authContinuation?.resume(returning: code)
        authContinuation = nil
        return true
    }

    static func notifyAuthDenied() {
        failAuth(WeChatSignInError.missingCode)
    }

    private static func completeSignIn(with code: String) async throws -> AccountProfile {
        if let backendURL = AccountAuthConfig.authBackendURL {
            return try await exchangeCodeViaBackend(code, backendURL: backendURL)
        }

        throw WeChatSignInError.backendRequired
    }

    private static func exchangeCodeViaBackend(_ code: String, backendURL: URL) async throws -> AccountProfile {
        var request = URLRequest(url: backendURL.appending(path: "wechat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["provider": "wechat", "code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw WeChatSignInError.backendFailed(message)
        }

        struct BackendUser: Decodable {
            let userId: String
            let displayName: String?
            let avatarURL: String?
        }

        let decoded = try JSONDecoder().decode(BackendUser.self, from: data)
        return AccountProfile(
            provider: .wechat,
            userID: decoded.userId,
            displayName: decoded.displayName,
            email: nil,
            avatarURL: decoded.avatarURL,
            signedInAt: .now
        )
    }
}

/// Runtime bridge for WechatOpenSDK (linked optionally).
enum WeChatSDKBridge {
    static var isLinked: Bool {
        NSClassFromString("WXApi") != nil
    }

    static var isWeChatInstalled: Bool {
        guard isLinked else { return false }
        return performBool(selector: "isWXAppInstalled")
    }

    @discardableResult
    static func register(appID: String, universalLink: String) -> Bool {
        guard isLinked else { return false }
        return performRegister(appID: appID, universalLink: universalLink)
    }

    static func sendAuthRequest(state: String) -> Bool {
        guard isLinked else { return false }
        guard let requestClass = NSClassFromString("SendAuthReq") as? NSObject.Type else {
            return false
        }
        let request = requestClass.init()
        request.setValue("snsapi_userinfo", forKey: "scope")
        request.setValue(state, forKey: "state")
        return performSend(request)
    }

    static func handleOpenURL(_ url: URL) -> Bool {
        guard isLinked else { return false }
        return performHandleURL(url)
    }

    private static func performRegister(appID: String, universalLink: String) -> Bool {
        guard let apiClass = NSClassFromString("WXApi") as? NSObject.Type else { return false }
        let selector = NSSelectorFromString("registerApp:universalLink:")
        guard apiClass.responds(to: selector) else { return false }
        let result = apiClass.perform(selector, with: appID, with: universalLink)
        return result != nil
    }

    private static func performSend(_ request: NSObject) -> Bool {
        guard let apiClass = NSClassFromString("WXApi") as? NSObject.Type else { return false }
        let selector = NSSelectorFromString("sendReq:completion:")
        guard apiClass.responds(to: selector) else { return false }
        let imp = apiClass.method(for: selector)
        typealias SendFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
        let function = unsafeBitCast(imp, to: SendFunc.self)
        var ok = false
        let block: @convention(block) (Bool) -> Void = { success in ok = success }
        function(apiClass, selector, request, block as AnyObject)
        return ok
    }

    private static func performHandleURL(_ url: URL) -> Bool {
        guard let apiClass = NSClassFromString("WXApi") as? NSObject.Type else { return false }
        let selector = NSSelectorFromString("handleOpenURL:delegate:")
        guard apiClass.responds(to: selector) else { return false }
        let result = apiClass.perform(selector, with: url, with: WeChatSDKDelegate.shared)
        return result != nil
    }

    private static func performBool(selector name: String) -> Bool {
        guard let apiClass = NSClassFromString("WXApi") as? NSObject.Type else { return false }
        let selector = NSSelectorFromString(name)
        guard apiClass.responds(to: selector) else { return false }
        typealias BoolMethod = @convention(c) (AnyObject, Selector) -> ObjCBool
        let imp = apiClass.method(for: selector)
        let function = unsafeBitCast(imp, to: BoolMethod.self)
        return function(apiClass as AnyObject, selector).boolValue
    }
}

private final class WeChatSDKDelegate: NSObject, @unchecked Sendable {
    static let shared = WeChatSDKDelegate()

    @objc func onResp(_ resp: NSObject) {
        guard NSStringFromClass(type(of: resp)).contains("SendAuthResp") else { return }
        let errCode = (resp.value(forKey: "errCode") as? Int32) ?? -1
        if errCode != 0 {
            Task { @MainActor in
                WeChatSignInService.failAuth(WeChatSignInError.missingCode)
            }
            return
        }
        guard let code = resp.value(forKey: "code") as? String, !code.isEmpty else {
            Task { @MainActor in
                WeChatSignInService.failAuth(WeChatSignInError.missingCode)
            }
            return
        }
        Task { @MainActor in
            WeChatSignInService.resumeAuth(code: code)
        }
    }
}
