# 发布记录

## V1.1

- 发布类型：为爱发电免费版更新
- 更新内容：配对界面增加 VPN 权限证书签名提示；壁纸下载完成后提示“壁纸已加载到导入栏，请手动导入”。
- 兼容说明：V1 系列内置 LocalDevVPN 回环，签名证书需要包含 VPN / Network Extension（Packet Tunnel）权限；市面上的常见付费签名证书基本都可以，但以证书实际权限为准。
- 已测试系统：iOS 27.0 Beta 4、iOS 27.0 正式版、iOS 27.2。
- 版本号：`1.1 (build 2)`
- 源码基线：`3de57d6`
- 已验证文件：`AirCard-Wallpaper-iOS-V1.1-正式版-为爱发电-未签名.ipa`
- 已验证文件 SHA-256：`62BEC514580A992CDB2E32847129D01A69A2292485F2BCCD6B76C3B78773DE97`
- 详细说明：[`V1.1-说明.md`](V1.1-说明.md)

## V1.0（正式版）

- 发布类型：为爱发电免费版
- 发布日期：2026-09-24
- 功能基线：iOS 27 正式版壁纸资源下载、AirCard 导入、内置 LocalDevVPN 回环配对
- 商业功能：不包含卡密、会员或授权限制
- 源码基线：`fee38b6`（移除卡密系统后的免费版）
- 已验证文件：`AirCard-Wallpaper-iOS-为爱发电免费版-未签名.ipa`
- 已验证文件 SHA-256：`459DCB3DE905490BBDFEC39DEF58806A10FD6845DD66C2FB0850037A2912D148`

V1.0 构建使用 `MARKETING_VERSION: "1.0"` 和
`CURRENT_PROJECT_VERSION: "1"`；当前正式构建已更新为 V1.1。
