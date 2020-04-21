//
//  Hotloader.h
//  hemiprocne
//
//  Created by kaiwei Xu on 2020/4/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Hotloader : NSObject

+ (instancetype)shareInstance;

- (NSURL *)runloopURL;

@end

NS_ASSUME_NONNULL_END
