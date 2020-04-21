####前言
关于ReactNative热更新，我首先是从网上对比了几个常见方案，然后从中选择较合适的方案实现。RN热更新分为**全量热更新和差量热更新**。全量的好处是实现逻辑相比差量而言较轻松一些，弊端是全量前端代码量如果很大的话，网络下载耗时较长，就影响了APP的启动体验了。
而差量热更新也大致分为2种思路：

- 1.将jsbundle 分离成通用部分和业务部分，每次热更新主要是业务部分脚本下发，然后和通用部分脚本合并。
- 2.利用比对工具biff将老版本和新版本比对出一个差异部分（我们称之为patch"补丁"），客户端每次下载补丁包，然后和老的部分合并出新的完整脚本。

鉴于差量更新第一种思路，业务脚本后续版本其实也存在大量重复的脚本，每次下载全量的业务脚本其实不是彻底的差量更新方案，而且资源文件更新也未能体现。所以，我最终采用了**第二种差分方案**实现。


####可行性探究
1.biff差分方案最核心的要借助第三方开源的biff。由于合并部分要在客户端上完成，所以我预先下载了bsdiff-4.3和bzip2的开源代码，由于是C语言实现，我们要在iOS平台编译，直接拷贝到项目中，由于多处方法名main同名而编译报错，所以，我选择了将该库c实现打包成.a静态库。（我把这个静态库放在本文末链接里，有需要的同学可自取）
然后将打包好的静态库导入到项目中（头文件bspatch.h别忘了），然后在项目的pch文件import bspatch.h即可
使用代码：

```
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
```

######2.关于资源文件

我一开始担心资源文件（比如图片）会找不到路径，因为我们更新的新的zip包所有资源文件由于不是在assets目录下，会担心RNImage无法找到，实际上，我多虑了，因为我们指定了index.jsbundle的path给RN后，RNImage**图片查找逻辑先是根据jsbundle的所在目录下遍历资源文件**，如果找不到，最后才取bundle的Assets找资源文件。而我们的资源文件总是和jsbundle打包在一起的，所以，**code和资源文件都可以热更新**。

