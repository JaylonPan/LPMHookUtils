//
//  LPMHookUtils.m
//  TestHack-iOS
//
//  Created by Jaylon on 2017/12/4.
//  Copyright © 2017年 Jaylon. All rights reserved.
//

#import "LPMHookUtils.h"
#import <objc/message.h>

#ifdef DEBUG
#define LPMLog(...) if(!g_closeLog) NSLog(__VA_ARGS__)
#else
#define LPMLog(...)
#endif
#define ReplaceHeaderName @"pjl_replace"
#define BeforeInvocationKey @"beforeInvocation"
#define ReplaceInvocationKey @"replaceInvocationKey"
#define AfterInvocationKey @"afterInvocationKey"
#define LPMError(errCode, desc) [NSError errorWithDomain:NSMachErrorDomain \
code:errCode userInfo:@{NSLocalizedDescriptionKey: desc}]
static BOOL g_closeLog;
typedef NS_ENUM(NSUInteger, LPMHookOption) {
    LPMHookOptionBefore,
    LPMHookOptionReplace,
    LPMHookOptionAfter,
};
// Block internals.
typedef NS_OPTIONS(int, LPMBlockFlags) {
    LPMBlockFlagsHasCopyDisposeHelpers = (1 << 25),
    LPMBlockFlagsHasSignature          = (1 << 30)
};
typedef struct _LPMBlock {
    __unused Class isa;
    LPMBlockFlags flags;
    __unused int reserved;
    void (__unused *invoke)(struct _LPMBlock *block, ...);
    struct {
        unsigned long int reserved;
        unsigned long int size;
        // requires LPMBlockFlagsHasCopyDisposeHelpers
        void (*copy)(void *dst, const void *src);
        void (*dispose)(const void *);
        // requires LPMBlockFlagsHasSignature
        const char *signature;
        const char *layout;
    } *descriptor;
    // imported variables
} *LPMBlockRef;


///////////////////////////////////////////////////////////////////////////////
#pragma mark - Class LPMHookIDInfo
//////////////////////////////////////////////////////////////////////////////
@interface LPMHookIDInfo : NSObject
@property Class clazz;
@property LPMHookOption option;
@property SEL selector;
@property NSUInteger index;
@property BOOL usingLPMHookCallback;
@property BOOL invokeOnce;
+ (instancetype)infoWithIdentifier:(NSString *)identifier;
@end

@implementation LPMHookIDInfo
+ (instancetype)infoWithIdentifier:(NSString *)identifier {
    LPMHookIDInfo *info = [[LPMHookIDInfo alloc] initWithIdentifier:identifier];
    return info;
}
- (instancetype)initWithIdentifier:(NSString *)identifier {
    if (self = [super init]) {
        NSArray *arr = [identifier componentsSeparatedByString:@"^"];
        if (arr.count >= 1) {
            self.clazz = NSClassFromString(arr[0]);
        }
        if (arr.count >= 2) {
            self.selector = NSSelectorFromString(arr[1]);
        }
        if (arr.count >= 3) {
            NSString *theKey = arr[2];
            if ([theKey isEqualToString:BeforeInvocationKey]) {
                self.option = LPMHookOptionBefore;
            }else if ([theKey isEqualToString:ReplaceInvocationKey]) {
                self.option = LPMHookOptionReplace;
            }else if ([theKey isEqualToString:AfterInvocationKey]) {
                self.option = LPMHookOptionAfter;
            }
        }
        if (arr.count >= 4) {
            self.usingLPMHookCallback = [arr[3] boolValue];
        }
        if (arr.count >= 5) {
            self.invokeOnce = [arr[4] boolValue];
        }
        if (arr.count >= 6) {
            self.index = [arr[5] integerValue];
        }
    }
    return self;
}
@end


///////////////////////////////////////////////////////////////////////////////
#pragma mark - Class LPMHookOperation
//////////////////////////////////////////////////////////////////////////////
@interface LPMHookOperation : NSObject
@property (nonatomic, readonly) SEL selector;
@property (nonatomic, readonly) Class clazz;
@property (nonatomic, readonly) BOOL hasBeforeInvocations;
@property (nonatomic, readonly) BOOL hasReplaceInvocations;
@property (nonatomic, readonly) BOOL hasAfterInvocations;
@property (nonatomic, readonly) BOOL hasInvocations;
@property (nonatomic, readonly) NSString *baseIdentifier;
@property (nonatomic, readonly) NSArray<NSInvocation *> *beforeInvocationList;
@property (nonatomic, readonly) NSArray<NSInvocation *> *replaceInvocationList;
@property (nonatomic, readonly) NSArray<NSInvocation *> *afterInvocationList;

