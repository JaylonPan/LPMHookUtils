# LPMHookUtils
Hook tools for Objective-C
# 使用

```
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
```
# 关闭Log

```
[LPMHookUtils closeLog:YES];
```

