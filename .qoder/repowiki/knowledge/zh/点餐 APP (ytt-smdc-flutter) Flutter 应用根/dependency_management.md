## 1. 使用的系统/方式

本项目是一个 Flutter 应用，依赖管理由三层构成：

- **Dart/Flutter 层**：使用 `pub` 包管理器，通过根目录的 `pubspec.yaml` 声明，`pubspec.lock` 锁定具体版本。
- **Android 原生层**：使用 Gradle（`android/app/build.gradle`），但当前 `dependencies {}` 为空，所有原生依赖均由 Flutter 插件间接引入；构建工具链（NDK、Java 17）在 Gradle 中固定。
- **iOS 原生层**：使用 CocoaPods，通过 `ios/Podfile` 声明平台与 pod 安装流程，未自定义 Podsource。

没有发现私有 Dart registry、私有 Maven/CocoaPods source 或 vendored 第三方源码。依赖来源均为公共仓库（pub.dev、CocoaPods Specs、flutter/plugins）。CI 侧通过 Codemagic (`codemagic.yaml`) 执行打包，但未见额外的依赖源配置。

## 2. 关键文件

| 文件 | 作用 |
|---|---|
| `pubspec.yaml` | Flutter/Dart 依赖、SDK 约束、资源清单 |
| `pubspec.lock` | Dart 依赖锁定（由 `flutter pub get` 生成） |
| `android/app/build.gradle` | Android 构建配置、NDK/Java 版本、签名、ProGuard |
| `android/build.gradle` / `android/settings.gradle` / `android/gradle.properties` | Gradle 工程级配置（Gradle wrapper 由 Flutter 脚手架提供） |
| `ios/Podfile` | iOS 平台版本、CocoaPods 安装入口 |
| `codemagic.yaml` | CI 云构建脚本（触发 `flutter build` / `pod install`） |

## 3. 架构与约定

### Dart 依赖（`pubspec.yaml`）

- SDK 约束为 `>=3.4.0 <4.0.0`，Flutter 约束为 `>=3.19.0`。
- 业务网络库使用 `dio ^5.9.0`，状态管理用 `provider ^6.1.2`，路由用 `fluro ^2.0.5`，本地数据库用 `sqflite ^2.3.0`，MQ 客户端用 `dart_amqp ^0.3.0`。
- 依赖版本风格混合：部分使用 caret（如 `dio: ^5.9.0`），部分使用精确版本（如 `common_utils: 2.1.0`、`sp_util: 2.0.3`、`mobile_scanner: ^6.0.2` 等），无统一的版本策略文档。
- 所有 Flutter SDK 依赖（`flutter`、`flutter_test`）以 `sdk: flutter` 引用，不指定版本号。
- 发布开关 `publish_to: "none"`，表明该工程不向 pub.dev 发布。
- 字体资源通过 `flutter.fonts` 声明 `RobotoThin`，其余静态资源（图片、HTML、SVG）集中在 `assets/` 下并在 `flutter.assets` 中列出。

### Android 依赖

- `android/app/build.gradle` 中 `dependencies {}` 为空块——所有 Android 原生依赖均通过 Flutter 插件（如 `sqflite`、`webview_flutter`、`image_picker` 等）间接拉取。
- NDK 版本固定为 `28.2.13676358`，Java 兼容级别固定为 `VERSION_17`。
- 签名信息从 `app/key.properties` 读取，release/debug 均使用同一签名配置。
- ProGuard/R8 开启（`minifyEnabled true`、`shrinkResources true`），规则文件为 `proguard-rules.pro`。

### iOS 依赖

- `ios/Podfile` 设置最低部署目标为 `platform :ios, '15.5'`，注释说明是为满足 `mobile_scanner 6.0.11` 的要求。
- 默认 CocoaPods source（github.com/CocoaPods/Specs.git）被注释掉，未启用镜像源；但通过 `ENV['COCOAPODS_DISABLE_STATS'] = 'true'` 关闭了 CocoaPods 统计上报。
- 使用 `use_frameworks! :linkage => :static` 以静态框架链接。
- `post_install` 中强制将低于 `15.5` 的 target deployment target 提升到 `15.5`。
- 未自定义 `Podfile.local` 或私有 repo。

## 4. 约定与约束

- **Dart 依赖统一通过 `pubspec.yaml` 声明**：所有第三方 Dart 包集中列于 `dependencies` 与 `dev_dependencies`，无 `dependency_overrides`。
- **Dart 版本锁定**：`pubspec.lock` 存在并纳入版本控制（由 git 跟踪），用于保证 CI 与本地复现一致。
- **Flutter SDK 版本约束**：通过 `environment.flutter: ">=3.19.0"` 限定，但无 `fvm` 或 `.fvmrc`，开发者需自行确保 Flutter 版本。
- **Android 原生零直接依赖**：`android/app/build.gradle` 的 `dependencies` 为空，所有原生库依赖都走 Flutter 插件通道，避免 Android 侧重复声明。
- **iOS 最低版本 15.5 为硬性约束**：Podfile 中通过 `post_install` 强制修正低于 15.5 的 target，并在注释中明确引用 `mobile_scanner` 的要求。
- **不发布到公共仓库**：`pubspec.yaml` 中的 `publish_to: "none"` 是明确的发布约束。
- **未发现私有注册表或 vendoring**：未配置 `pubspec.yaml` 的 `repositories`、未设置 `GOOGLE_MAVEN_METADATA_URL` 或 `PUB_HOSTED_URL`，也未见 `vendor/`、`third_party/` 或私有 CocoaPods source。