+ (instancetype)operationWithSelector:(SEL)selector clazz:(Class)clazz;
- (NSString *)addInvocation:(NSInvocation *)invocation
                      block:(id)block
                     option:(LPMHookOption)option
          usingHookCallback:(BOOL)usingCallback
                 invokeOnce:(BOOL)invokeOnce;
- (void)removeInvocationWithIdentifier:(NSString *)identifier;
- (BOOL)invokeWithOriginalInvocation:(NSInvocation *)originalInvocation option:(LPMHookOption)option;
@end

@interface LPMHookOperation()
@property (nonatomic, strong) NSMutableDictionary<NSString * ,NSInvocation *> *beforeInvocationDict;
@property (nonatomic, strong) NSMutableDictionary<NSString * ,NSInvocation *> *replaceInvocationDict;
@property (nonatomic, strong) NSMutableDictionary<NSString * ,NSInvocation *> *afterInvocationDict;
@property (nonatomic, strong) NSMutableArray<NSString *> *needRemoveIDList;
@property (nonatomic, strong) NSMutableDictionary *blockDict;
@end

@implementation LPMHookOperation

+ (instancetype)operationWithSelector:(SEL)selector clazz:(Class)clazz {
    LPMHookOperation *op = [[LPMHookOperation alloc] initWithSelector:selector clazz:clazz];
    return op;
}

- (instancetype)initWithSelector:(SEL)selector clazz:(Class)clazz {
    if (self = [super init]) {
        _selector = selector;
        _clazz = clazz;
    }
    return self;
}

- (BOOL)invokeWithOriginalInvocation:(NSInvocation *)originalInvocation option:(LPMHookOption)option {
    NSDictionary *blockInvocationDict = nil;
    id obj = originalInvocation.target;
    switch (option) {
        case LPMHookOptionBefore:
            blockInvocationDict = self.beforeInvocationDict;
            break;
        case LPMHookOptionReplace:
            blockInvocationDict = self.replaceInvocationDict;
            break;
        case LPMHookOptionAfter:
            blockInvocationDict = self.afterInvocationDict;
            break;
        default:
            break;
    }
    for (NSString *identifier in blockInvocationDict.allKeys) {
        NSInvocation *blockInvocation = blockInvocationDict[identifier];
        NSUInteger numberOfArguments = blockInvocation.methodSignature.numberOfArguments;
        NSUInteger originalInvocationArgCount = originalInvocation.methodSignature.numberOfArguments;
        
        // Be extra paranoid. We already check that on hook registration.
        if (numberOfArguments > originalInvocationArgCount) {
            LPMLog(@"Block has too many arguments. Not calling %@", NSStringFromSelector(originalInvocation.selector));
            continue;
        }
        
        
        if (numberOfArguments > 1) {
            [blockInvocation setArgument:&obj atIndex:1];
        }
        
        LPMHookIDInfo *info = [LPMHookIDInfo infoWithIdentifier:identifier];
        if (info.invokeOnce) {
            if (identifier) {
                [self.needRemoveIDList addObject:identifier];
            }
        }
        void *argBuf = NULL;
        NSArray *argumentList = nil;
        if (info.usingLPMHookCallback) {
            if (originalInvocationArgCount > 2) {
                argumentList = [self invocationArguments:originalInvocation];
                [blockInvocation setArgument:&argumentList atIndex:2];
            }
        }else{
            
            for (NSUInteger idx = 2; idx < numberOfArguments; idx++) {
                const char *type = [originalInvocation.methodSignature getArgumentTypeAtIndex:idx];
                NSUInteger argSize;
                NSGetSizeAndAlignment(type, &argSize, NULL);
                
                if (!(argBuf = reallocf(argBuf, argSize))) {
                    LPMLog(@"Failed to allocate memory for block invocation.");
                    continue;
                }
                
                [originalInvocation getArgument:argBuf atIndex:idx];
                [blockInvocation setArgument:argBuf atIndex:idx];
            }
        }
        
        [blockInvocation invoke];
        
        if (argBuf != NULL) {
            free(argBuf);
        }
    }
    for (NSString *theID in self.needRemoveIDList) {
        [self removeInvocationWithIdentifier:theID];
    }
    [self.needRemoveIDList removeAllObjects];
    return YES;
}

