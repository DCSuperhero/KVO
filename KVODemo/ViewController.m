//
//  ViewController.m
//  KVODemo
//
//  Created by chendichuan on 2021/7/6.
//

#import "ViewController.h"
#import "DCPerson.h"
#import "DCKVO.h"
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    DCPerson *p = [[DCPerson alloc] init];
    [p dc_addObserver:self forKeyPath:@"age" observerBlock:^(NSDictionary * _Nonnull info) {
        NSLog(@"age 1 %@", info);
    }];
    [p dc_addObserver:self forKeyPath:@"age" observerBlock:^(NSDictionary * _Nonnull info) {
        NSLog(@"age 2 %@", info);
    }];
    p.age = @(20);
    p.age = @(30);
    NSLog(@"%@", p.age);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end
