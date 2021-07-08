//
//  DCKVO.h
//  KVODemo
//
//  Created by chendichuan on 2021/7/6.
//

#import <Foundation/Foundation.h>
typedef void(^DCKVOObserverBlock)(NSDictionary * _Nonnull info);

NS_ASSUME_NONNULL_BEGIN


@interface NSObject (DCKVO)

/// 添加观察者
/// @param observer observer
/// @param keyPath keyPath
/// @param observerBlock observerBlock
- (void)dc_addObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
         observerBlock:(DCKVOObserverBlock)observerBlock;

@end

NS_ASSUME_NONNULL_END
