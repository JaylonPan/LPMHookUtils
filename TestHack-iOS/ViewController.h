//
//  ViewController.h
//  TestHack-iOS
//
//  Created by Jaylon on 2017/12/1.
//  Copyright © 2017年 Jaylon. All rights reserved.
//

#import <UIKit/UIKit.h>
#define STR_SEL(sel) NSStringFromSelector(@selector(sel))
typedef struct Test {
    int num;
    long age;
    char name[20];
}TheTest;
@interface ViewController : UIViewController


@end