![RN更新包解压后的目录结构](https://upload-images.jianshu.io/upload_images/1413134-c8b05e61736bde20.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

####关于版本管理
约定：
- 1.所有的完整的RN版本包命名规则：**hot_V[版本号].zip**
例如：hot_V1.0.0.zip
- 2.所有的补丁包命名规则：**hot_V[老版本号]_V[新版本号].patched**
例如：hot_V1.0.0_V1.0.1.patched 
表示：1.0.1版本和1.0.0版本差异部分产生的补丁包。

![版本推进演示图稿](https://upload-images.jianshu.io/upload_images/1413134-7d82936b8ca0fab4.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- **3.不做跨原生版本的补丁**
为啥不做跨原生版本的补丁呢？
因为考虑到原生版本更新的原生组件的API，很可能v2.0.1版本的脚本调用了只仅限于v2.0.0原生版本才有的原生组件，那么如果v1.0.3版本跨native版本更新到了v2.0.1的脚本，导致调用的native 组件api找不到方法而报错！

- 4.**每次原生版本更新的颗粒度精确到版本数组的第二位，第3位留给热更新**
我们的版本号预定格式： **x_y_z** 3位数字
x:代表整个APP大的功能升级或者重构
y:App 原生版本升级（需要市场审核发布）
z:补丁包升级

x、y版本升级均需要native版本升级，z标识补丁包升级，不需要重新发布APP市场审核，即热更新。

####逻辑流程图
![流程手稿](https://upload-images.jianshu.io/upload_images/1413134-e52342a5712aa95d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

####核心逻辑代码

```
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
```

最后在你的宿主RN工程中调用即可：
![宿主工程调用](https://upload-images.jianshu.io/upload_images/1413134-889421173cd0ced7.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**值得说明的：**

1.上面代码流程中最后第7步，继续递归调用了方法本身。
我的考虑是，虽然本次版本刚升级了，一般来说肯定就是最新的版本了，可以直接用本次zip解压的脚本启动APP了。但是当迭代了多个版本后，会出现这样的场景：

v1.0.0_v1.0.1.patch

v1.0.1_v1.0.2.patch

v1.0.2_v1.0.3.patch

...

假设服务器已经下发了3个补丁包了，但是，我们的用户可能很久没有打开过APP，很可能他的补丁版本还停留在初始的v1.0.0或者v1.0.1, 对于这两个版本的用户，升级一次版本后的版本相应的为1.0.1和v1.0.2, 而最新的版本是v1.0.3,  也就是说只有上次停留在v1.0.2的版本只需要一次升级到最新的版本，而其他版本需要多次升级到最新版本。所以这里采用**递归升级策略**。

2.每次APP 原生版本发布（有别于补丁包发布），**客户端需要手动保存一份和app原生版本相同的zip格式在项目中（即bundle中）**，这是因为，第一个补丁x.x.0_x.x.1.patch包要合并的初始zip必须存在。

####关于服务端部署
1.需要编写个服务端脚本，用于判断是否存在最新的可用补丁包。需要一个入参：当前版本号。
逻辑是遍历服务端存放补丁的列表文件目录，根据存放的补丁文件名称解析出老版本号-新版本号，然后和入参版本比对，返回补丁包下载链接和新版本号。
php代码逻辑如下：

```
$appVersion = $_GET['appVersion'];
$fileDir = "hot_patches";

function checkAvaliblePatchesByVersion($version, $fileDir){
    $result = '';
    //1、首先先读取文件夹
    $temp=scandir($fileDir);
    //遍历文件夹
    foreach($temp as $v){
       $a = $fileDir.'/'.$v;
       if(is_dir($a)){//如果是文件夹则执行

           if($v=='.' || $v=='..'){//判断是否为系统隐藏的文件.和..  如果是则跳过否则就继续往下走，防止无限循环再这里。
               continue;
           }
           return checkAvaliblePatchesByVersion($a);//因为是文件夹所以再次调用自己这个函数，把这个文件夹下的文件遍历出来
       }else{

         $ext = pathinfo($a, PATHINFO_EXTENSION);
         $baseName = pathinfo($a, PATHINFO_BASENAME);
         $dirName = pathinfo($a, PATHINFO_DIRNAME);
         $filename = str_replace(strrchr($baseName, "."),"",$baseName);

         if ($ext == 'patched') {
           //将文件名转成数组，以_分割
           $arr = explode('_', $filename);
           if (count($arr) >= 2) {
             //倒数第2个字符串：
             $oldVersion = str_replace("V","",strtoupper($arr[count($arr)-2]));
             //倒数第1个字符串：
             $newVersion = str_replace("V","",strtoupper($arr[count($arr)-1]));

             if ($oldVersion == $version) {
               $currDir = 'http://'.$_SERVER['SERVER_NAME'].':'.$_SERVER['SERVER_PORT'].dirname($_SERVER['PHP_SELF']);
               //返回完整的下载URL
               $url = $currDir.'/'.$a;
               $result = array(
               'patchUrl' => $url,
               'newVersion' => $newVersion,
               );
               break;
             }
           }
         }
       }

    }
    return $result;
}

$result = checkAvaliblePatchesByVersion($appVersion, $fileDir);
$response = array(
 'code' => 200,
 'message' => 'success for request',
 'data' => $result,
 );
//echo $result."<br>";
echo json_encode($response);
return json_encode($response);
```
![image.png](https://upload-images.jianshu.io/upload_images/1413134-c5237ccdc6c9fd0c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**日常补丁更新维护**

1.终端命令行：
biff [oldzip_path] [newzip_path] [生成的补丁输出目录]

2.将 生成的补丁包版本放入上图中的hot_patches目录下即可

整个RN差量热更新方案大致就是这样，也经过实测通过。此间前后花了4天时间，连php脚本都是现学现用的。特此记录一下研究过程。

最后，附上我的研究的成果，我上传至我的github上了：https://github.com/GithubXkw1573/RN_BiffHot
如果我的方案成果对你有所帮助，请给个star吧，谢谢~
