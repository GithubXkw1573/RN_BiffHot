//
//  HttpEngine.h
//  hemiprocne
//
//  Created by kaiwei Xu on 2020/4/17.
//  Copyright © 2020 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HttpEngineResponse : NSObject
@property (nonatomic, assign) NSInteger code;
@property (nonatomic, copy) NSString * _Nullable message;
@property (nonatomic, strong) id _Nullable data;
@end

typedef NS_ENUM(NSInteger, HttpMethod) {
  HttpMethodGet = 0,
  HttpMethodPost = 1,
};

typedef void (^HttpEngineResponseBlock)(BOOL succ, HttpEngineResponse * _Nonnull resp);

NS_ASSUME_NONNULL_BEGIN

@interface HttpEngine : NSObject

+ (instancetype)shareInstance;

+ (void)destroy;

- (void)requestUrl:(NSString *)path complete:(HttpEngineResponseBlock)block;
- (void)requestUrl:(NSString *)path paramters:(NSDictionary *)paramters complete:(HttpEngineResponseBlock)block;

- (void)downloadUrl:(NSString *)path saveToPath:(NSString *)savePath complete:(void(^)(BOOL, NSString *, NSString *))block;

@end

NS_ASSUME_NONNULL_END
