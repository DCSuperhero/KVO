//
//  DCKVO.m
//  KVODemo
//
//  Created by chendichuan on 2021/7/6.
//

#import "DCKVO.h"
#import <objc/runtime.h>
#import <objc/message.h>
#define DCKVOPREFIX @"DCKVOPREFIX_"

@interface NSObject (DCKVO)

@property (nonatomic, strong) NSMapTable<NSString *, NSHashTable *> *observerMap;

@end

@implementation NSObject (DCKVO)

- (void)dc_addObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
         observerBlock:(DCKVOObserverBlock)observerBlock {
    SEL setter = [self dc_setterForKeyPath:keyPath];
    // 1.keyPath校验
    if (![self respondsToSelector:setter]) return;
    // 2.动态生成当前KVO子类
    [self dc_createKVOSubClass];
    // 3.改写子类对应setter方法
    [self dc_addKeyPathSetter1:setter];
    // 4.存储observerBlock
    [self dc_addObserverBlock:observerBlock keyPath:keyPath];
}

- (BOOL)dc_isKVOClass {
    return [NSStringFromClass(self.class) containsString:DCKVOPREFIX];
}


/// keyPath生成对应的setter方法
/// @param keyPath keyPath
- (SEL)dc_setterForKeyPath:(NSString *)keyPath {
    if (keyPath.length <= 0) return nil;
    NSString *firstLetter = [[keyPath substringToIndex:1] uppercaseString];
    NSString *otherString = [keyPath substringFromIndex:1];
    NSString *setterName = [NSString stringWithFormat:@"set%@%@:", firstLetter, otherString];
    return NSSelectorFromString(setterName);
}

- (NSString *)dc_keyPathForSetter:(SEL)setter {
    if (!setter) return nil;
    NSString *setterName = NSStringFromSelector(setter);
    if ([setterName hasPrefix:@"set"] && [setterName hasSuffix:@":"]) {
        setterName = [setterName substringWithRange:NSMakeRange(3, setterName.length - 4)];
    }
    NSString *firstLetter = [[setterName substringToIndex:1] lowercaseString];
    NSString *otherString = [setterName substringFromIndex:1];
    NSString *keyPath = [NSString stringWithFormat:@"%@%@", firstLetter, otherString];
    return keyPath;
}

/// 当前类对象是否含有selector
/// @param selector selector
- (BOOL)dc_containSelector:(SEL)selector {
    unsigned int count = 0;
    Method *methodList = class_copyMethodList(self.class, &count);
    for (int i = 0; i < count; i++) {
        Method method = methodList[i];
        if (method_getName(method) == selector) {
            free(methodList);
            return YES;
        }
    }
    free(methodList);
    return NO;
}


/// 动态生成子类
- (void)dc_createKVOSubClass {
    if ([self dc_isKVOClass]) return;
    NSString *kvoClsName = [NSString stringWithFormat:@"%@%@", DCKVOPREFIX, NSStringFromClass(self.class)];
    // 生成KVO子类
    Class kvoCls = objc_allocateClassPair(self.class, kvoClsName.UTF8String, 0);
    objc_registerClassPair(kvoCls);
    // 修改当前对象isa指针指向kvo子类
    object_setClass(self, kvoCls);
}

- (void)dc_addKeyPathSetter:(SEL)setter {
    // 已存在setter
    if ([self dc_containSelector:setter]) return;
    Method method = class_getInstanceMethod(self.class, setter);
    class_replaceMethod(self.class, setter, (IMP)dc_kvosetter, method_getTypeEncoding(method));
}

- (SEL)aliasSelectorForSelector:(SEL)selector {
    return NSSelectorFromString([NSString stringWithFormat:@"%@%@", DCKVOPREFIX, NSStringFromSelector(selector)]);;
}

