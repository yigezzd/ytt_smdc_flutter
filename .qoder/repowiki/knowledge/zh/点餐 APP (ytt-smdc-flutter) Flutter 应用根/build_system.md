## 概述

本项目是 Flutter 3.19+ 点餐应用，构建体系以 `pubspec.yaml` 为单一入口，结合 Android Gradle、iOS CocoaPods、Windows PowerShell 脚本以及 Codemagic 云端流水线完成跨平台编译、签名和产物命名。

## 核心文件与职责

- `pubspec.yaml`：声明 Dart SDK/Flutter 版本约束（`>=3.4.0 <4.0.0` / `>=3.19.0`）、依赖、`flutter:` 资源与字体、以及 `version: 1.0.0+1` 的语义化版本号（`major.minor.patch+buildNumber`）。
- `android/app/build.gradle`：Android 应用 Gradle 配置。使用 `com.android.application` + `dev.flutter.flutter-gradle-plugin` + Kotlin；`compileSdkVersion 36`、`targetSdkVersion 35`、`minSdkVersion flutter.minSdkVersion`、`ndkVersion 28.2.13676358`、Java 17；从 `local.properties` 读取 `flutter.versionCode` / `flutter.versionName`，从 `app/key.properties` 加载 release 签名信息；debug/release 均启用 `signingConfig release`、`shrinkResources`、`zipAlignEnabled`、`minifyEnabled` 并引用 `proguard-rules.pro`。
- `android/build.gradle`：统一 Maven 仓库源（阿里云公共/Gradle/Central/Google、mavenCentral、jitpack.io），根 buildDir 指向项目级 `../build`，注册 `clean` 任务删除该目录。
- `ios/Podfile`：CocoaPods 配置，`platform :ios, '15.5'`，通过 `ENV['COCOAPODS_DISABLE_STATS'] = 'true'` 关闭分析统计以提升构建速度；`post_install` 中强制所有 Pod 的 `IPHONEOS_DEPLOYMENT_TARGET >= 15.5`，以满足 `mobile_scanner 6.0.x` 的要求。
- `build_apk.ps1`：本地 Windows APK 构建脚本。从 `pubspec.yaml` 解析 `version`（支持 `x.y.z+build` 格式），执行 `flutter build apk --release --split-per-abi --dart-define=FULL_VERSION=$fullVersion`，仅保留 `app-arm64-v8a-release.apk` 并重命名为 `ytt_smdc_flutter_<fullVersion>.apk`。
- `build_ipa.ps1`：本地 Windows 辅助脚本，用于处理 Codemagic 产出的 `.ipa`。自动在 `.`、`build\ios`、`Downloads` 中搜索最新 ipa，按相同版本号逻辑重命名为 `ytt_smdc_flutter_<fullVersion>.ipa`，并输出 Sideloadly 安装步骤说明。
- `codemagic.yaml`：Codemagic 云构建工作流 `ios-test-build`，使用 `flutter: stable` + `cocoapods: default`，依次执行 `flutter pub get` → `flutter build ios --release --no-codesign` → 将 `Runner.app` 打包为 `ytt_smdc_flutter_<VERSION>.ipa` 作为 artifact 上传；注释说明该流程产出无签名包，由本地 Sideloadly 用免费 Apple ID 重新签名（7 天有效期）。

## 架构与约定

1. **版本号来源**：`pubspec.yaml` 中的 `version` 字段是单一事实源。Android 侧通过 `local.properties` 注入 `flutter.versionCode` / `flutter.versionName`；PowerShell 脚本通过正则 `^([^+]+)\+(.+)$` 将 `x.y.z+build` 展开为 `x.y.z.build` 作为最终文件名后缀，并通过 `--dart-define=FULL_VERSION=$fullVersion` 注入到运行时。
2. **Android 构建**：采用新版 Gradle Plugin DSL（`plugins {}` + `android { }`），启用 R8/ProGuard 压缩混淆，默认 debug 也使用 release 签名以便 `flutter run --release` 可直接运行。
3. **iOS 构建**：不直接在 Windows 上编译 iOS；通过 Codemagic 云端 macOS 环境执行 `flutter build ios --release --no-codesign`，本地再用 Sideloadly 自签安装。
4. **产物命名规范**：APK 与 IPA 均以 `ytt_smdc_flutter_<version>.<ext>` 形式输出，便于分发归档。
5. **依赖仓库镜像**：Android Gradle 优先使用阿里云镜像加速下载；CocoaPods 源码镜像被注释掉，但通过禁用 stats 减少网络开销。

## 约束与规则

- Dart SDK 必须满足 `>=3.4.0 <4.0.0`，Flutter 必须 `>=3.19.0`（由 `pubspec.yaml` environment 约束）。[source: `pubspec.yaml`]
- Android 编译需 Java 17（`sourceCompatibility/targetCompatibility VERSION_17`）且 NDK 固定为 `28.2.13676358`。[source: `android/app/build.gradle`]
- Android `local.properties` 需提供 `flutter.versionCode` 与 `flutter.versionName`，否则回退为 `1` / `1.0`。[source: `android/app/build.gradle`]
- Android release 签名凭据位于 `android/app/key.properties`（`keyAlias` / `keyPassword` / `storeFile` / `storePassword`），debug 也复用 release 签名。[source: `android/app/build.gradle`]
- iOS 最低部署目标为 `15.5`，任何 Pod 低于此值会在 `post_install` 中被强制提升。[source: `ios/Podfile`]
- `flutter build apk` 使用 `--split-per-abi` 生成多架构 APK，脚本仅保留 `arm64-v8a`，其余架构产物会被删除。[source: `build_apk.ps1`]
- Codemagic 工作流产出的是 `--no-codesign` 未签名 ipa，必须由本地 Sideloadly 重新签名后安装。[source: `codemagic.yaml`]
- `flutter_test` 作为 dev_dependency 引入，单元测试使用 `test ^1.16.8`；黄金测试 (`flutter_goldens`) 当前被注释掉。[source: `pubspec.yaml`]