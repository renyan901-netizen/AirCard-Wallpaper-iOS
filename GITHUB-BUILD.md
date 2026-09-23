# 无 Mac 构建 IPA

## 1. 上传到 GitHub

在 GitHub 新建一个空仓库，然后把整个 `AirCard-Wallpaper-iOS` 文件夹上传。需要保留这些目录和文件：

- `.github/workflows/build-ipa.yml`
- `AirCard-iOS.xcodeproj`
- `AirliftFFI.xcframework`
- `ios-app`
- `build-ipa.sh`

## 2. 运行云端构建

打开仓库的 `Actions` 页面，选择 `Build AirCard-Wallpaper IPA`，点击 `Run workflow`。构建完成后，在运行结果底部下载：

`AirCard-Wallpaper-iOS-unsigned`

压缩包内的 `AirCard-iOS.ipa` 就是编译产物。

## 3. Windows 自签安装

下载 IPA 后，用你已有的自签工具重新签名并安装。当前工作流只负责编译，不保存 Apple 证书，也不会把签名密钥上传到 GitHub。

## 4. 真机验证

安装后依次验证：LocalDevVPN 回环、系统设置配对、资源页列表、下载 `.tendies`、Wallpapers 页导入和 Flash。

资源页下载必须先请求 `free_unlock_grant.php`，再请求 `get_download_url.php`。授权 `card_id` 使用 `Base64URL("<原始 card_id>|<Unix 时间戳秒>")`，下载地址请求使用原始数字 `card_id`；两个请求必须使用同一个 32 位十六进制 `device_fp`。直接跳过授权会返回 `ad_unlock_required`。
