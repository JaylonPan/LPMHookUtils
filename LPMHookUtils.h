//
//  LPMHookUtils.h
//  TestHack-iOS
//
//  Created by Jaylon on 2017/12/4.
//  Copyright © 2017年 Jaylon. All rights reserved.
//

#import <Foundation/Foundation.h>


/**
 The hook callback which we can get arguments in a array.
 
 @param receiver The method's receiver which we hooked.
 @param arguments The method's argument array.
 */
typedef void(^LPMHookCallbackBlock)(id receiver, NSArray *arguments);
@interface LPMHookUtils : NSObject

/**
 Add hook to the method of class with block.

 @param sel The method which you want to hook.
 @param clazz The Class which the method of.
 @param block The hook block.
 @return The identifier of the hook which you will use when invoke method:
 + (void)removeHookWithIdentifier:(NSString *)identifier.
 */
+ (NSString *)addHookStartOfMethod:(SEL)sel ofClass:(Class )clazz withBlock:(id )block;
+ (NSString *)addHookReplaceMethod:(SEL)sel ofClass:(Class )clazz withBlock:(id )block;
+ (NSString *)addHookEndOfMethod:(SEL)sel ofClass:(Class )clazz withBlock:(id )block;



/**
 Add hook to the method of class with block which removed after it was invoked once.

 @param sel The method which you want to hook.
 @param clazz The Class which the method of.
 @param block The hook block.
 */
+ (void)addOnceHookStartOfMethod:(SEL)sel ofClass:(Class )clazz withBlock:(id)block;
+ (void)addOnceHookReplaceMethod:(SEL)sel ofClass:(Class )clazz withBlock:(id)block;
+ (void)addOnceHookEndOfMethod:(SEL)sel ofClass:(Class )clazz withBlock:(id)block;



/**
 Add hook to the method of class with LPMHookCallbackBlock.

 @param sel The method which you want to hook.
 @param clazz The Class which the method of.
 @param callback The hooked LPMHookCallbackBlock.
 @return The identifier of the hook which you will use when invoke method:
 + (void)removeHookWithIdentifier:(NSString *)identifier.
 */
+ (NSString *)addHookStartOfMethod:(SEL)sel
                           ofClass:(Class )clazz
                  withHookCallback:(LPMHookCallbackBlock)callback;
+ (NSString *)addHookReplaceMethod:(SEL)sel
                           ofClass:(Class)clazz
                  withHookCallback:(LPMHookCallbackBlock)callback;;
+ (NSString *)addHookEndOfMethod:(SEL)sel
                         ofClass:(Class)clazz
                withHookCallback:(LPMHookCallbackBlock)callback;



/**
 Remove hook which we added.

 @param sel The method selector.
 @param clazz The class we hooked.
 */
+ (void)removeHookWithMethod:(SEL)sel ofClass:(Class )clazz;

/**
 Remove hook which we added.

 @param identifier The identifier of the hook which you did added.
 */
+ (void)removeHookWithIdentifier:(NSString *)identifier;


/**
 Remove hook of the class.

 @param clazz The class we hooked.
 */
+ (void)removeAllHooksOfClass:(Class )clazz;


/**
 Remove all hooks which was using LPMHookUtils.
 */
+ (void)removeAllHooks;


/**
 Close the log from LPMHookUtils.

 @param close If close is YES ,we will not print log any more. The default value is NO.
 */
+ (void)closeLog:(BOOL)close;

@end
