#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSTimeInterval gLastUserInteractionTime = 0;
static BOOL gDidSwizzleApplication = NO;
static BOOL gDidSwizzleResponder = NO;
static NSUInteger gSwizzledTextInputClassCount = 0;
static __weak UIResponder* gCapturedFirstResponder = nil;

static void (*gOriginalSendEvent)(UIApplication*, SEL, UIEvent*) = NULL;
static BOOL (*gOriginalResponderResignFirstResponder)(id, SEL) = NULL;
static NSMapTable* gOriginalClassResignImplementations = nil;

@interface UIResponder (ChatGPTShellKeyboardGuard)
- (void)chatgptShell_captureFirstResponder:(id)sender;
@end

@implementation UIResponder (ChatGPTShellKeyboardGuard)
- (void)chatgptShell_captureFirstResponder:(id)sender {
    gCapturedFirstResponder = self;
}
@end

static NSTimeInterval ChatGPTShellNow(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

static NSString* ChatGPTShellLogPath(void) {
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documents = paths.firstObject ?: NSTemporaryDirectory();
    return [documents stringByAppendingPathComponent:@"chatgpt-shell-keyboard.log"];
}

static void ChatGPTShellLog(NSString* format, ...) {
    va_list args;
    va_start(args, format);
    NSString* message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString* line = [NSString stringWithFormat:@"%.3f %@\n", ChatGPTShellNow(), message];
    NSLog(@"%@", [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);

    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("chatgpt.shell.keyboard.log", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(queue, ^{
        NSString* path = ChatGPTShellLogPath();
        NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        if ([attributes fileSize] > 512 * 1024) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    });
}

static UIResponder* ChatGPTShellCurrentFirstResponder(void) {
    gCapturedFirstResponder = nil;
    [[UIApplication sharedApplication] sendAction:@selector(chatgptShell_captureFirstResponder:)
                                               to:nil
                                             from:nil
                                         forEvent:nil];
    UIResponder* responder = gCapturedFirstResponder;
    gCapturedFirstResponder = nil;
    return responder;
}

static NSString* ChatGPTShellClassChain(id object) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        [names addObject:NSStringFromClass(cls)];
        if (cls == [UIResponder class]) {
            break;
        }
    }
    return [names componentsJoinedByString:@"<-"];
}

static void ChatGPTShellRecordUserInteraction(UIEvent* event) {
    if (event.type != UIEventTypeTouches && event.type != UIEventTypePresses) {
        return;
    }

    if (event.type == UIEventTypePresses) {
        gLastUserInteractionTime = ChatGPTShellNow();
        return;
    }

    for (UITouch* touch in event.allTouches) {
        if (touch.phase == UITouchPhaseBegan) {
            gLastUserInteractionTime = ChatGPTShellNow();
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

static BOOL ChatGPTShellIsCustomWebTextInput(id object) {
    if (![object isKindOfClass:[UIView class]]) {
        return NO;
    }
    if ([object isKindOfClass:[UITextField class]] || [object isKindOfClass:[UITextView class]]) {
        return NO;
    }
    return [object conformsToProtocol:@protocol(UITextInput)];
}

static BOOL ChatGPTShellShouldBlockResign(id object) {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        return NO;
    }
    if (!ChatGPTShellIsCustomWebTextInput(object)) {
        return NO;
    }
    if (![object isFirstResponder] || ![(UIView*)object window]) {
        return NO;
    }

    const NSTimeInterval elapsedSinceUserInteraction = ChatGPTShellNow() - gLastUserInteractionTime;
    if (elapsedSinceUserInteraction >= 0 && elapsedSinceUserInteraction < 0.8) {
        return NO;
    }

    return ChatGPTShellTextInputHasDraft(object);
}

static BOOL ChatGPTShellCallOriginalResign(id object, SEL selector) {
    BOOL (*implementation)(id, SEL) = NULL;
    @synchronized ([UIApplication class]) {
        NSValue* value = [gOriginalClassResignImplementations objectForKey:object_getClass(object)];
        implementation = (BOOL (*)(id, SEL))value.pointerValue;
    }
    if (!implementation) {
        implementation = gOriginalResponderResignFirstResponder;
    }
    if (implementation) {
        return implementation(object, selector);
    }
    return YES;
}

static BOOL ChatGPTShellGuardedResignFirstResponder(id object, SEL selector) {
    const BOOL isRelevantInput = ChatGPTShellIsCustomWebTextInput(object);
    if (isRelevantInput) {
        ChatGPTShellLog(
            @"resign attempt class=%@ first=%d draft=%d elapsed=%.3f app=%ld",
            ChatGPTShellClassChain(object),
            [object isFirstResponder],
            ChatGPTShellTextInputHasDraft(object),
            ChatGPTShellNow() - gLastUserInteractionTime,
            (long)[[UIApplication sharedApplication] applicationState]
        );
    }

    if (ChatGPTShellShouldBlockResign(object)) {
        ChatGPTShellLog(@"blocked resign class=%@", ChatGPTShellClassChain(object));
        return NO;
    }

    return ChatGPTShellCallOriginalResign(object, selector);
}

static void ChatGPTShellGuardedSendEvent(UIApplication* application, SEL selector, UIEvent* event) {
    ChatGPTShellRecordUserInteraction(event);
    if (gOriginalSendEvent) {
        gOriginalSendEvent(application, selector, event);
    }
}

static BOOL ChatGPTShellClassIsSubclassOf(Class cls, Class parent) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        if (current == parent) {
            return YES;
        }
    }
    return NO;
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
    ChatGPTShellLog(@"installed UIApplication sendEvent guard");
}

static void ChatGPTShellSwizzleResponder(void) {
    if (gDidSwizzleResponder) {
        return;
    }

    Method method = class_getInstanceMethod([UIResponder class], @selector(resignFirstResponder));
    if (!method) {
        return;
    }

    gOriginalResponderResignFirstResponder = (BOOL (*)(id, SEL))method_getImplementation(method);
    method_setImplementation(method, (IMP)ChatGPTShellGuardedResignFirstResponder);
    gDidSwizzleResponder = YES;
    ChatGPTShellLog(@"installed UIResponder resignFirstResponder guard");
}

static void ChatGPTShellSwizzleCustomTextInputClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        return;
    }

    Class* classes = (Class*)calloc((size_t)count, sizeof(Class));
    if (!classes) {
        return;
    }
    count = objc_getClassList(classes, count);

    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!ChatGPTShellClassIsSubclassOf(cls, [UIView class])) {
            continue;
        }
        if (cls == [UITextField class] || cls == [UITextView class]) {
            continue;
        }
        if (!class_conformsToProtocol(cls, @protocol(UITextInput))) {
            continue;
        }

        Method method = class_getInstanceMethod(cls, @selector(resignFirstResponder));
        if (!method) {
            continue;
        }

        IMP current = method_getImplementation(method);
        if (current == (IMP)ChatGPTShellGuardedResignFirstResponder ||
            current == (IMP)gOriginalResponderResignFirstResponder) {
            continue;
        }

        @synchronized ([UIApplication class]) {
            if (!gOriginalClassResignImplementations) {
                gOriginalClassResignImplementations = [NSMapTable strongToStrongObjectsMapTable];
            }
            if ([gOriginalClassResignImplementations objectForKey:cls]) {
                continue;
            }
            [gOriginalClassResignImplementations setObject:[NSValue valueWithPointer:current] forKey:cls];
        }

        method_setImplementation(method, (IMP)ChatGPTShellGuardedResignFirstResponder);
        gSwizzledTextInputClassCount++;
        ChatGPTShellLog(@"installed custom text input resign guard class=%@", NSStringFromClass(cls));
    }

    free(classes);
}

