//
//  Hotloader.m
//  hemiprocne
//
//  Created by kaiwei Xu on 2020/4/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

#import "Hotloader.h"
#import "HttpEngine.h"
#import <ZipArchive/ZipArchive.h>

#define kAppHotVersion @"AppHotVersion"
#define kDocumentDir [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
#define kPatchesDir [kDocumentDir stringByAppendingPathComponent:@"patches"]
#define kBaseURL @"http://127.0.0.1"
#define kZipPackageName @"bundle"

@interface Hotloader ()
@property (nonatomic, copy, readonly) NSString *hotVersion;
@property (nonatomic, copy, readonly) NSString *currHotZipPath;
@property (nonatomic, copy) NSURL *bundleURL;
@end

@implementation Hotloader

static Hotloader *sharedInstance = nil;
static dispatch_once_t onceToken;

+ (instancetype)shareInstance {
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Hotloader alloc] init];
    });
    return sharedInstance;
}

- (NSURL *)runloopURL {
  self.bundleURL = nil;
  
  //开始请求...
  [self loadResourceURL];
  
  //当前时间，主线程
  NSDate *early = [NSDate date];
  //下面循环的目的：阻塞UI主线程
  //循环条件：1.bundleURL为空；2.并且循环时间不能超过3s
  while (!_bundleURL) {
      if ([[NSDate date] timeIntervalSinceDate:early] < 3) {
          //这里睡眠0.2秒，是为了防止while循环频率太快
          [NSThread sleepForTimeInterval:0.2];
          DLog(@"runloop end.");
      }else{
          break;
      }
  }
  
  if (!_bundleURL) {
    DLog(@"等待资源超时，使用现有的");
    _bundleURL = [self loadCurrResource];
  }
  
  return _bundleURL;
}

- (void)loadResourceURL {
  //1.检查是否有新的补丁
  NSString *url = [NSString stringWithFormat:@"%@/rn_hot/checkPatch.php?appVersion=%@", kBaseURL, self.hotVersion];
  [[HttpEngine shareInstance] requestUrl:url complete:^(BOOL succ, HttpEngineResponse * _Nonnull resp) {
    if (succ) {
      NSDictionary *patchDic = resp.data;
      DLog(@"%@", patchDic);
      if (![patchDic isKindOfClass:[NSDictionary class]]) {
        DLog(@"没有新的补丁，使用现有的");
        self->_bundleURL = [self loadCurrResource];
        return ;
      }
      NSString *patchUrl = [patchDic objectForKey:@"patchUrl"];
      NSString *newVersion = [patchDic objectForKey:@"newVersion"];
      if (patchUrl && [patchUrl isKindOfClass:[NSString class]] && patchUrl.length > 0) {
        //2.如果没有补丁目录，则创建
        NSError *err = nil;
        [self createDirIfNotExist:kPatchesDir error:&err];
        if (err) {
          DLog(@"创建补丁目录失败，使用现有的");
          self->_bundleURL = [self loadCurrResource];
          return ;
        }
        //3.下载补丁文件
        [[HttpEngine shareInstance] downloadUrl:patchUrl saveToPath:kPatchesDir complete:^(BOOL succ, NSString * _Nonnull filePath, NSString * _Nonnull error) {
          if (succ) {
            DLog(@"下载保存到地址：%@",filePath);
            //4.补丁合并现有zip生成newzip
            NSString *newZipPath = [self bspatch:filePath newVersion:newVersion];
            if (newZipPath.length) {
              //5.解压
              [SSZipArchive unzipFileAtPath:newZipPath toDestination:kDocumentDir overwrite:YES password:@"" progressHandler:nil completionHandler:^(NSString * _Nonnull path, BOOL succeeded, NSError * _Nullable error) {
                if (succeeded && !error) {
                  //6.升级成功，更新版本号
                  DLog(@"升级成功，更新版本号");
                  [NSUserDefaults.standardUserDefaults setObject:newVersion forKey:kAppHotVersion];
                  [NSUserDefaults.standardUserDefaults synchronize];
                  //7.继续检查有无新的版本更新
                  [self loadResourceURL];
                }else {
                  DLog(@"解压失败，使用现有的");
                  self->_bundleURL = [self loadCurrResource];
                }
              }];
            }else {
              DLog(@"合成补丁失败，使用现有的");
              self->_bundleURL = [self loadCurrResource];
            }
          }else {
            DLog(@"下载补丁失败，使用现有的");
            self->_bundleURL = [self loadCurrResource];
          }
        }];
      }else {
        DLog(@"没有新的补丁，使用现有的");
        self->_bundleURL = [self loadCurrResource];
      }
    }else {
      DLog(@"checkPatch接口失败，使用现有的");
      self->_bundleURL = [self loadCurrResource];
    }
  }];
}