- (NSString *)addInvocation:(NSInvocation *)invocation
                      block:(id)block
                     option:(LPMHookOption)option
          usingHookCallback:(BOOL)usingCallback
                 invokeOnce:(BOOL)invokeOnce {
    NSString *key = nil;
    switch (option) {
        case LPMHookOptionBefore:
            key = BeforeInvocationKey;
            break;
        case LPMHookOptionReplace:
            key = ReplaceInvocationKey;
            break;
        case LPMHookOptionAfter:
            key = AfterInvocationKey;
            break;
        default:
            break;
    }
    return [self addInvocation:invocation withKey:key block:block usingHookCallback:usingCallback invokeOnce:invokeOnce];
}

- (NSString *)addInvocation:(NSInvocation *)invocation
                    withKey:(NSString *)key
                      block:(id)block
          usingHookCallback:(BOOL)usingCallback
                 invokeOnce:(BOOL) invokeOnce {
    if (!invocation || !key) {
        return nil;
    }
    NSMutableDictionary *dic = nil;
    if ([key isEqualToString:BeforeInvocationKey]) {
        dic = self.beforeInvocationDict;
    }else if ([key isEqualToString:ReplaceInvocationKey]) {
        dic = self.replaceInvocationDict;
    }else if ([key isEqualToString:AfterInvocationKey]) {
        dic = self.afterInvocationDict;
    }
    NSInteger count = dic.count;
    NSString *identifier = [NSString stringWithFormat:@"%@^%@^%d^%d^%zd",self.baseIdentifier,key,usingCallback,invokeOnce,count];
    [dic setValue:invocation forKey:identifier];
    [self.blockDict setValue:[block copy] forKey:identifier];
    return identifier;
}

- (void)removeInvocationWithIdentifier:(NSString *)identifier {
    if (!identifier) {
        [self.beforeInvocationDict removeAllObjects];
        [self.replaceInvocationDict removeAllObjects];
        [self.afterInvocationDict removeAllObjects];
        [self.needRemoveIDList removeAllObjects];
        [self.blockDict removeAllObjects];
        return;
    }
    NSMutableDictionary *dic = nil;
    if ([identifier containsString:BeforeInvocationKey]) {
        dic = self.beforeInvocationDict;
    }else if ([identifier containsString:ReplaceInvocationKey]) {
        dic = self.replaceInvocationDict;
    }else if ([identifier containsString:AfterInvocationKey]) {
        dic = self.afterInvocationDict;
    }
    [dic removeObjectForKey:identifier];
    [self.blockDict removeObjectForKey:identifier];
}

- (NSMutableDictionary *)blockDict {
    if (!_blockDict) {
        _blockDict = [NSMutableDictionary dictionary];
    }
    return _blockDict;
}

- (NSMutableDictionary<NSString * ,NSInvocation *> *)beforeInvocationDict {
    if (!_beforeInvocationDict) {
        _beforeInvocationDict = [NSMutableDictionary dictionary];
    }
    return _beforeInvocationDict;
}

- (NSMutableDictionary<NSString * ,NSInvocation *> *)replaceInvocationDict {
    if (!_replaceInvocationDict) {
        _replaceInvocationDict = [NSMutableDictionary dictionary];
    }
    return _replaceInvocationDict;
}

- (NSMutableDictionary<NSString * ,NSInvocation *> *)afterInvocationDict {
    if (!_afterInvocationDict) {
        _afterInvocationDict = [NSMutableDictionary dictionary];
    }
    return _afterInvocationDict;
}

- (NSMutableArray<NSString *> *)needRemoveIDList {
    if (!_needRemoveIDList) {
        _needRemoveIDList = [NSMutableArray array];
    }
    return _needRemoveIDList;
}

- (NSArray<NSInvocation *> *)beforeInvocationList {
    return self.beforeInvocationDict.allValues;
}

- (NSArray<NSInvocation *> *)replaceInvocationList {
    return self.replaceInvocationDict.allValues;
}

- (NSArray<NSInvocation *> *)afterInvocationList {
    return self.afterInvocationDict.allValues;
}

- (BOOL)hasBeforeInvocations {
    return self.beforeInvocationDict.count ? YES : NO;
}

- (BOOL)hasReplaceInvocations {
    return self.replaceInvocationDict.count ? YES : NO;
}

- (BOOL)hasAfterInvocations {
    return self.afterInvocationDict.count ? YES : NO;
}

- (BOOL)hasInvocations {
    return (self.hasBeforeInvocations || self.hasReplaceInvocations || self.hasAfterInvocations);
}

