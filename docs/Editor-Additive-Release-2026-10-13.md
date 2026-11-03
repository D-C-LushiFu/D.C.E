# 编辑器功能追加发布（2026-10-13）

## Windows

- 新增正式入口：`E:\D.C.E\export\release\windows\bin\D.C.E.exe`。
- 原 `DCE.exe` 保留；SHA256 仍为 `6E75ACC4F0663FCA7D692E9BBE8FA377B6A020FEA295E16CBC16677FD9A30A07`。
- 新程序大小 64,488,448 字节，SHA256 `A479ACBC41DBDDCE133BB903DCC745984ADC81A77EBB9FEB58C8FAD15AEAF5E9`。
- 保持 app.file=DCE，因此新增入口继续使用既有 Windows 存档及设置路径。
- 按现有 Windows 发布流程编译（officialBuild、legacy_gc_compare），未切换 hxcpp 全局配置。
- 只新增或合并 18 个文件：1 个程序、2 张缺失图片、4 个缺失键位配置、10 个语言文件、1 个资源索引。
- 10 个语言文件原字节内容全部保留，只在末尾追加缺失键。
- 资源索引原 860 个条目及元数据逐项核对一致，只新增 2 张图片的索引。
- 原有 3,375 个模组、插件、回放及键位文件的路径、大小、修改时间均保持一致。
- 正式目录游戏内确认引擎下拉框、4/1 波形及顶部历史入口。截图：`_build/editor-release-additive/screenshots/formal-engine-menu.png`、`formal-chart-4to1.png`、`formal-history.png`。
- 测试后已恢复用户设置和既有运行诊断文件。最后一次试玩截图捕获到其他前台窗口，未作为游戏验证证据。

## Android

- 新增交付 APK：`E:\D.C.E\_release\D.C.E.apk`。
- 应用名 D.C.E.，包名 `com.DCEEngine`，版本 1.2.2，versionCode 35260921。
- ARM64（arm64-v8a），minSdk 21，targetSdk / compileSdk 36。
- APK 大小 446,329,372 字节。
- SHA256：`0109AB98187C466F41EC9B14BC5AFA7B542FAE998F0840B233C5E49F6758FBBD`。
- Gradle `BUILD SUCCESSFUL`，APK v1 / v2 签名验证通过。
- 按用户要求，移动端 DebugMonitor 调试面板默认关闭，禁用其键盘快捷键，且 Android 目标的 mountOverlay 不包含创建面板的代码；桌面 Ctrl+F3 保留。
- 生成的 Android C++ 已确认 overlayEnabled=false、keysConfig=off(mobile)、mountOverlay 为空。未声称完成手机 UI 实测。

## Redmi K70 推送安装

- 已连接设备型号标识 23113RKC6C，Android 16。
- APK 已推送至 `/sdcard/Download/D.C.E.apk`。
- ADB 安装返回 `Success`，系统包信息确认 versionName=1.2.2、versionCode=35260921。
- 安装前不存在 com.DCEEngine，本次为新增应用；未改动手机上原有 NovaFlare 等应用。
- 严格按照用户“只是推送安装”的要求，没有启动游戏或进行手机 UI 操作。

## 可复核记录

- 构建脚本：`tools/build-editor-release.cmd`。
- Windows 日志：`_build/editor-release-additive/build-windows.log`。
- Android 日志：`_build/editor-release-additive/build-android-final.log`。
- 追加清单及旧文件备份：`_build/editor-release-additive/installed.json`、`backup/`。
- 手机安装日志：`_build/editor-release-additive/phone-install.log`。

## Android 启动与 Freeplay 追加修复

原 Android 包在权限授予后触发了游戏创建前的身份检查崩溃。追加修复包为 `_release/D.C.E-Android-Update.apk`，已更新安装并推送到手机 Download。新增存储根目录、权限等待与中文提示，合并此前漏入的 Freeplay 功能。此前的 APK 保留作历史产物，不能作为启动修复版本使用。

详见 `Android-Startup-Permission-Fix-2026-10-13.md` 与 `Android-Refresh-Rate-Audit-2026-10-13.md`。实际屏幕仍为 60Hz，高刷问题未解决；引擎绘制计数不构成屏幕高刷验证。Windows 可执行文件未在此次 Freeplay 合并后重编译。
