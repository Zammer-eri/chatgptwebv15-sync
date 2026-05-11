#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSTimeInterval gLastUserTouchTime = 0;
static BOOL gDidSwizzleApplication = NO;
static BOOL gDidSwizzleChildView = NO;

static void (*gOriginalSendEvent)(UIApplication*, SEL, UIEvent*) = NULL;
static BOOL (*gOriginalChildViewResignFirstResponder)(id, SEL) = NULL;

static NSTimeInterval ChatGPTShellNow(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

static void ChatGPTShellRecordUserTouch(UIEvent* event) {
    if (event.type != UIEventTypeTouches) {
        return;
    }

    for (UITouch* touch in event.allTouches) {
        if (touch.phase == UITouchPhaseBegan) {
            gLastUserTouchTime = ChatGPTShellNow();
            return;
        }
    }
}

static BOOL ChatGPTShellTextInputHasDraft(id object) {
    if (![object conformsToProtocol:@protocol(UITextInput)]) {
        return NO;
    }

    id<UITextInput> textInput = (id<UITextInput>)object;
    UITextPosition* start = textInput.beginningOfDocument;
    UITextPosition* end = textInput.endOfDocument;
    if (!start || !end) {
        return NO;
    }

    UITextRange* range = [textInput textRangeFromPosition:start toPosition:end];
    if (!range) {
        return NO;
    }

    NSString* text = [textInput textInRange:range] ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"\u200B" withString:@""];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text.length > 0;
}

static void ChatGPTShellGuardedSendEvent(UIApplication* application, SEL selector, UIEvent* event) {
    ChatGPTShellRecordUserTouch(event);
    if (gOriginalSendEvent) {
        gOriginalSendEvent(application, selector, event);
    }
}

static BOOL ChatGPTShellGuardedChildViewResignFirstResponder(id view, SEL selector) {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        if (gOriginalChildViewResignFirstResponder) {
            return gOriginalChildViewResignFirstResponder(view, selector);
        }
        return YES;
    }

    const NSTimeInterval elapsedSinceTouch = ChatGPTShellNow() - gLastUserTouchTime;
    const BOOL recentUserTouch = elapsedSinceTouch >= 0 && elapsedSinceTouch < 0.8;

    if (!recentUserTouch &&
        [view isKindOfClass:[UIView class]] &&
        [view isFirstResponder] &&
        [view window] &&
        ChatGPTShellTextInputHasDraft(view)) {
        return NO;
    }

    if (gOriginalChildViewResignFirstResponder) {
        return gOriginalChildViewResignFirstResponder(view, selector);
    }

    return YES;
}

static void ChatGPTShellSwizzleApplication(void) {
    if (gDidSwizzleApplication) {
        return;
    }

    Method method = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
    if (!method) {
        return;
    }

    gOriginalSendEvent = (void (*)(UIApplication*, SEL, UIEvent*))method_getImplementation(method);
    method_setImplementation(method, (IMP)ChatGPTShellGuardedSendEvent);
    gDidSwizzleApplication = YES;
}

static void ChatGPTShellSwizzleChildViewIfAvailable(void) {
    if (gDidSwizzleChildView) {
        return;
    }

    Class childViewClass = NSClassFromString(@"ChildView");
    if (!childViewClass) {
        return;
    }

    Method method = class_getInstanceMethod(childViewClass, @selector(resignFirstResponder));
    if (!method) {
        return;
    }

    gOriginalChildViewResignFirstResponder = (BOOL (*)(id, SEL))method_getImplementation(method);
    method_setImplementation(method, (IMP)ChatGPTShellGuardedChildViewResignFirstResponder);
    gDidSwizzleChildView = YES;
}

static void ChatGPTShellInstallKeyboardGuardWithAttempts(NSUInteger attemptsRemaining) {
    ChatGPTShellSwizzleApplication();
    ChatGPTShellSwizzleChildViewIfAvailable();

    if (gDidSwizzleChildView || attemptsRemaining == 0) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ChatGPTShellInstallKeyboardGuardWithAttempts(attemptsRemaining - 1);
    });
}

__attribute__((constructor)) static void ChatGPTShellKeyboardGuardConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ChatGPTShellInstallKeyboardGuardWithAttempts(20);
    });
}
