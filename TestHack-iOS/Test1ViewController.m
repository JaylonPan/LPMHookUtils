//
//  Test1ViewController.m
//  TestHack-iOS
//
//  Created by Jaylon on 2017/12/1.
//  Copyright © 2017年 Jaylon. All rights reserved.
//

#import "Test1ViewController.h"
#import "LPMHookUtils.h"


@interface Test1ViewController ()

@end

@implementation Test1ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setIndex:(TheTest )index  test:(NSString *)test{
    NSLog(@"%s",__func__);
//    NSLog(@"%@",[NSString stringWithFormat:@"index: %d,test:%@",index,test]);
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