- (NSString *)baseIdentifier {
    return [NSString stringWithFormat:@"%@^%@",NSStringFromClass(self.clazz),NSStringFromSelector(self.selector)];
}


- (id)invocation:(NSInvocation *)invocation argumentAtIndex:(NSUInteger)index {
    const char *argType = [invocation.methodSignature getArgumentTypeAtIndex:index];
    // Skip const type qualifier.
    if (argType[0] == _C_CONST) argType++;
    
#define WRAP_AND_RETURN(type) do { type val = 0;\
[invocation getArgument:&val atIndex:(NSInteger)index];\
return @(val); } while (0)
    if (strcmp(argType, @encode(id)) == 0 || strcmp(argType, @encode(Class)) == 0) {
        __autoreleasing id returnObj;
        [invocation getArgument:&returnObj atIndex:(NSInteger)index];
        return returnObj;
    } else if (strcmp(argType, @encode(SEL)) == 0) {
        SEL selector = 0;
        [invocation getArgument:&selector atIndex:(NSInteger)index];
        return NSStringFromSelector(selector);
    } else if (strcmp(argType, @encode(Class)) == 0) {
        __autoreleasing Class theClass = Nil;
        [invocation getArgument:&theClass atIndex:(NSInteger)index];
        return theClass;
        // Using this list will box the number with the appropriate constructor, instead of the generic NSValue.
    } else if (strcmp(argType, @encode(char)) == 0) {
        WRAP_AND_RETURN(char);
    } else if (strcmp(argType, @encode(int)) == 0) {
        WRAP_AND_RETURN(int);
    } else if (strcmp(argType, @encode(short)) == 0) {
        WRAP_AND_RETURN(short);
    } else if (strcmp(argType, @encode(long)) == 0) {
        WRAP_AND_RETURN(long);
    } else if (strcmp(argType, @encode(long long)) == 0) {
        WRAP_AND_RETURN(long long);
    } else if (strcmp(argType, @encode(unsigned char)) == 0) {
        WRAP_AND_RETURN(unsigned char);
    } else if (strcmp(argType, @encode(unsigned int)) == 0) {
        WRAP_AND_RETURN(unsigned int);
    } else if (strcmp(argType, @encode(unsigned short)) == 0) {
        WRAP_AND_RETURN(unsigned short);
    } else if (strcmp(argType, @encode(unsigned long)) == 0) {
        WRAP_AND_RETURN(unsigned long);
    } else if (strcmp(argType, @encode(unsigned long long)) == 0) {
        WRAP_AND_RETURN(unsigned long long);
    } else if (strcmp(argType, @encode(float)) == 0) {
        WRAP_AND_RETURN(float);
    } else if (strcmp(argType, @encode(double)) == 0) {
        WRAP_AND_RETURN(double);
    } else if (strcmp(argType, @encode(BOOL)) == 0) {
        WRAP_AND_RETURN(BOOL);
    } else if (strcmp(argType, @encode(bool)) == 0) {
        WRAP_AND_RETURN(BOOL);
    } else if (strcmp(argType, @encode(char *)) == 0) {
        WRAP_AND_RETURN(const char *);
    } else if (strcmp(argType, @encode(void (^)(void))) == 0) {
        __unsafe_unretained id block = nil;
        [invocation getArgument:&block atIndex:(NSInteger)index];
        return [block copy];
    } else {
        NSUInteger valueSize = 0;
        NSGetSizeAndAlignment(argType, &valueSize, NULL);
        
        unsigned char valueBytes[valueSize];
        [invocation getArgument:valueBytes atIndex:(NSInteger)index];
        
        return [NSValue valueWithBytes:valueBytes objCType:argType];
    }
    return nil;
#undef WRAP_AND_RETURN
}

- (NSArray *)invocationArguments:(NSInvocation *)invocation {
    NSMutableArray *argumentsArray = [NSMutableArray array];
    for (NSUInteger idx = 2; idx < invocation.methodSignature.numberOfArguments; idx++) {
        [argumentsArray addObject:[self invocation:invocation argumentAtIndex:idx] ?: NSNull.null];
    }
    return [argumentsArray copy];
}

@end


///////////////////////////////////////////////////////////////////////////////
#pragma mark - Class LPMHookUtils
//////////////////////////////////////////////////////////////////////////////

@implementation LPMHookUtils

+ (NSString *)addHookStartOfMethod:(SEL)sel
                           ofClass:(Class )clazz
                         withBlock:(id)block {
    return addHook(clazz, sel, block, LPMHookOptionBefore, NO, NO);
}