- (NSString *)bspatch:(NSString *)patchPath newVersion:(NSString *)newVersion {
  const char *argv[4];
  argv[0] = "bspatch";
  // oldPath
  NSString *oldPath = self.currHotZipPath;
  if (!oldPath) {
    return nil;
  }
  argv[1] = [oldPath UTF8String];
  // newPath
  argv[2] = [[self newZipPath:newVersion] UTF8String];
  // patchPath
  argv[3] = [patchPath UTF8String];
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Wincompatible-pointer-types-discards-qualifiers"
  int result = BsdiffUntils_bspatch(4, argv);
  #pragma clang diagnostic pop
  NSString *newZipPath = [NSString stringWithFormat:@"%s", argv[2]];
  if (result == 0 && [NSFileManager.defaultManager fileExistsAtPath:newZipPath]) {
    //success
    return newZipPath;
  }else {
    return nil;
  }
}

- (void)createDirIfNotExist:(NSString *)dir error:(NSError **)error {
  BOOL exsit  = [NSFileManager.defaultManager fileExistsAtPath:dir];
  if (!exsit) {
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:error];
  }
}


- (NSString *)hotVersion {
  if ([NSUserDefaults.standardUserDefaults stringForKey:kAppHotVersion]) {
    NSString *version = [NSUserDefaults.standardUserDefaults stringForKey:kAppHotVersion];
    return version;
  }else {
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *app_Version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    return app_Version;
  }
}

- (NSString *)currHotZipPath {
  NSString *zipName = [NSString stringWithFormat:@"hot_V%@.zip", self.hotVersion];
  NSString *zipPath = [kDocumentDir stringByAppendingPathComponent:zipName];
  if ([NSFileManager.defaultManager fileExistsAtPath:zipPath]) {
    return zipPath;
  }else {
    //bundle读取
    zipName = [zipName stringByReplacingOccurrencesOfString:@".zip" withString:@""];
    NSString *zipBoundPath = [[NSBundle mainBundle] pathForResource:zipName ofType:@"zip"];
    if ([NSFileManager.defaultManager fileExistsAtPath:zipBoundPath]) {
      return zipBoundPath;
    }else {
      DLog(@"本地bundle不存在名为%@.zip的文件", zipName);
      return nil;
    }
  }
}

- (NSString *)newZipPath:(NSString *)version {
  NSString *zipName = [NSString stringWithFormat:@"hot_V%@.zip", version];
  NSString *zipPath = [kDocumentDir stringByAppendingPathComponent:zipName];
  return zipPath;
}

- (NSURL *)loadCurrResource {
  NSFileManager *manager = [NSFileManager defaultManager];
  NSString *jsbundle = [NSString stringWithFormat:@"%@/index.jsbundle", kZipPackageName];
  NSString *filePath = [kDocumentDir stringByAppendingPathComponent:jsbundle];
  if ([manager fileExistsAtPath:filePath]) {
    NSURL *url = [[manager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *urlPath = [url URLByAppendingPathComponent: jsbundle];
    return urlPath;
  }else {
    return [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"jsbundle"];
  }
}

@end
