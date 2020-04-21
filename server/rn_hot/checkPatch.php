<?php
# @Author: kaiweixu
# @Date:   2020-04-16 5:17:29 pm
# @Email:  xukaiwei@aecg.com.cn
# @Project: react_native_aecg
# @Last modified by:   kaiweixu
# @Last modified time: 2020-04-17 2:39:25 pm
# @Copyright: Nalong.tecnology.com

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

 ?>