+ (NSString *)addHookReplaceMethod:(SEL)sel
                           ofClass:(Class )clazz
                         withBlock:(id )block {
    return addHook(clazz, sel, block, LPMHookOptionReplace, NO, NO);
}

+ (NSString *)addHookEndOfMethod:(SEL)sel
                         ofClass:(Class )clazz
                       withBlock:(id)block{
    return addHook(clazz, sel, block, LPMHookOptionAfter, NO, NO);
}

+ (NSString *)addHookStartOfMethod:(SEL)sel
                           ofClass:(Class)clazz
                  withHookCallback:(LPMHookCallbackBlock)callback {
    return addHook(clazz, sel, callback, LPMHookOptionBefore, YES, NO);
}

+ (NSString *)addHookReplaceMethod:(SEL)sel
                           ofClass:(Class)clazz
                  withHookCallback:(LPMHookCallbackBlock)callback {
    return addHook(clazz, sel, callback, LPMHookOptionReplace, YES, NO);
}

+ (NSString *)addHookEndOfMethod:(SEL)sel
                         ofClass:(Class)clazz
                withHookCallback:(LPMHookCallbackBlock)callback {
    return addHook(clazz, sel, callback, LPMHookOptionAfter, YES, NO);
}

+ (void)addOnceHookStartOfMethod:(SEL)sel
                         ofClass:(Class)clazz
                       withBlock:(id)block {
    addHook(clazz, sel, block, LPMHookOptionBefore, NO, YES);
}

+ (void)addOnceHookReplaceMethod:(SEL)sel
                         ofClass:(Class)clazz
                       withBlock:(id)block {
    addHook(clazz, sel, block, LPMHookOptionReplace, NO, YES);
}

+ (void)addOnceHookEndOfMethod:(SEL)sel
                       ofClass:(Class)clazz
                     withBlock:(id)block {
    addHook(clazz, sel, block, LPMHookOptionAfter, NO, YES);
}

+ (void)removeHookWithMethod:(SEL)sel
                     ofClass:(Class )clazz {
    removeHook(clazz, sel, nil);
}

+ (void)removeHookWithIdentifier:(NSString *)identifier {
    if (!identifier) {
        return;
    }
    LPMHookIDInfo *info = [LPMHookIDInfo infoWithIdentifier:identifier];
    removeHook(info.clazz, info.selector, identifier);
}

+ (void)removeAllHooksOfClass:(Class )clazz {
    [self removeHookWithMethod:nil ofClass:clazz];
}
+ (void)removeAllHooks {
    [self removeAllHooksOfClass:nil];
}

+ (void)closeLog:(BOOL)close {
    g_closeLog = close;
}

#pragma mark - C functions for the hook utils

static NSString *addHook(Class clazz, SEL selector, id block, LPMHookOption option, BOOL useHookCallback,BOOL invokeOnce) {
    
    NSInvocation *invocation = lpm_InvocationOfBlock(block);
    return addInvocation(clazz, selector, invocation,block, option, useHookCallback, invokeOnce);
}

static void removeHook(Class clazz, SEL selector, NSString *identifier) {
    removeInvocation(clazz, selector, identifier);
}

#pragma mark - Swizzle Class In Place

