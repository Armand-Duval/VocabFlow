#import "ExtensionOpenURL.h"

BOOL KWExtensionOpenURL(NSURL *url, UIResponder *responder) {
    UIResponder *current = responder;
    while (current != nil) {
        SEL selector = @selector(openURL:options:completionHandler:);
        if ([current respondsToSelector:selector]) {
            NSMethodSignature *signature = [current methodSignatureForSelector:selector];
            if (signature == nil) {
                current = current.nextResponder;
                continue;
            }
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = current;
            invocation.selector = selector;
            NSURL *argumentURL = url;
            [invocation setArgument:&argumentURL atIndex:2];
            NSDictionary *options = nil;
            [invocation setArgument:&options atIndex:3];
            void (^completion)(BOOL) = nil;
            [invocation setArgument:&completion atIndex:4];
            [invocation retainArguments];
            [invocation invoke];
            return YES;
        }
        current = current.nextResponder;
    }
    return NO;
}
