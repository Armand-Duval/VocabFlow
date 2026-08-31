#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Same approach Chrome uses in `ExtensionOpenURL`: walk the responder chain and
/// invoke `openURL:options:completionHandler:` via NSInvocation.
BOOL KWExtensionOpenURL(NSURL *url, UIResponder *responder);

NS_ASSUME_NONNULL_END
