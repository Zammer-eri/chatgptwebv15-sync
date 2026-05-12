//
//  JITEnabler.m
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

#import "JITEnabler.h"
#import "JITErrors.h"
#import "TSRoot.h"
#import "TSUtils.h"

@implementation JITEnabler

+ (JITEnabler *)shared {
    static JITEnabler *sharedEnabler = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEnabler = [[self alloc] init];
    });
    return sharedEnabler;
}

- (instancetype)init {
    return [super init];
}

- (BOOL)enableJITForPID:(int32_t)pid hasTXM26:(BOOL)hasTXM26 error:(NSError **)error {
    (void)hasTXM26;
    if (!getEntitlementValue(@"com.apple.private.security.no-sandbox")) {
        if (error) *error = MakeError(TSPtraceHelperAttachFailed);
        return NO;
    }

    NSString *helperPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ptrace_jit"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
        if (error) *error = MakeError(TSPtraceHelperMissing);
        return NO;
    }

    int result = spawnRoot(helperPath, @[[NSString stringWithFormat:@"%d", pid]]);
    if (result >= 128) {
        if (error) *error = MakeError(TSPtraceHelperTerminated);
        return NO;
    }

    if (result != 0) {
        if (error) *error = MakeError(TSPtraceHelperAttachFailed);
        return NO;
    }

    return YES;
}

- (void)detachAllJITSessions {
    // TrollStore ptrace JIT attaches and exits; there is no persistent session to detach.
}

@end
