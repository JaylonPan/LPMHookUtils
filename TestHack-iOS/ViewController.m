//
//  ViewController.m
//  TestHack-iOS
//
//  Created by Jaylon on 2017/12/1.
//  Copyright © 2017年 Jaylon. All rights reserved.
//

#import "ViewController.h"
#import <objc/message.h>
#import "LPMHookUtils.h"
#import "Test1ViewController.h"
@interface ViewController ()

@end

@implementation ViewController


- (instancetype)init {
    if (self = [super init]) {

    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    [LPMHookUtils addHookStartOfMethod:@selector(setIndex:test:) ofClass:[Test1ViewController class] withHookCallback:^(id receiver, NSArray *arguments) {
        NSLog(@"Before hooked setIndex:test:");
    }];
    
    [LPMHookUtils addHookEndOfMethod:@selector(setIndex:test:) ofClass:[Test1ViewController class] withHookCallback:^(id receiver, NSArray *arguments) {
        NSLog(@"After hooked setIndex:test:");
    }];
    [LPMHookUtils addOnceHookReplaceMethod:@selector(setIndex:test:) ofClass:[Test1ViewController class] withBlock:^(id receiver, TheTest index, NSString *test) {
        NSLog(@"Replace once hooked setIndex:test:");
    }];
    // Do any additional setup after loading the view, typically from a nib.
}

- (IBAction)clicked:(id)sender {
    NSDate *date = [NSDate date];
    Test1ViewController *controller = [[Test1ViewController alloc]init];
    NSTimeInterval time = [[NSDate date] timeIntervalSinceDate:date];
    NSLog(@"time:%f",time);
    TheTest test ;
    test.num = 1;
    test.age = 27;
    strcpy(test.name, "panjinlong");
    [controller setIndex:test test:@"5.789"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

+ (NSArray<NSString *> *)ignoreList {
    return @[STR_SEL(viewDidLoad),STR_SEL(didReceiveMemoryWarning)];
}

@end