static void _lpm_modifySwizzledClasses(void (^block)(NSMutableSet *swizzledClasses)) {
    static NSMutableSet *swizzledClasses;
    static dispatch_queue_t swizzledClassesQueue;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        swizzledClasses = [NSMutableSet new];
        swizzledClassesQueue = dispatch_queue_create("swizzledClassesQueue", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_barrier_sync(swizzledClassesQueue, ^{
        if (block) {
            block(swizzledClasses);
        }
    });
}

static Class lpm_swizzleClassInPlace(Class clazz) {
    NSCParameterAssert(clazz);
    NSString *className = NSStringFromClass(clazz);
    
    _lpm_modifySwizzledClasses(^(NSMutableSet *swizzledClasses) {
        if (![swizzledClasses containsObject:className]) {
            lpm_swizzleForwardInvocation(clazz);
            [swizzledClasses addObject:className];
        }
    });
    return clazz;
}

static void lpm_undoSwizzleClassInPlace(Class clazz) {
    NSCParameterAssert(clazz);
    NSString *className = NSStringFromClass(clazz);
    
    _lpm_modifySwizzledClasses(^(NSMutableSet *swizzledClasses) {
        if ([swizzledClasses containsObject:className]) {
            lpm_undoSwizzleForwardInvocation(clazz);
            [swizzledClasses removeObject:className];
        }
    });
}

static NSString *const LPMForwardInvocationSelectorName = @"__lpm_forwardInvocation:";
static void lpm_swizzleForwardInvocation(Class clazz) {
    NSCParameterAssert(clazz);
    // If there is no method, replace will act like class_addMethod.
    IMP originalImplementation = class_replaceMethod(clazz, @selector(forwardInvocation:), (IMP)swizzledTargetInvocation, "v@:@");
    if (originalImplementation) {
        class_addMethod(clazz, NSSelectorFromString(LPMForwardInvocationSelectorName), originalImplementation, "v@:@");
    }
    LPMLog(@"LPMHook: %@ is now lpmHook aware.", NSStringFromClass(clazz));
}

static void lpm_undoSwizzleForwardInvocation(Class clazz) {
    NSCParameterAssert(clazz);
    Method originalMethod = class_getInstanceMethod(clazz, NSSelectorFromString(LPMForwardInvocationSelectorName));
    Method objectMethod = class_getInstanceMethod(NSObject.class, @selector(forwardInvocation:));
    // There is no class_removeMethod, so the best we can do is to retore the original implementation, or use a dummy.
    IMP originalImplementation = method_getImplementation(originalMethod ?: objectMethod);
    class_replaceMethod(clazz, @selector(forwardInvocation:), originalImplementation, "v@:@");
    
    LPMLog(@"LPMHook: %@ has been restored.", NSStringFromClass(clazz));
}

static void lpm_replaceForwardIMP(Class clazz, SEL selector) {
    NSCParameterAssert(selector);
    Method targetMethod = class_getInstanceMethod(clazz, selector);
    IMP targetMethodIMP = method_getImplementation(targetMethod);
    if (!lpm_isMsgForwardIMP(targetMethodIMP)) {
        // Make a method alias for the existing method implementation, it not already copied.
        const char *typeEncoding = method_getTypeEncoding(targetMethod);
        SEL replaceSelector = lpm_replaceSelector(selector);
        if (![clazz instancesRespondToSelector:replaceSelector]) {
            __unused BOOL success = class_addMethod(clazz, replaceSelector, method_getImplementation(targetMethod), typeEncoding);
            NSCAssert(success, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(replaceSelector), clazz);
        }
        
        // We use forwardInvocation to hook in.
        class_replaceMethod(clazz, selector, lpm_getMsgForwardIMP(clazz, selector), typeEncoding);
        LPMLog(@"LPMHook: Installed hook for -[%@ %@].", clazz, NSStringFromSelector(selector));
    }
}

static void lpm_undoReplaceForwardIMP(Class clazz, SEL selector) {
    
    // Check if the method is marked as forwarded and undo that.
    Method targetMethod = class_getInstanceMethod(clazz, selector);
    IMP targetMethodIMP = method_getImplementation(targetMethod);
    if (lpm_isMsgForwardIMP(targetMethodIMP)) {
        // Restore the original method implementation.
        const char *typeEncoding = method_getTypeEncoding(targetMethod);
        SEL replaceSelector = lpm_replaceSelector(selector);
        Method originalMethod = class_getInstanceMethod(clazz, replaceSelector);
        IMP originalIMP = method_getImplementation(originalMethod);
        NSCAssert(originalMethod, @"Original implementation for %@ not found %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(replaceSelector), clazz);
        
        class_replaceMethod(clazz, selector, originalIMP, typeEncoding);
        LPMLog(@"LPMHook: Removed hook for -[%@ %@].", clazz, NSStringFromSelector(selector));
    }
    
}

static SEL lpm_replaceSelector(SEL selector) {
    NSCParameterAssert(selector);
    return NSSelectorFromString([ReplaceHeaderName stringByAppendingFormat:@"_%@", NSStringFromSelector(selector)]);
}

static BOOL lpm_isMsgForwardIMP(IMP impl) {
    return impl == _objc_msgForward
#if !defined(__arm64__)
    || impl == (IMP)_objc_msgForward_stret
#endif
    ;
}

static IMP lpm_getMsgForwardIMP(Class clazz, SEL selector) {
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    
    Method method = class_getInstanceMethod(clazz, selector);
    const char *encoding = method_getTypeEncoding(method);
    BOOL methodReturnsStructValue = encoding[0] == _C_STRUCT_B;
    if (methodReturnsStructValue) {
        @try {
            NSUInteger valueSize = 0;
            NSGetSizeAndAlignment(encoding, &valueSize, NULL);
            
            if (valueSize == 1 || valueSize == 2 || valueSize == 4 || valueSize == 8) {
                methodReturnsStructValue = NO;
            }
        } @catch (__unused NSException *e) {}
    }
    if (methodReturnsStructValue) {
        msgForwardIMP = (IMP)_objc_msgForward_stret;
    }
#endif
    return msgForwardIMP;
}

static void getGlobalInvocationMap(void (^block)(NSMutableDictionary *globalInvocationMap)) {
    static dispatch_queue_t globalInvocationQueue = nil;
    static NSMutableDictionary *globalInvocationMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        globalInvocationQueue = dispatch_queue_create("globalInvocationQueue", DISPATCH_QUEUE_SERIAL);
        globalInvocationMap = [NSMutableDictionary dictionary];
    });
    dispatch_barrier_sync(globalInvocationQueue, ^{
        if (block) {
            block(globalInvocationMap);
        }
    });
}