static void ChatGPTShellLogKeyboardNotification(NSNotification* notification) {
    UIResponder* firstResponder = ChatGPTShellCurrentFirstResponder();
    ChatGPTShellLog(
        @"keyboard %@ firstResponder=%@ draft=%d elapsed=%.3f swizzledClasses=%lu",
        notification.name,
        firstResponder ? ChatGPTShellClassChain(firstResponder) : @"nil",
        firstResponder ? ChatGPTShellTextInputHasDraft(firstResponder) : NO,
        ChatGPTShellNow() - gLastUserInteractionTime,
        (unsigned long)gSwizzledTextInputClassCount
    );
}

static void ChatGPTShellObserveKeyboard(void) {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIKeyboardWillShowNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                        ChatGPTShellLogKeyboardNotification(notification);
                    }];
    [center addObserverForName:UIKeyboardWillHideNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                        ChatGPTShellLogKeyboardNotification(notification);
                    }];
    [center addObserverForName:UIKeyboardWillChangeFrameNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                        ChatGPTShellLogKeyboardNotification(notification);
                    }];
    [center addObserverForName:UITextInputCurrentInputModeDidChangeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                        ChatGPTShellLogKeyboardNotification(notification);
                    }];
}

static void ChatGPTShellInstallKeyboardGuardWithAttempts(NSUInteger attemptsRemaining) {
    ChatGPTShellSwizzleApplication();
    ChatGPTShellSwizzleResponder();
    ChatGPTShellSwizzleCustomTextInputClasses();

    if (attemptsRemaining == 0) {
        ChatGPTShellLog(@"keyboard guard install attempts finished swizzledClasses=%lu", (unsigned long)gSwizzledTextInputClassCount);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ChatGPTShellInstallKeyboardGuardWithAttempts(attemptsRemaining - 1);
    });
}

__attribute__((constructor)) static void ChatGPTShellKeyboardGuardConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ChatGPTShellLog(@"keyboard guard starting log=%@", ChatGPTShellLogPath());
        ChatGPTShellObserveKeyboard();
        ChatGPTShellInstallKeyboardGuardWithAttempts(20);
    });
}
