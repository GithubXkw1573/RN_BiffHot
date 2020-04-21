//
//  HttpEngine.m
//  hemiprocne
//
//  Created by kaiwei Xu on 2020/4/17.
//  Copyright © 2020 Facebook. All rights reserved.
//

#import "HttpEngine.h"

@implementation HttpEngineResponse

@end

@interface HttpEngine ()
@property (nonatomic, strong) NSURLSession *globalSession;
@end

@implementation HttpEngine

static HttpEngine *sharedInstance = nil;
static dispatch_once_t onceToken;

+ (instancetype)shareInstance {
    dispatch_once(&onceToken, ^{
        sharedInstance = [[HttpEngine alloc] init];
    });
    return sharedInstance;
}

//单例销毁
+ (void)destroy {
    onceToken = 0;
    sharedInstance = nil;
}

- (NSURLSessionConfiguration *)defaultSessionConfiguration {
  NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
  config.timeoutIntervalForRequest = 15;
  return config;
}

- (instancetype)init {
    if (self = [super init]) {
      self.globalSession = [NSURLSession sessionWithConfiguration:[self defaultSessionConfiguration]];
    }
    return self;
}

- (void)requestUrl:(NSString *)path complete:(HttpEngineResponseBlock)block {
  [self requestUrl:path method:HttpMethodGet paramters:nil complete:block];
}

- (void)requestUrl:(NSString *)path paramters:(NSDictionary *)paramters complete:(HttpEngineResponseBlock)block {
  [self requestUrl:path method:HttpMethodPost paramters:paramters complete:block];
}
                              
- (void)requestUrl:(NSString *)path method:(HttpMethod)method paramters:(NSDictionary *)paramters complete:(HttpEngineResponseBlock)block {
  HttpEngineResponse *resp = [[HttpEngineResponse alloc] init];
  NSURL *URL = [NSURL URLWithString:path];
  if (URL == nil) {
    resp.code = 300;
    resp.message = @"url string is not valid url!";
    if (block) {
      block(NO, resp);
    }
    return;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
  if (method == HttpMethodPost) {
    [request setHTTPMethod:@"POST"];
    if (paramters && [paramters isKindOfClass:[NSDictionary class]]) {
      NSError *error = nil;
      NSData *body = [NSJSONSerialization dataWithJSONObject:paramters options:NSJSONWritingPrettyPrinted error:&error];
      if (error) {
        resp.code = 300;
        resp.message = @"parameters can not serialization, please check paramters!";
        if (block) {
          block(NO, resp);
        }
        return;
      }
      [request setHTTPBody:body];
    }
  }else {
    [request setHTTPMethod:@"GET"];
  }
//  request setValue: forHTTPHeaderField:
  
  NSURLSessionTask *task = [self.globalSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (error) {
      resp.code = 500;
      resp.message = error.localizedDescription;
      if (block) {
        block(NO, resp);
      }
      return;
    }
    NSError *myerror = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&myerror];
    if (myerror) {
      NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      resp.code = 501;
      resp.message = @"response data serialization failed!";
      resp.data = jsonStr;
      if (block) {
        block(NO, resp);
      }
      return;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
      resp.code = 502;
      resp.message = @"response data format is not json object!";
      if (block) {
        block(NO, resp);
      }
      return;
    }
    resp.code = [[json objectForKey:@"code"] integerValue];
    resp.message = [NSString stringWithFormat:@"%@", [json objectForKey:@"message"]];
    resp.data = [json objectForKey:@"data"];
    if (block) {
      block(YES, resp);
    }
  }];
  [task resume];
}

- (void)downloadUrl:(NSString *)path saveToPath:(NSString *)savePath complete:(void(^)(BOOL, NSString *, NSString *))block {
  NSURL *URL = [NSURL URLWithString:path];
  if (URL == nil) {
    if (block) {
      block(NO, nil, @"url string is not valid url!");
    }
    return;
  }
  NSURLSessionDownloadTask *task = [self.globalSession downloadTaskWithURL:URL completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (error) {
      if (block) {
        block(NO, nil , error.localizedDescription);
      }
      return;
    }
    if (location == nil) {
      if (block) {
        block(NO, nil ,@"download to loaction file is empty!");
      }
      return;
    }
    NSString *fileName = response.suggestedFilename;
    if (fileName == nil) {
      fileName = location.lastPathComponent;
    }
    NSString *dstPath = [savePath stringByAppendingPathComponent:fileName];
    //删除之前的缓存
    if ([NSFileManager.defaultManager fileExistsAtPath:dstPath]) {
      [NSFileManager.defaultManager removeItemAtPath:dstPath error:nil];
    }
    //move file
    NSError *myerr = nil;
    [NSFileManager.defaultManager moveItemAtPath:location.path toPath:dstPath error:&myerr];
    if (myerr.domain == NSCocoaErrorDomain && myerr.code == 516) {
      //文件已经存在，说明是重复下载，可认为是正确的
      if (block) {
        block(YES, dstPath, myerr.localizedDescription);
      }
    }else {
      if (block) {
        block(myerr == nil, dstPath, myerr.localizedDescription);
      }
    }
  }];
  [task resume];
}

@end