- (void)dc_addKeyPathSetter1:(SEL)setter {
    // 已存在setter
    if ([self dc_containSelector:setter]) return;
    Method method = class_getInstanceMethod(self.class, setter);
    // 保存setter原始实现
    SEL aliasSEL = [self aliasSelectorForSelector:setter];
    class_replaceMethod(self.class, aliasSEL, method_getImplementation(method), method_getTypeEncoding(method));
    // setter->forwardInvocation
    class_replaceMethod(self.class, setter, (IMP)_objc_msgForward, method_getTypeEncoding(method));
    SEL forwardSEL = @selector(forwardInvocation:);
    Method forwardMethod = class_getInstanceMethod(self.class, forwardSEL);
    SEL aliasForwardSEL = [self aliasSelectorForSelector:forwardSEL];
    // 保存forwardInvocation原始实现
    class_replaceMethod(self.class, aliasForwardSEL, method_getImplementation(forwardMethod), method_getTypeEncoding(forwardMethod));
    // forwardInvocation -> dc_forwardInvocation
    class_replaceMethod(self.class, forwardSEL, (IMP)dc_forwardInvocation, method_getTypeEncoding(forwardMethod));
}

- (void)dc_addObserverBlock:(DCKVOObserverBlock)observerBlock keyPath:(NSString *)keyPath {
    if (!observerBlock) return;
    NSHashTable *observersTable = [self.observerMap objectForKey:keyPath];
    if (!observersTable) {
        observersTable = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
        [self.observerMap setObject:observersTable forKey:keyPath];
    }
    [observersTable addObject:observerBlock];
}

/// 通过重写子类setter实现KVO
static void dc_kvosetter(id self, SEL _cmd, id value) {
    NSString *keyPath = [self dc_keyPathForSetter:_cmd];
    // 获取旧值
    id oldValue = [self valueForKeyPath:keyPath];
    
    // 获取super class
    struct objc_super superClass = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    // willChangeValueForKey
    [self willChangeValueForKey:keyPath];
    void (*superSetter)(void *, SEL, id) = (void *)objc_msgSendSuper;
    // 调用super的setter方法
    superSetter(&superClass, _cmd, value);
    // didChangeValueForKey
    [self didChangeValueForKey: keyPath];
    
    // 获取ObserverBlock并调用
    NSMapTable *observerMap = objc_getAssociatedObject(self, @selector(observerMap));
    NSHashTable *observersTable = [observerMap objectForKey:keyPath];
    [observersTable.allObjects enumerateObjectsUsingBlock:^(DCKVOObserverBlock  _Nonnull observerBlock, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMutableDictionary *observerInfo = [NSMutableDictionary dictionary];
        observerInfo[@"oldValue"] = oldValue;
        observerInfo[@"newValue"] = value;
        observerBlock([observerInfo copy]);
    }];
}

/// 通过forwardInvocation实现KVO
static void dc_forwardInvocation(NSObject *self, SEL _cmd, NSInvocation *anInvocation) {
    SEL selector = anInvocation.selector;
    NSString *keyPath = [self dc_keyPathForSetter:selector];
    
    SEL aliasSEL = [self aliasSelectorForSelector:anInvocation.selector];
    if (![self respondsToSelector:aliasSEL]) {
        // 不响应aliasSEL 转发回super forward
        SEL aliasForwardSEL = [self aliasSelectorForSelector:_cmd];
        if ([self respondsToSelector:aliasForwardSEL]) {
            ((void( *)(id, SEL, NSInvocation *))objc_msgSend)(self, aliasForwardSEL, anInvocation);
        }
    }
    
    anInvocation.selector = aliasSEL;
    [anInvocation invoke];

    // 获取ObserverBlock并调用
    NSMapTable *observerMap = objc_getAssociatedObject(self, @selector(observerMap));
    NSHashTable *observersTable = [observerMap objectForKey:keyPath];
    [observersTable.allObjects enumerateObjectsUsingBlock:^(DCKVOObserverBlock  _Nonnull observerBlock, NSUInteger idx, BOOL * _Nonnull stop) {
        // DEMO演示 应该读出每个参数的类型和值
        NSMutableDictionary *observerInfo = [NSMutableDictionary dictionary];
        NSNumber *age = NULL;
        [anInvocation getArgument:&age atIndex:2];
        observerInfo[@"newValue"] = age;
        observerBlock([observerInfo copy]);
    }];
}

- (NSMapTable<NSString *,NSHashTable *> *)observerMap {
    NSMapTable<NSString *,NSHashTable *> *map = objc_getAssociatedObject(self, _cmd);
    if (!map) {
        map = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory];
        self.observerMap = map;
    }
    return map;
}

- (void)setObserverMap:(NSMapTable<NSString *,NSHashTable *> *)observerMap {
    objc_setAssociatedObject(self, @selector(observerMap), observerMap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