static NSString *addInvocation( Class clazz, SEL selector, NSInvocation *invocation,id block,
                               LPMHookOption option ,BOOL useCallback, BOOL invokeOnce) {
    NSString *key = NSStringFromClass(clazz);
    NSString *subKey = NSStringFromSelector(selector);
    if (!key || !subKey) {
        return nil;
    }
    __block NSString *identifier = nil;
    getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
        lpm_swizzleClassInPlace(clazz);
        lpm_replaceForwardIMP(clazz, selector);
        NSMutableDictionary *dic = [globalInvocationMap valueForKey:key];
        if (!dic) {
            dic = [NSMutableDictionary dictionary];
            [globalInvocationMap setValue:dic forKey:key];
        }
        LPMHookOperation *op = dic[subKey];
        if (!op) {
            op = [LPMHookOperation operationWithSelector:selector clazz:clazz];
            [dic setValue:op forKey:subKey];
        }
        identifier = [op addInvocation:invocation
                                 block:block
                                option:option
                     usingHookCallback:useCallback
                            invokeOnce:invokeOnce];
    });
    if (invokeOnce) {
    }
    return identifier;
}

static void removeInvocation( Class clazz,SEL selector, NSString *identifier) {
    NSString *key = NSStringFromClass(clazz);
    NSString *subKey = NSStringFromSelector(selector);
    
    if (!clazz) {
        __block NSMutableDictionary *theGlobalInvocationMap = nil;
        getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
            theGlobalInvocationMap = globalInvocationMap;
        });
        for (NSString *theKey in theGlobalInvocationMap.allKeys) {
            Class theClazz = NSClassFromString(theKey);
            removeInvocation(theClazz, nil, nil);
        }
        getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
            [globalInvocationMap removeAllObjects];
        });
        return;
    }
    __block NSMutableDictionary *dic = nil;
    getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
        dic = [globalInvocationMap valueForKey:key];
    });
    
    if (!dic) {
        return;
    }
    if (!selector) {
        for (NSString *theSubKey in dic.allKeys) {
            SEL theSelector = NSSelectorFromString(theSubKey);
            removeInvocation(clazz, theSelector, nil);
        }
        getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
            [globalInvocationMap removeObjectForKey:key];
            lpm_undoSwizzleClassInPlace(clazz);
        });
        return;
    }
    
    getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
        
        LPMHookOperation *op = dic[subKey];
        if (!op) {
            return;
        }
        [op removeInvocationWithIdentifier:identifier];
        if (!op.hasInvocations) {
            [dic removeObjectForKey:subKey];
            lpm_undoReplaceForwardIMP(clazz, selector);
        }
    });
    if (!dic.count){
        removeInvocation(clazz, nil, nil);
    }
}

static LPMHookOperation *getHookOperation( Class clazz, SEL selector) {
    NSString *key = NSStringFromClass(clazz);
    NSString *subKey = NSStringFromSelector(selector);
    if (!key || !subKey) {
        return nil;
    }
    __block NSMutableDictionary *dic = nil;
    getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
        dic = [globalInvocationMap valueForKey:key];
    });
    if (!dic) {
        return nil;
    }
    __block LPMHookOperation *op = nil;
    getGlobalInvocationMap(^(NSMutableDictionary *globalInvocationMap) {
        op = dic[subKey];
    });
    if (!op) {
        return nil;
    }
    return op;
}

#pragma mark Utils for block

static NSInvocation *lpm_InvocationOfBlock(id block) {
    NSMethodSignature *blockSignature = lpm_blockMethodSignature(block, nil);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:blockSignature];
    invocation.target = block;
    return invocation;
}
static NSMethodSignature *lpm_blockMethodSignature(id block, NSError **error) {
    LPMBlockRef layout = (__bridge void *)block;
    if (!(layout->flags & LPMBlockFlagsHasSignature)) {
        NSString *description = [NSString stringWithFormat:@"The block %@ doesn't contain a type signature.", block];
        LPMLog(@"%@",description);
        if (error) {
            *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: description}];
            LPMError(-1, description);
        }
        return nil;
    }
    void *desc = layout->descriptor;
    desc += 2 * sizeof(unsigned long int);
    if (layout->flags & LPMBlockFlagsHasCopyDisposeHelpers) {
        desc += 2 * sizeof(void *);
    }
    if (!desc) {
        NSString *description = [NSString stringWithFormat:@"The block %@ doesn't has a type signature.", block];
        LPMError(-1, description);
        return nil;
    }
    const char *signature = (*(const char **)desc);
    return [NSMethodSignature signatureWithObjCTypes:signature];
}

static __unused BOOL lpm_isCompatibleBlockSignature(NSMethodSignature *blockSignature, id object, SEL selector, NSError **error) {
    NSCParameterAssert(blockSignature);
    NSCParameterAssert(object);
    NSCParameterAssert(selector);
    
    BOOL signaturesMatch = YES;
    NSMethodSignature *methodSignature = [[object class] instanceMethodSignatureForSelector:selector];
    if (blockSignature.numberOfArguments > methodSignature.numberOfArguments) {
        signaturesMatch = NO;
    }else {
        if (blockSignature.numberOfArguments > 1) {
            const char *blockType = [blockSignature getArgumentTypeAtIndex:1];
            if (blockType[0] != '@') {
                signaturesMatch = NO;
            }
        }
        
        if (signaturesMatch) {
            for (NSUInteger idx = 2; idx < blockSignature.numberOfArguments; idx++) {
                const char *methodType = [methodSignature getArgumentTypeAtIndex:idx];
                const char *blockType = [blockSignature getArgumentTypeAtIndex:idx];
                // Only compare parameter, not the optional type data.
                if (!methodType || !blockType || methodType[0] != blockType[0]) {
                    signaturesMatch = NO; break;
                }
            }
        }
    }
    
    if (!signaturesMatch) {
        NSString *description = [NSString stringWithFormat:@"Block signature %@ doesn't match %@.", blockSignature, methodSignature];
        LPMLog(@"%@",description);
        if (error) {
            *error = [NSError errorWithDomain:description code:-1 userInfo:nil];
        }
        return NO;
    }
    return YES;
}

#pragma mark swizzledTargetInvocation

static void swizzledTargetInvocation(NSObject *self, SEL selector, NSInvocation *invocation) {
    NSCParameterAssert(self);
    NSCParameterAssert(invocation);
    SEL originalSelector = invocation.selector;
    SEL replaceSelector = lpm_replaceSelector(invocation.selector);
    LPMHookOperation *op = getHookOperation([invocation.target class], invocation.selector);
    invocation.selector = replaceSelector;
    
    // Before blocks.
    [op invokeWithOriginalInvocation:invocation option:LPMHookOptionBefore];
    
    // Replace blocks.
    BOOL respondsToReplace = YES;
    if (op.hasReplaceInvocations) {
        [op invokeWithOriginalInvocation:invocation option:LPMHookOptionReplace];
    }else {
        Class clazz = object_getClass(invocation.target);
        do {
            if ((respondsToReplace = [clazz instancesRespondToSelector:replaceSelector])) {
                [invocation invoke];
                break;
            }
        }while (!respondsToReplace && (clazz = class_getSuperclass(clazz)));
    }
    
    // After hooks.
    [op invokeWithOriginalInvocation:invocation option:LPMHookOptionAfter];
    if (!op.hasInvocations) {
        removeInvocation([invocation.target class], originalSelector, nil);
    }
    // If no hooks are installed, call original implementation (usually to throw an exception)
    if (!respondsToReplace) {
        invocation.selector = originalSelector;
        SEL originalForwardInvocationSEL = NSSelectorFromString(LPMForwardInvocationSelectorName);
        if ([self respondsToSelector:originalForwardInvocationSEL]) {
            ((void( *)(id, SEL, NSInvocation *))objc_msgSend)(self, originalForwardInvocationSEL, invocation);
        }else {
            [self doesNotRecognizeSelector:invocation.selector];
        }
    }
}


@end





